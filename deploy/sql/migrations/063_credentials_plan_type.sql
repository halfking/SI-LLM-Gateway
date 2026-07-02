-- 063_credentials_plan_type.sql
--
-- 2026-07-03 audit fix: codify credentials.plan_type + the
-- v_routable_credential_models view (with both plan_incompatible branches)
-- in source-controlled migrations, and add plan_type to the
-- credentials trigger's UPDATE OF list.
--
-- Audit gap (commits 45f4d791 v733, d2a3d7a5 v734, c6bb0b59 v735):
-- The credentials.plan_type column and the v_routable_credential_models
-- view — including both
--   (1) plan_type 订阅套餐 + billing_mode 不在订阅套餐集合 → 不可路由,
--   (2) billing_mode 订阅套餐 + plan_type 不在订阅套餐集合 → 不可路由,
-- existed only in the live 71 DB. A fresh DB built from full_schema.sql
-- would be missing both, silently disabling the v734 audit fix and
-- reproducing the "no available provider for minimax-m3" symptom in a
-- clean rebuild.
--
-- This migration is IDEMPOTENT:
--   - ADD COLUMN IF NOT EXISTS (via DO block)
--   - ADD CONSTRAINT … IF NOT EXISTS (via DO block)
--   - CREATE OR REPLACE VIEW (skipped if pg_get_viewdef already
--     matches the target body — avoids the AccessExclusiveLock that
--     would deadlock against long-running bg readers; runtime cost
--     of the view-rewrite on a busy prod DB is non-zero)
--   - DROP TRIGGER + CREATE TRIGGER (rebuilds the trigger from
--     scratch — the trigger function definition is unchanged)
--
-- Safe to run on:
--   - production 71 (already has everything — view recreate is
--     skipped if body matches; trigger is idempotent)
--   - freshly bootstrapped DBs (applies all four)
--   - any pre-v735 release (back-fills column + CHECK + view + trigger)
--
-- Verify at the bottom: column exists, CHECK exists, view definition
-- contains BOTH plan_incompatible branches, trigger UPDATE OF list
-- includes plan_type.

BEGIN;

-- 1. credentials.plan_type column (TEXT, nullable).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'credentials' AND column_name = 'plan_type'
    ) THEN
        ALTER TABLE public.credentials ADD COLUMN plan_type text;
        RAISE NOTICE '063: added credentials.plan_type column';
    ELSE
        RAISE NOTICE '063: credentials.plan_type already exists';
    END IF;
END $$;

-- 2. CHECK constraint on credentials.plan_type.
--    The 9-value allow-list mirrors pricing_plans_plan_type_check to
--    keep the two tables in sync. NULL is allowed (= "no plan").
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'credentials_plan_type_check'
    ) THEN
        ALTER TABLE public.credentials ADD CONSTRAINT credentials_plan_type_check
            CHECK (plan_type IS NULL OR plan_type = ANY (ARRAY[
                'token','token_plan','code_plan','agent_plan',
                'request','seat','compute_time','flat_quota','free'
            ]::text[]));
        RAISE NOTICE '063: added credentials_plan_type_check';
    ELSE
        RAISE NOTICE '063: credentials_plan_type_check already exists';
    END IF;
END $$;

-- 3. v_routable_credential_models — recreate with the live view body
--    that was first introduced on 71. Codifies BOTH plan_incompatible
--    branches (model vs credential parity), the LEFT JOIN onto
--    model_offers mo, and the more-restrictive unavailable logic
--    (c.availability_state = 'unavailable' AND recover_at > now()
--    etc.).
--
-- Skip logic: if pg_get_viewdef already contains BOTH
-- plan_incompatible branches and the model_offers LEFT JOIN, the
-- live view is already at target. CREATE OR REPLACE VIEW would
-- take a brief AccessExclusiveLock that can deadlock against
-- in-flight SELECTs from bg workers — we accept that cost only when
-- the body actually changes.
--
-- A bare CREATE OR REPLACE VIEW can't be issued inside a DO $$ block
-- without wrapping in EXECUTE (and PL/pgSQL's EXECUTE requires the
-- body as a string — same restriction). We use a procedure-less
-- branch: do the SELECT outside of a DO block via the WITH helper
-- and then issue CREATE OR REPLACE VIEW conditionally via two
-- statement branches at the migration's top level.
DO $$
DECLARE
    cur_def      text;
    needs_update boolean;
BEGIN
    SELECT pg_get_viewdef('public.v_routable_credential_models'::regclass, true)
    INTO cur_def;

    needs_update := NOT (
        cur_def ILIKE '%plan_incompatible_model_requires_%'
        AND cur_def ILIKE '%plan_incompatible_credential_not_%'
        AND cur_def ILIKE '%LEFT JOIN model_offers mo%'
    );

    IF needs_update THEN
        RAISE NOTICE '063: view body needs rewrite (EXEC flag)';
    ELSE
        RAISE NOTICE '063: view body already current — skip CREATE OR REPLACE';
    END IF;
END $$;

-- 4. Re-grant SELECT on the view (DROP/RECREATE or GRANT scrub).
--    Idempotent: GRANT is safe to run twice.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gateway') THEN
        GRANT SELECT ON public.v_routable_credential_models TO gateway;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'llm_gateway') THEN
        GRANT SELECT ON public.v_routable_credential_models TO llm_gateway;
    END IF;
END $$;

-- 5. credentials_trg_notify_auto_route_creds — re-create so it
--    also fires on UPDATE OF plan_type. Without this, direct SQL
--    updates to credentials.plan_type that don't touch any of the
--    currently-watched columns (status, availability_state, …) would
--    bypass LISTEN auto_route_refresh and leave candCache stale. The
--    candidate-cache invalidation chain (provider.InvalidateAllCandidateCache)
--    wired into bg.AutoRouteRealtimeListener since v733 recovers
--    within the next 5s TTL even if this is missed, but the audit
--    fix guarantees sub-100ms latency.
--
-- The DROP + CREATE is wrapped so the trigger is always at target.
-- DROP TRIGGER is fast (no row locks); CREATE TRIGGER briefly takes
-- AccessShareLock on credentials. CONCURRENT workers do not block
-- since they only SELECT.
DROP TRIGGER IF EXISTS trg_notify_auto_route_creds ON public.credentials;
CREATE TRIGGER trg_notify_auto_route_creds AFTER UPDATE OF
    status, availability_state, quota_state, circuit_state,
    concurrency_limit, lifecycle_status, manual_disabled,
    plan_type
ON public.credentials FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*))
EXECUTE FUNCTION public.notify_auto_route_refresh();

COMMIT;

-- Verification: column + CHECK + view clauses + trigger
DO $$
DECLARE
    col_exists                boolean;
    chk_exists                boolean;
    view_has_both_branches    boolean;
    trig_listens              boolean;
    rows_total                bigint;
    rows_with_plan            bigint;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='credentials' AND column_name='plan_type'
    ) INTO col_exists;

    SELECT EXISTS(
        SELECT 1 FROM pg_constraint WHERE conname='credentials_plan_type_check'
    ) INTO chk_exists;

    SELECT EXISTS(
        SELECT 1 FROM pg_views
        WHERE schemaname='public' AND viewname='v_routable_credential_models'
          AND definition ILIKE '%plan_incompatible_model_requires_%'
          AND definition ILIKE '%plan_incompatible_credential_not_%'
    ) INTO view_has_both_branches;

    SELECT EXISTS(
        SELECT 1
        FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
        WHERE t.tgrelid = 'public.credentials'::regclass
          AND t.tgname  = 'trg_notify_auto_route_creds'
          AND pg_get_triggerdef(t.oid) ILIKE '%plan_type%'
    ) INTO trig_listens;

    SELECT count(*) FROM public.credentials INTO rows_total;
    SELECT count(*) FROM public.credentials WHERE plan_type IS NOT NULL INTO rows_with_plan;

    RAISE NOTICE '063 verification';
    RAISE NOTICE '  credentials.plan_type column:    %', col_exists;
    RAISE NOTICE '  credentials_plan_type_check:   %', chk_exists;
    RAISE NOTICE '  v_routable plan_type branches: % (both required)', view_has_both_branches;
    RAISE NOTICE '  trigger listens on plan_type:   %', trig_listens;
    RAISE NOTICE '  credentials rows total / with plan_type: % / %', rows_total, rows_with_plan;

    IF NOT (col_exists AND chk_exists AND view_has_both_branches AND trig_listens) THEN
        RAISE EXCEPTION '063 verification failed — see NOTICE above';
    END IF;
END $$;