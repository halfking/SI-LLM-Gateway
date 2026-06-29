package bg

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PickProbeResult is the value type returned by PickProbeModelForCredential.
type PickProbeResult struct {
	Model  string
	Source string
}

// featuredRow is the per-binding row pulled from the credential's available
// model list. probeModel is what the upstream API actually accepts
// (outbound_model_name with raw_model_name fallback); candidateName is the
// standardized/canonical name used to match against routing_policy.featured_models.
type featuredRow struct {
	probeModel    string
	candidateName string
}

// PickProbeModelForCredential implements the 5-level fallback algorithm
// (manual > request_logs > featured > domestic_random > empty).
// Skips credentials with source='manual' (already pinned by admin).
//
// Used by both:
//   - admin.ProviderDetailView.pickDefaultProbeModel (admin on-demand pick)
//   - bg.DefaultProbePicker.repickAll (daily 0:00 batch)
func PickProbeModelForCredential(ctx context.Context, db *pgxpool.Pool, credID int) (PickProbeResult, error) {
	var (
		currModel  string
		currSource string
		status     string
		lifecycle  string
		manual     bool
	)
	err := db.QueryRow(ctx, `
		SELECT COALESCE(default_probe_model, ''),
		       COALESCE(default_probe_model_source, ''),
		       status, lifecycle_status, COALESCE(manual_disabled, FALSE)
		FROM credentials WHERE id = $1
	`, credID).Scan(&currModel, &currSource, &status, &lifecycle, &manual)
	if err != nil {
		return PickProbeResult{}, err
	}

	if currSource == "manual" && currModel != "" {
		return PickProbeResult{Model: currModel, Source: "manual"}, nil
	}
	if status != "active" || lifecycle != "active" || manual {
		return PickProbeResult{}, nil
	}

	// Priority 1: most-used client_model in request_logs (7d)
	var topModel string
	err = db.QueryRow(ctx, `
		SELECT client_model
		FROM request_logs
		WHERE credential_id = $1
		  AND ts > now() - interval '7 days'
		  AND status_code = 200
		  AND client_model IS NOT NULL
		GROUP BY client_model
		ORDER BY count(*) DESC
		LIMIT 1
	`, credID).Scan(&topModel)
	if err == nil && topModel != "" {
		if bindingAvailableForModel(ctx, db, credID, topModel) {
			return PickProbeResult{Model: topModel, Source: "auto:request_log"}, nil
		}
	}

	// Priority 2: domestic provider random
	var domestic bool
	err = db.QueryRow(ctx, `
		SELECT p.domestic
		FROM credentials c JOIN providers p ON p.id = c.provider_id
		WHERE c.id = $1
	`, credID).Scan(&domestic)
	if err != nil {
		return PickProbeResult{}, err
	}
	if domestic {
		// Priority 3a (2026-06-29 审计修复): 在该凭据可用模型中匹配
		//   routing_policy.featured_models 列表（标准模型名）。
		//   - featured_models 存的是 standardized_name（标准模型名），
		//     由 admin/routing.go PATCH /api/routing/featured-models 维护。
		//   - 优先匹配 pm.standardized_name，未映射时回退到
		//     pm.canonical_id → mc.canonical_name，再回退到 pm.raw_model_name。
		//   - 目的：避免在 30+ 模型中随机挑中冷门模型 → 单点抖动导致
		//     整凭据被标 unreachable/auth_failed → 路由空集雪崩。
		//   - 排序按 featured_models 在数组中的位置，
		//     业务方在数组里靠前的 = 优先级更高。
		//
		// The SQL pushes a list of (probe_model, candidate_name) tuples to
		// Go, then pickFeaturedModelName selects the highest-priority match
		// per featured_models ordering. Doing the sort in Go keeps the
		// algorithm testable without a live DB (see shared_pick_test.go).
		rows, qerr := db.Query(ctx, `
			SELECT
			    COALESCE(NULLIF(pm.outbound_model_name, ''), pm.raw_model_name) AS probe_model,
			    COALESCE(NULLIF(pm.standardized_name, ''),
			             mc.canonical_name,
			             pm.raw_model_name) AS candidate_name
			FROM credential_model_bindings cmb
			JOIN provider_models pm ON pm.id = cmb.provider_model_id
			LEFT JOIN models_canonical mc ON mc.id = pm.canonical_id
			CROSS JOIN routing_policy pol
			WHERE pol.tenant_id = 'default'
			  AND cmb.credential_id = $1
			  AND cmb.available = TRUE
			  AND cmb.unavailable_reason IS DISTINCT FROM 'manual'
			  AND pm.available = TRUE
			  AND pm.unavailable_reason IS DISTINCT FROM 'manual'
		`, credID)
		if qerr != nil {
			return PickProbeResult{}, qerr
		}
		var featured []string
		if scanErr := db.QueryRow(ctx,
			`SELECT COALESCE(featured_models, ARRAY[]::TEXT[])
			 FROM routing_policy WHERE tenant_id = 'default' ORDER BY id LIMIT 1`,
		).Scan(&featured); scanErr != nil {
			rows.Close()
			return PickProbeResult{}, scanErr
		}
		var available []featuredRow
		for rows.Next() {
			var r featuredRow
			if err := rows.Scan(&r.probeModel, &r.candidateName); err != nil {
				continue
			}
			available = append(available, r)
		}
			rows.Close()
			// Check rows.Err() before falling back — a database error mid-scan
			// should be returned, not silently absorbed into the fallback path.
			if err := rows.Err(); err != nil {
				return PickProbeResult{}, err
			}
			if picked := pickFeaturedModelName(available, featured); picked != "" {
				return PickProbeResult{Model: picked, Source: "auto:featured"}, nil
			}

		// Priority 3b: featured 没命中 → 退到原逻辑（随机）。
		//   保留以兼容 admin 没有维护 featured_models 的旧凭据，
		//   或该凭据上的所有模型都不在 featured 列表里。
		candidates := make([]string, 0, len(available))
		for _, r := range available {
			candidates = append(candidates, r.probeModel)
		}
		if len(candidates) > 0 {
			pick := pickRandomCandidate(candidates, time.Now().UnixNano())
			return PickProbeResult{Model: pick, Source: "auto:domestic_random"}, nil
		}
	}

	return PickProbeResult{}, nil
}

// pickFeaturedModelName returns the probe_model of the highest-priority
// candidate whose candidate_name appears in the featured list, or "" if
// no candidate matches.
//
// Priority is the position of candidate_name inside featured (lower index
// = higher priority). When the same name appears multiple times among
// candidates (e.g. multiple bindings all mapped to the same standardized
// name), the first occurrence in `available` order wins — this is a
// deterministic tie-breaker that keeps the choice stable across retries
// when bindings come back from the DB in credential_model_bindings.id
// order (the SQL ORDER BY in production is implicit).
func pickFeaturedModelName(available []featuredRow, featured []string) string {
	if len(available) == 0 || len(featured) == 0 {
		return ""
	}
	// Build position lookup. Use first occurrence (defensive: admins should
	// not put duplicates in featured_models, but if they do, the earlier
	// one wins).
	pos := make(map[string]int, len(featured))
	for i, name := range featured {
		if _, dup := pos[name]; dup {
			continue
		}
		pos[name] = i
	}
	bestPos := len(featured) + 1
	bestProbe := ""
	for _, r := range available {
		p, ok := pos[r.candidateName]
		if !ok {
			continue
		}
		// Lower position = higher priority. Equal-position ties keep the
		// first occurrence in `available` order (the for-range naturally
		// gives us this — only update on strictly lower p).
		if p < bestPos {
			bestPos = p
			bestProbe = r.probeModel
		}
	}
	return bestProbe
}

// pickRandomCandidate returns one of the candidates deterministically
// driven by salt. Wrapping the modulo here keeps it mockable from tests
// and isolates the time import from the SQL path.
func pickRandomCandidate(candidates []string, salt int64) string {
	if len(candidates) == 0 {
		return ""
	}
	return candidates[salt%int64(len(candidates))]
}

func bindingAvailableForModel(ctx context.Context, db *pgxpool.Pool, credID int, model string) bool {
	var ok bool
	err := db.QueryRow(ctx, `
		SELECT EXISTS(
		    SELECT 1 FROM credential_model_bindings cmb
		    JOIN provider_models pm ON pm.id = cmb.provider_model_id
		    WHERE cmb.credential_id = $1
		      AND pm.raw_model_name = $2
		      AND cmb.available = TRUE
		      AND cmb.unavailable_reason IS DISTINCT FROM 'manual'
		      AND pm.available = TRUE
		      AND pm.unavailable_reason IS DISTINCT FROM 'manual'
		)
	`, credID, model).Scan(&ok)
	return err == nil && ok
}
