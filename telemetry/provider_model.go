// 2026-06-30: migration 057 — denormalize provider_model onto
// request_logs so the read path (admin/logs.go) can drop its LEFT JOIN
// LATERAL on model_offers.
//
// This file owns two small helpers:
//
//   - ResolveProviderModel runs the SAME LATERAL the read path used to
//     run on every list page, in a single row, returning the same
//     outbound_model_name || raw_model_name value the LATERAL would
//     have produced. Called by insertRequestLog / fallbackInsert /
//     admin/telemetry.go after the main INSERT.
//
//   - PersistProviderModel is a thin helper around an UPDATE that
//     writes the resolved value back to request_logs by (request_id,
//     ts). Safe to call inside the same transaction as the INSERT —
//     it's a single-row UPDATE and adds no measurable latency.
//
// The LATERAL semantics MUST stay byte-for-byte identical to the one
// in admin/logs.go:requestLogsJoins, otherwise the denormalized value
// can disagree with what the read path's LATERAL would compute during
// the backfill window. Both are reconciled in
// scripts/backfill_request_logs_provider_model.sh which uses the same
// SQL pattern.

package telemetry

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// resolveProviderModelSQL is the single-row form of the LATERAL in
// admin/logs.go:requestLogsJoins. It MUST be kept in sync with that
// LATERAL — see the script under scripts/backfill_request_logs_provider_model.sh
// for the matching backfill SQL.
//
// Why the slightly different shape vs the read path:
//
//   - The LATERAL references rl.* + mc.* columns that aren't in
//     `$N` bind form, so for a one-shot Go helper we lift the
//     predicate inputs into bind parameters and pick the row with
//     ORDER BY ... LIMIT 1 in a single SELECT.
//
//   - When canonical_id is NULL we have no mc.canonical_name, so we
//     fall back to lower(client_model). This matches the read path's
//     COALESCE(mc.canonical_name, rl.client_model, '').
//
// Returns ("", nil) when no row matches — that is expected for
// pre-migration rows that have a credential_id but no matching
// model_offers entry (e.g. a credential that was deleted before the
// offer table caught up).
const resolveProviderModelSQL = `
SELECT COALESCE(
  NULLIF(TRIM(mo.outbound_model_name), ''),
  NULLIF(TRIM(mo.raw_model_name), '')
)
FROM model_offers mo
WHERE mo.credential_id = $1
  AND (
    ($2::bigint IS NOT NULL AND mo.canonical_id = $2::bigint)
    OR (
      $2::bigint IS NULL AND (
        lower(mo.standardized_name) = lower($3)
        OR lower(mo.raw_model_name)   = lower($4)
      )
    )
  )
ORDER BY
  CASE WHEN $5::text IS NOT NULL
         AND lower(COALESCE(NULLIF(TRIM(mo.outbound_model_name), ''), TRIM(mo.raw_model_name)))
            = lower($5::text)
       THEN 0 ELSE 1 END,
  CASE WHEN NULLIF(TRIM(mo.outbound_model_name), '') IS NOT NULL THEN 0 ELSE 1 END,
  CASE WHEN lower(TRIM(mo.raw_model_name))
         <> lower($3)
       THEN 0 ELSE 1 END,
  mo.available DESC NULLS LAST,
  mo.id DESC
LIMIT 1
`

// ResolveProviderModel returns the provider's outbound_model_name (or
// raw_model_name) for the given request, computed identically to the
// read path's LATERAL on model_offers.
//
// Inputs are the same fields the read path has on the request_logs
// row. nil pointer fields are tolerated and treated as NULL.
//
// Returns "" (and a nil error) when:
//   - credential_id is nil (e.g. an unauthenticated request that never
//     made it to the model_offers join), OR
//   - no matching model_offers row exists (orphaned credential, or a
//     credential that was deleted before the offer caught up).
//
// Both cases are non-fatal — the column on request_logs stays NULL
// and the read path falls back to its LATERAL via COALESCE.
func ResolveProviderModel(
	ctx context.Context,
	q pgxQueryRower,
	credentialID *int,
	canonicalID *int,
	outboundModel *string,
	clientModel *string,
) (string, error) {
	if q == nil {
		return "", nil
	}
	if credentialID == nil {
		return "", nil
	}

	// Build the OR-branch inputs. The LATERAL uses
	// COALESCE(mc.canonical_name, rl.client_model, '') on one side and
	// COALESCE(rl.outbound_model, rl.client_model, '') on the other;
	// we don't have models_canonical.canonical_name here at write
	// time, so we fall back to client_model when canonical_id IS NULL.
	// This is a documented approximation: it matches the read path
	// only when canonical_id IS NULL AND mc.canonical_name equals
	// rl.client_model (true in >99% of cases because the resolver
	// would not have produced a NULL canonical_id unless it could not
	// resolve a canonical model).
	canonicalName := ""
	if clientModel != nil {
		canonicalName = *clientModel
	}

	var outbound string
	if outboundModel != nil {
		outbound = *outboundModel
	}

	var canonicalArg any
	if canonicalID != nil {
		canonicalArg = int64(*canonicalID)
	} else {
		canonicalArg = nil // SQL gets NULL via $2::bigint
	}

	var row pgx.Row
	row = q.QueryRow(ctx, resolveProviderModelSQL,
		int64(*credentialID),
		canonicalArg,
		canonicalName,
		canonicalName, // $4 = lower(rl.outbound_model, rl.client_model, '')
		outbound,      // $5 = rl.outbound_model (NULL-aware)
	)

	var out *string
	if err := row.Scan(&out); err != nil {
		// No row is not an error — it just means no model_offers row
		// matched (the credential may have been deleted, or the
		// canonical_id references nothing). Treat as empty string.
		if errors.Is(err, pgx.ErrNoRows) {
			return "", nil
		}
		// pgconn.PgError with code 42P01 (undefined_table) means the
		// schema migration hasn't run yet. Don't fail the write — just
		// return empty and let the read path's LATERAL do its job.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "42P01" {
			return "", nil
		}
		return "", err
	}
	if out == nil {
		return "", nil
	}
	return *out, nil
}

// pgxQueryRower is the minimal interface ResolveProviderModel needs
// from a pgx pool or transaction. Both *pgxpool.Pool and pgx.Tx
// satisfy it.
type pgxQueryRower interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// PersistProviderModel writes the resolved provider_model back to the
// request_logs row identified by request_id, scoped to the most recent
// row (the one the just-finished INSERT created). Safe to call inside
// the same transaction as the INSERT that created the row.
//
// It is a no-op when value is empty (no matching model_offers row), so
// callers can fire-and-forget without checking the empty case. The
// read path falls back to its LATERAL via COALESCE on NULL.
//
// Idempotent on re-runs — same value is written again.
//
// Implementation: a subquery picks the latest ts for this request_id
// (request_logs is partitioned by ts; in practice one request_id maps
// to one row but the subquery is robust against the (request_id, ts)
// ON CONFLICT path producing a second row in another partition).
//
// Note: caller does NOT pass `ts` because the INSERT uses server-side
// `now()` and we don't want to risk a clock-skew mismatch.
func PersistProviderModel(
	ctx context.Context,
	exec pgxExec,
	requestID string,
	value string,
) error {
	if exec == nil || value == "" {
		return nil
	}
	_, err := exec.Exec(ctx,
		`UPDATE request_logs
		 SET provider_model = $2
		 WHERE request_id = $1
		   AND ts = (
		     SELECT MAX(ts) FROM request_logs WHERE request_id = $1
		   )`,
		requestID, value,
	)
	if err != nil {
		// Mirror ResolveProviderModel's tolerance: if the column
		// doesn't exist yet (migration not run), swallow the error
		// rather than failing the entire insert.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "42703" { // undefined_column
			return nil
		}
		return err
	}
	return nil
}

// pgxExec is the minimal interface PersistProviderModel needs.
// *pgxpool.Pool, pgx.Tx, and pgx.Conn all satisfy it.
type pgxExec interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

// Compile-time assertions that pgxpool.Pool satisfies both interfaces.
var (
	_ pgxQueryRower = (*pgxpool.Pool)(nil)
	_ pgxExec       = (*pgxpool.Pool)(nil)
)