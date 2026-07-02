-- 2026-07-03-fix-cmb-billing-mode-for-plan-creds.sql
--
-- Background:
--   credentials.plan_type was changed to token_plan / code_plan / agent_plan
--   for subscription credentials (e.g. minimax-prod-1 id=6, scnet-acrbo3aajx id=14)
--   but credential_model_bindings.billing_mode for those (cred, model) rows
--   remained at the column default 'per_token'. The
--   v_routable_credential_models view rejects these pairs with
--   unavailable_reason = 'plan_incompatible_model_requires_per_token'
--   because its rule 8 expects:
--       WHEN (c.plan_type IN token_plan/code_plan/agent_plan)
--            AND (mo.billing_mode NOT IN token_plan/code_plan/agent_plan)
--       THEN false
--
-- Root cause (request a69a71a05e6610adcf55df32f2618797, follow-up after 45f4d791):
--   Before commit 45f4d791 (candCache staleness fix), cmb.available was FALSE for
--   cred 6 / MiniMax-M3 so the view's earlier clause
--   (WHEN cmb.available IS NOT TRUE THEN 'binding_unavailable') fired first and
--   masked this bug. Once the binding was re-enabled, the plan_incompatible
--   clause became the dominant reason and blocked the route.
--
-- Fix:
--   For every cmb row whose credential is on a subscription plan, mirror
--   c.plan_type into cmb.billing_mode so the view's rule 8 matches.
--   - token_plan creds  -> billing_mode = 'token_plan'
--   - code_plan  creds  -> billing_mode = 'code_plan'
--   - agent_plan creds  -> billing_mode = 'agent_plan'
--   - other creds (plan_type = 'token' or NULL) -> leave alone; they are
--     NOT subject to the rule.
--
-- Safety:
--   - Only updates rows where the current billing_mode does NOT already
--     match the plan_type, so this is idempotent.
--   - Does NOT touch admin_protected / unavailable_reason / available flags.
--   - plan_meta is preserved (kept untouched).
--
-- Run on: 71 production DB
-- Author: gateway team
-- Ticket: request a69a71a05e6610adcf55df32f2618797 follow-up

BEGIN;

-- 1. token_plan credentials: their cmb rows must use billing_mode='token_plan'
UPDATE credential_model_bindings cmb
SET billing_mode = 'token_plan',
    pricing_updated_at = now(),
    updated_at = now()
FROM credentials c
WHERE cmb.credential_id = c.id
  AND c.tenant_id = 'default'
  AND c.plan_type = 'token_plan'
  AND cmb.billing_mode <> 'token_plan';

-- 2. code_plan credentials
UPDATE credential_model_bindings cmb
SET billing_mode = 'code_plan',
    pricing_updated_at = now(),
    updated_at = now()
FROM credentials c
WHERE cmb.credential_id = c.id
  AND c.tenant_id = 'default'
  AND c.plan_type = 'code_plan'
  AND cmb.billing_mode <> 'code_plan';

-- 3. agent_plan credentials
UPDATE credential_model_bindings cmb
SET billing_mode = 'agent_plan',
    pricing_updated_at = now(),
    updated_at = now()
FROM credentials c
WHERE cmb.credential_id = c.id
  AND c.tenant_id = 'default'
  AND c.plan_type = 'agent_plan'
  AND cmb.billing_mode <> 'agent_plan';

-- 4. Verification: report rows affected and the new billing_mode distribution
--    for credentials on subscription plans.
SELECT 'cmb_billing_mode_for_plan_creds_fix' AS check_name,
       (SELECT count(*)
        FROM credential_model_bindings cmb
        JOIN credentials c ON c.id = cmb.credential_id
        WHERE c.plan_type = 'token_plan') AS token_plan_cmb_total,
       (SELECT count(*)
        FROM credential_model_bindings cmb
        JOIN credentials c ON c.id = cmb.credential_id
        WHERE c.plan_type = 'token_plan'
          AND cmb.billing_mode = 'token_plan') AS token_plan_cmb_correct,
       (SELECT count(*)
        FROM credential_model_bindings cmb
        JOIN credentials c ON c.id = cmb.credential_id
        WHERE c.plan_type = 'token_plan'
          AND cmb.billing_mode <> 'token_plan') AS token_plan_cmb_still_wrong;

-- 5. Targeted check on the originally-failing pair
SELECT 'cred6_minimax_m3' AS check_name,
       cmb.available, cmb.billing_mode,
       v.is_routable, v.unavailable_reason
FROM credential_model_bindings cmb
JOIN provider_models pm ON pm.id = cmb.provider_model_id
JOIN credentials c ON c.id = cmb.credential_id
JOIN v_routable_credential_models v
     ON v.credential_id = c.id AND v.raw_model_name = pm.raw_model_name
WHERE c.id = 6 AND pm.raw_model_name = 'MiniMax-M3';

COMMIT;