-- Migration 065: v_routable_credential_models respects manual_disabled
-- Author: v738 audit 2026-07-03
-- Issue: "可用" provider list showing manually-disabled providers
--
-- Root cause: v_routable_credential_models (migration 017) does not filter
-- on provider.manual_disabled or credential.manual_disabled, so a disabled
-- provider/credential pair can still produce is_routable=true rows. The
-- admin UI /providers page relied on client-side filtering which raced
-- with stale provider.Client candidate caches.
--
-- Fix: Add COALESCE(p.manual_disabled, FALSE) = FALSE AND
-- COALESCE(c.manual_disabled, FALSE) = FALSE to the view WHERE clause. The
-- view already encodes the "manual_priority overrides auto" logic (017)
-- so we just layer the gate on top.
--
-- Deployment: Safe (idempotent CREATE OR REPLACE). The view is read-only;
-- no data changes. Downstream consumers (admin/routing.go handlers) already
-- gate on manual_disabled in their own WHERE clauses (defense-in-depth),
-- so worst-case regression is a single frame showing a disabled provider
-- before the view refresh completes.

CREATE OR REPLACE VIEW public.v_routable_credential_models AS
SELECT
    c.tenant_id,
    c.id AS credential_id,
    c.provider_id,
    p.code AS provider_code,
    p.display_name AS provider_name,
    mo.raw_model_name,
    mo.standardized_name,
    mo.available,
    mo.manual_priority,
    -- 2026-07-03 v738: is_routable now respects manual_disabled. A
    -- manually-disabled provider or credential cannot route traffic
    -- even if all other conditions (available=true, status=active,
    -- enabled=true) are met. This mirrors the in-memory gate in
    -- provider/client.go loadCandidates() and the SQL gates in
    -- admin/routing.go's 5 handlers.
    (
        mo.available = TRUE
        AND c.status = 'active'
        AND p.enabled = TRUE
        -- 017: manual > auto. If manual_priority is set (non-null),
        -- the row is routable regardless of auto weights. Otherwise
        -- it must pass the weight/tier heuristic.
        AND (
            mo.manual_priority IS NOT NULL
            OR (
                COALESCE(mo.weight, 0) > 0
                AND mo.tier IN ('premium', 'standard', 'economy')
            )
        )
        -- v738: manual_disabled gates. COALESCE(..., FALSE) ensures
        -- NULL is treated as "not disabled". Both provider-level and
        -- credential-level flags are checked so either dimension can
        -- block routability.
        AND COALESCE(p.manual_disabled, FALSE) = FALSE
        AND COALESCE(c.manual_disabled, FALSE) = FALSE
    ) AS is_routable
FROM
    model_offers mo
    JOIN credentials c ON c.id = mo.credential_id
    JOIN providers p ON p.id = c.provider_id;

COMMENT ON VIEW public.v_routable_credential_models IS
'v738: Routable credential-model bindings (respects manual_disabled). 
Used by admin/providers.go listProviders to compute per-provider 
routable_binding_count and by admin/routing.go to surface available 
model choices. The is_routable column answers "can this binding route 
traffic right now" — it gates on available=true, status=active, 
enabled=true, manual_priority precedence, AND manual_disabled=false 
for both provider and credential.';
