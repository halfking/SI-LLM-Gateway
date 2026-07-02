-- ===========================================================================
-- Object:   v_routable_credential_models
-- Type:     VIEW
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only); reconciled against the
--           live 71 DB on 2026-07-03 by commit <this commit>.
-- ===========================================================================
-- Name: v_routable_credential_models; Type: VIEW; Schema: public; Owner: -
--
-- v735: codifies the view body that lived only in the live 71 DB until
-- 2026-07-03. Two structural differences vs the original pre-735 view:
--
-- 1. New credentials.plan_type column feeds two CASE branches: the
--    "plan_incompatible_model_requires_<mode>" branch fires when a
--    credential is on a subscription plan (token_plan / code_plan /
--    agent_plan) but the matching model_offer row carries a non-plan
--    billing_mode; the symmetric "plan_incompatible_credential_not_<mode>"
--    fires when a subscription-plan billing_mode is set on an offer for a
--    credential that is NOT on a matching subscription plan. The data
--    migration 2026-07-03-fix-cmb-billing-mode-for-plan-creds.sql made
--    the production data conform to these clauses.
-- 2. model_offers mo is LEFT JOINed in (alongside cmb JOIN pm) so the
--    billing_mode read comes from the model_offers view, not from
--    cmb.billing_mode directly. The view contract: cmb.billing_mode is
--    still authoritative for write paths; model_offers is the published
--    surface and is what the planner reads.
--
-- Pre-v735 versions of this view lived only in the live DB and in the
-- migration's documentation, which led to schema drift: a fresh DB built
-- from this repo's full_schema.sql would silently lose the rule, and the
-- v734 audit fix would have nothing to gate on. Codifying the view here
-- closes that gap. The matching source-of-truth entry in
-- `full_schema.sql` is the post-pg_dump copy at line ~7065.

CREATE VIEW public.v_routable_credential_models AS
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
    mo.billing_mode,
    c.tenant_id,
    c.provider_id,
        CASE
            WHEN c.status <> ALL (ARRAY['active'::text, 'cooling'::text, 'degraded'::text]) THEN false
            WHEN c.lifecycle_status <> 'active'::text THEN false
            WHEN cmb.available IS NOT TRUE THEN false
            WHEN c.quota_state = 'periodic_exhausted'::text THEN false
            WHEN c.quota_state = 'exhausted'::text AND (c.quota_recover_at IS NULL OR c.quota_recover_at > now()) THEN false
            WHEN c.availability_state = 'unavailable'::text AND (c.availability_recover_at IS NULL OR c.availability_recover_at > now()) THEN false
            -- Subscription-plan credentials require the matching
            -- billing_mode on the offer (token_plan / code_plan /
            -- agent_plan only). A subscription billing_mode set on a
            -- regular credential is also rejected (the symmetric
            -- branch). Allows NULL plan_type and non-plan billing_mode
            -- for the "no plan, pay per token" baseline.
            WHEN (c.plan_type = ANY (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) AND (mo.billing_mode <> ALL (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) THEN false
            WHEN (mo.billing_mode = ANY (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) AND (c.plan_type <> ALL (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) THEN false
            ELSE true
        END AS is_routable,
        CASE
            WHEN c.status <> ALL (ARRAY['active'::text, 'cooling'::text, 'degraded'::text]) THEN 'credential_status_'::text || c.status
            WHEN c.lifecycle_status <> 'active'::text THEN 'lifecycle_'::text || c.lifecycle_status
            WHEN cmb.available IS NOT TRUE THEN 'binding_unavailable'::text
            WHEN c.quota_state = 'periodic_exhausted'::text THEN 'quota_periodic_exhausted'::text
            WHEN c.quota_state = 'exhausted'::text THEN 'quota_exhausted'::text
            WHEN c.availability_state = 'unavailable'::text THEN 'availability_unavailable'::text
            WHEN (c.plan_type = ANY (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) AND (mo.billing_mode <> ALL (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) THEN 'plan_incompatible_model_requires_'::text || COALESCE(mo.billing_mode, 'token'::text)
            WHEN (mo.billing_mode = ANY (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) AND (c.plan_type <> ALL (ARRAY['token_plan'::text, 'code_plan'::text, 'agent_plan'::text])) THEN 'plan_incompatible_credential_not_'::text || mo.billing_mode
            ELSE NULL::text
        END AS unavailable_reason
   FROM credential_model_bindings cmb
     JOIN credentials c ON c.id = cmb.credential_id
     JOIN provider_models pm ON pm.id = cmb.provider_model_id
     LEFT JOIN model_offers mo ON mo.credential_id = cmb.credential_id AND mo.raw_model_name = pm.raw_model_name
  WHERE c.tenant_id = 'default'::text;
