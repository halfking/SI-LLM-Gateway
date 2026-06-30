-- Migration 057: denormalize provider_model onto request_logs (2026-06-30)
--
-- Phase 2 (P1) of the /request-logs slow-query fix. Migration 056 added
-- the indexes the LATERAL needed; this migration ELIMINATES the LATERAL
-- entirely for the read path by writing the computed value at INSERT
-- time. Read path then becomes a single index lookup instead of a
-- LEFT JOIN LATERAL with 4-CASE ORDER BY + LIMIT 1 per row.
--
-- What we do:
--   1. Add the column to request_logs (no DEFAULT, metadata-only ALTER,
--      online-safe on a partitioned table).
--   2. Backfill existing rows in batches via the script under
--      scripts/backfill_request_logs_provider_model.sh so the read
--      path can fall back to the LATERAL during the backfill window
--      (admin/logs.go uses COALESCE(rl.provider_model, mo_pick.provider_model)).
--   3. Add a partial index on provider_model for the few UI paths that
--      filter on it (top-models, debugging).
--
-- Companion changes:
--   - db/db.go EnsureRequestLogSchema (mirror of 1 and 3)
--   - db/request_logs_archive_schema.go (column on archive tier; see
--     comment below on why the archive dynamic-intersection archiver
--     requires both sides).
--   - deploy/sql/migrations/910_request_logs_archive.sql (same column)
--   - scripts/backfill_request_logs_provider_model.sh (chunked backfill)
--   - telemetry/provider_model.go (Go helper for write path)
--   - telemetry/client.go + admin/telemetry.go (call helper, write
--     column on INSERT).
--   - admin/logs.go (read path: prefer rl.provider_model, fall back to
--     LATERAL during the backfill window).

-- ----------------------------------------------------------------------------
-- 1) ADD COLUMN — metadata-only on PG 11+ partitioned tables; no rewrite.
-- ----------------------------------------------------------------------------
-- No DEFAULT: rows that pre-date the migration stay NULL until the
-- backfill script catches up. The read path (admin/logs.go) uses
-- COALESCE(rl.provider_model, mo_pick.provider_model) so NULL rows still
-- return correct data via the existing LATERAL path.
ALTER TABLE public.request_logs
    ADD COLUMN IF NOT EXISTS provider_model text;

-- ----------------------------------------------------------------------------
-- 2) Partial index — supports the few queries that filter by
--    provider_model and the (rare) debugging join on it.
-- ----------------------------------------------------------------------------
-- Most list-page queries do NOT filter by provider_model directly; the
-- partial index keeps the index small (~hundreds of distinct values
-- per tenant, not the full row count).
CREATE INDEX IF NOT EXISTS idx_request_logs_provider_model
    ON public.request_logs (provider_model, ts DESC)
    WHERE provider_model IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 3) Backfill is intentionally NOT done in this migration file.
-- ----------------------------------------------------------------------------
-- The LATERAL below is identical to the one in admin/logs.go so the
-- values match byte-for-byte. Running it inline here would lock the
-- table for the duration of the scan, which on a 100M+ row table is
-- unacceptable. Instead, scripts/backfill_request_logs_provider_model.sh
-- walks it in 10k-row batches using an UPDATE … WHERE id BETWEEN … AND
-- … pattern, with a configurable sleep between batches so production
-- traffic is unaffected.
--
-- The reference LATERAL (for documentation only — DO NOT run as-is):
--
--   UPDATE request_logs r
--   SET provider_model = pm.provider_model
--   FROM (
--     SELECT r2.id,
--            COALESCE(
--              NULLIF(TRIM(mo.outbound_model_name), ''),
--              NULLIF(TRIM(mo.raw_model_name), '')
--            ) AS provider_model
--     FROM request_logs r2
--     LEFT JOIN models_canonical mc ON mc.id = r2.canonical_id
--     LEFT JOIN LATERAL (
--       SELECT mo.outbound_model_name, mo.raw_model_name
--       FROM model_offers mo
--       WHERE mo.credential_id = r2.credential_id
--         AND (
--           (r2.canonical_id IS NOT NULL AND mo.canonical_id = r2.canonical_id)
--           OR (
--             r2.canonical_id IS NULL AND (
--               lower(mo.standardized_name) = lower(COALESCE(mc.canonical_name, r2.client_model, ''))
--               OR lower(mo.raw_model_name)   = lower(COALESCE(r2.outbound_model, r2.client_model, ''))
--             )
--           )
--         )
--       ORDER BY
--         CASE WHEN r2.outbound_model IS NOT NULL
--                AND lower(COALESCE(NULLIF(TRIM(mo.outbound_model_name),''), TRIM(mo.raw_model_name)))
--                   = lower(r2.outbound_model) THEN 0 ELSE 1 END,
--         CASE WHEN NULLIF(TRIM(mo.outbound_model_name), '') IS NOT NULL THEN 0 ELSE 1 END,
--         CASE WHEN lower(TRIM(mo.raw_model_name))
--                 <> lower(TRIM(COALESCE(mo.standardized_name, mc.canonical_name, r2.client_model, '')))
--              THEN 0 ELSE 1 END,
--         mo.available DESC NULLS LAST,
--         mo.id DESC
--       LIMIT 1
--     ) mo ON TRUE
--     WHERE r2.id = r.id AND r2.provider_model IS NULL
--   ) pm
--   WHERE r.id = pm.id;

COMMENT ON COLUMN request_logs.provider_model IS
'Denormalized provider_model (mirrors the LATERAL on `model_offers` in admin/logs.go). Set at INSERT time by telemetry/provider_model.go:resolveProviderModel. Falls back to the LATERAL during the backfill window via COALESCE in the read path. NULL for legacy rows until the chunked backfill (scripts/backfill_request_logs_provider_model.sh) catches up.';