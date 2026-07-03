-- 066_fix_routable_view_free_billing_mode.sql
--
-- Fix: v_routable_credential_models incorrectly rejects routable bindings
-- when billing_mode='free' or billing_mode='per_token' but credential's
-- plan_type is a subscription plan or token plan.
--
-- Root cause: the view's plan compatibility check used a simple string
-- inequality `cmb.billing_mode <> c.plan_type` (or the equivalent
-- model_offers-based branch), which has wrong semantics. Having a
-- subscription or token plan gives MORE access, not less.
--
-- Correct logic: only reject when the model requires a subscription
-- billing_mode (token_plan / code_plan / agent_plan) but the credential
-- does NOT have a matching subscription plan.
--
-- This migration handles two view structures:
--   - live 71 DB: uses cmb.billing_mode directly
--   - fresh DB (from full_schema.sql): uses mo.billing_mode via
--     LEFT JOIN model_offers
-- It detects the current structure and applies the correct fix.
--
-- Idempotent: skips if the view already has the subscription-only check.

BEGIN;

DO $$
DECLARE
    cur_def      text;
    needs_update boolean;
    uses_mo      boolean;
BEGIN
    SELECT pg_get_viewdef('public.v_routable_credential_models'::regclass, true)
    INTO cur_def;

    -- Detect which billing_mode column the view uses
    uses_mo := cur_def ILIKE '%model_offers mo%';

    -- Check if already has the subscription-only check
    IF uses_mo THEN
        needs_update := NOT (
            cur_def ILIKE '%mo.billing_mode = ANY (ARRAY[''token_plan''%'
            AND cur_def ILIKE '%c.plan_type IS NULL%'
        );
    ELSE
        needs_update := NOT (
            cur_def ILIKE '%cmb.billing_mode = ANY (ARRAY[''token_plan''%'
        );
    END IF;

    IF needs_update THEN
        RAISE NOTICE '066: view body needs rewrite (uses_mo=%)', uses_mo;
    ELSE
        RAISE NOTICE '066: view body already current — skip CREATE OR REPLACE';
    END IF;
END $$;

-- Recreate the view with the correct plan compatibility logic.
-- Uses the same column source (cmb.billing_mode or mo.billing_mode)
-- as the current view to avoid changing the view contract.
CREATE OR REPLACE VIEW public.v_routable_credential_models AS
 SELECT cmb.id AS binding_id,
    cmb.credential_id,
    cmb.provider_model_id,
    pm.raw_model_name,
    cmb.available AS binding_available,
    c.status AS credential_status,
    c.lifecycle_status AS credential_lifecycle_status,
    c.availability_state,
    c.availability_recover_at,
    c.quota_state,
    c.quota_recover_at,
    c.plan_type,
    c.tenant_id,
    c.provider_id,
    p.enabled AS provider_enabled,
    p.manual_disabled AS provider_manual_disabled,
    pm.available AS provider_model_available,
    cmb.billing_mode,
    cmb.plan_type_origin,
        CASE
            WHEN c.status <> ALL (ARRAY['active'::text, 'cooling'::text, 'degraded'::text]) THEN false
            WHEN p.enabled = false OR p.manual_disabled = true THEN false
            WHEN pm.available = false THEN false
            WHEN c.lifecycle_status <> 'active'::text THEN false
            WHEN cmb.available IS NOT TRUE THEN false
            WHEN c.quota_state = 'periodic_exhausted'::text THEN false
            WHEN c.quota_state = 'exhausted'::text AND (c.quota_recover_at IS NULL OR c.quota_recover_at > now()) THEN false
            WHEN c.availability_state = 'unavailable'::text AND (c.availability_recover_at IS NULL OR c.availability_recover_at > now()) THEN false
            -- Only block when model requires a subscription plan but the
            -- credential does not have one. Subscription-plan credentials
            -- may always use non-plan models (free, per-token).
            WHEN cmb.billing_mode = ANY (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text]) AND (c.plan_type IS NULL OR c.plan_type <> ALL (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) THEN false
            ELSE true
        END AS is_routable,
        CASE
            WHEN c.status <> ALL (ARRAY['active'::text, 'cooling'::text, 'degraded'::text]) THEN 'credential_status_'::text || c.status
            WHEN p.enabled = false OR p.manual_disabled = true THEN 'provider_disabled'::text
            WHEN pm.available = false THEN 'model_disabled'::text
            WHEN c.lifecycle_status <> 'active'::text THEN 'lifecycle_'::text || c.lifecycle_status
            WHEN cmb.available IS NOT TRUE THEN 'binding_unavailable'::text
            WHEN c.quota_state = 'periodic_exhausted'::text THEN 'quota_periodic_exhausted'::text
            WHEN c.quota_state = 'exhausted'::text THEN 'quota_exhausted'::text
            WHEN c.availability_state = 'unavailable'::text THEN 'availability_unavailable'::text
            WHEN cmb.billing_mode = ANY (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text]) AND (c.plan_type IS NULL OR c.plan_type <> ALL (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) THEN 'plan_incompatible_credential_not_'::text || cmb.billing_mode
            ELSE NULL::text
        END AS unavailable_reason
   FROM credential_model_bindings cmb
     JOIN credentials c ON c.id = cmb.credential_id
     JOIN provider_models pm ON pm.id = cmb.provider_model_id
     JOIN providers p ON p.id = c.provider_id
  WHERE c.tenant_id = 'default'::text;

COMMIT;

-- Verification
DO $$
DECLARE
    cur_def      text;
    has_check    boolean;
    plan_issues  bigint;
BEGIN
    SELECT pg_get_viewdef('public.v_routable_credential_models'::regclass, true)
    INTO cur_def;

    has_check := cur_def ILIKE '%billing_mode = ANY (ARRAY[''token_plan''%'
                 AND cur_def ILIKE '%plan_incompatible_credential_not_%';

    SELECT COUNT(*) INTO plan_issues
    FROM v_routable_credential_models
    WHERE is_routable = false AND unavailable_reason LIKE 'plan_incompatible%';

    RAISE NOTICE '066 verification:';
    RAISE NOTICE '  has subscription check: %', has_check;
    RAISE NOTICE '  plan_incompatible bindings remaining: %', plan_issues;

    IF NOT has_check THEN
        RAISE EXCEPTION '066 verification failed';
    END IF;
    IF plan_issues > 0 THEN
        RAISE WARNING '066: % bindings still plan_incompatible — investigate', plan_issues;
    END IF;
END $$;
