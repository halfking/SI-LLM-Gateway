-- Migration 056: listing-path indexes for /api/logs (2026-06-30)
--
-- Bug context: GET /api/logs (the request-logs page) was taking several
-- seconds to render the default 24h window. Root cause was an
-- unindexable query plan, not a hot row count:
--
--   1. The list endpoint runs a LEFT JOIN LATERAL against the
--      `model_offers` VIEW (which is `credential_model_bindings JOIN
--      provider_models`). The LATERAL subquery has an OR over
--      `mo.canonical_id = $X` and `lower(mo.standardized_name) = ...` /
--      `lower(mo.raw_model_name) = ...`, ordered by 4 CASE expressions
--      then LIMIT 1. Without functional / canonical_id indexes on
--      `provider_models`, the planner was forced into per-row sort +
--      sequential scan of provider_models for every `request_logs`
--      page.
--
--   2. `model_aliases` had NO primary key and NO index on `raw_name`.
--      The `?model=` filter's EXISTS subquery
--      `lower(ma.raw_name) = lower(rl.client_model) AND ma.status='active'`
--      therefore seq-scanned `model_aliases` for every page.
--
--   3. `request_logs` had no plain `(ts DESC)` index. When the caller is
--      not a tenant admin (super-admin perspective, the most common
--      case in the admin UI), the WHERE clause has only
--      `rl.ts BETWEEN $1 AND $2`, so the planner could only rely on
--      partition pruning + the partial `(tenant_id, ts DESC)` index.
--      Under cross-month ranges that index does not advance an ORDER
--      BY ts DESC efficiently.
--
--   4. `credential_model_bindings` had no composite index on
--      `(credential_id, provider_model_id)`. After the `model_offers`
--      view is expanded, the join to `provider_models` is inner; the
--      planner needed a covering index here to keep the LATERAL cheap.
--
-- This migration adds the missing indexes. All of them are
-- idempotent (`CREATE INDEX IF NOT EXISTS`) and online-safe — none
-- rewrite existing data, and PostgreSQL takes only a brief
-- ShareLock on each index creation.
--
-- Companion Go change is in admin/logs.go (split requestLogsSelectCols
-- into list vs detail projections, drop three big JSONB columns from
-- the list response, merge COUNT(*) into the list query as
-- `COUNT(*) OVER ()` to halve the round-trip count).

-- ----------------------------------------------------------------------------
-- 1) provider_models: indexes for the LATERAL predicate columns.
-- ----------------------------------------------------------------------------
-- The LATERAL subquery in admin/logs.go (requestLogsJoins) filters on
-- `mo.canonical_id = rl.canonical_id` (when non-NULL) OR on
-- `lower(mo.standardized_name|raw_model_name) = lower(...)`. Two
-- B-trees + one functional expression index cover all three branches.
CREATE INDEX IF NOT EXISTS idx_provider_models_canonical_id
    ON public.provider_models (canonical_id);

CREATE INDEX IF NOT EXISTS idx_provider_models_lower_standardized_name
    ON public.provider_models (lower(standardized_name));

CREATE INDEX IF NOT EXISTS idx_provider_models_lower_raw_model_name
    ON public.provider_models (lower(raw_model_name));

-- ----------------------------------------------------------------------------
-- 2) credential_model_bindings: composite for the model_offers view join.
-- ----------------------------------------------------------------------------
-- The `model_offers` view (full_schema.sql line 3229) is
--   credential_model_bindings cmb JOIN provider_models pm ON pm.id = cmb.provider_model_id
-- A composite (credential_id, provider_model_id) lets the LATERAL
-- subquery probe by credential_id and reach pm without a separate
-- scan. Partial index keeps it cheap because most rows have a NULL
-- provider_model_id only briefly during inserts.
CREATE INDEX IF NOT EXISTS idx_cmb_credential_provider_model
    ON public.credential_model_bindings (credential_id, provider_model_id);

-- ----------------------------------------------------------------------------
-- 3) model_aliases: primary key + functional index for ?model= filter.
-- ----------------------------------------------------------------------------
-- `model_aliases` previously had only a sequence default on `id`; no
-- PK, no index on `raw_name`. Adding PK first (safe — `id` is already
-- NOT NULL and unique in practice) gives pg_dump a clean handle, then
-- the functional lower(raw_name) index makes the EXISTS subquery in
-- the `?model=` filter (admin/logs.go:332-352) an index probe instead
-- of a seq-scan.
ALTER TABLE public.model_aliases
    ADD CONSTRAINT IF NOT EXISTS model_aliases_pkey PRIMARY KEY (id);

CREATE INDEX IF NOT EXISTS idx_model_aliases_lower_raw_name_status
    ON public.model_aliases (lower(raw_name), status)
    WHERE status = 'active';

-- ----------------------------------------------------------------------------
-- 4) request_logs: plain (ts DESC) for the 24h default window.
-- ----------------------------------------------------------------------------
-- The list endpoint's most common access pattern is
--   WHERE ts BETWEEN $now-24h AND $now ORDER BY ts DESC LIMIT N OFFSET M
-- without any other selective predicate. The existing
-- `idx_request_logs_tenant_ts (tenant_id, ts DESC)` cannot serve this
-- when the caller's tenant_id is 'default' AND the result set spans
-- multiple monthly partitions: the planner falls back to a per-part
-- seq scan + sort. A pure `(ts DESC)` index lets PG use partition
-- pruning + an index-only reverse scan.
--
-- request_logs is PARTITION BY RANGE(ts); on PG 11+ an index created
-- on the parent is automatically propagated to existing and future
-- partitions, so this single statement covers all of
-- request_logs_2026_06, _07, _08, _default, and any future monthly
-- partitions created by ensure_request_logs_partition().
CREATE INDEX IF NOT EXISTS idx_request_logs_ts_desc
    ON public.request_logs (ts DESC);

-- ----------------------------------------------------------------------------
-- Rollback (if needed) — see migration 056.down.sql
-- ----------------------------------------------------------------------------