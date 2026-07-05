#!/bin/bash
# scripts/backfill_request_logs_provider_model.sh — migration 057 backfill
#
# Purpose:
#   Walk request_logs in id batches and compute `provider_model` using
#   the same LATERAL the read path (admin/logs.go) used to use.
#   This is the offline-safe counterpart to the inline UPDATE in
#   deploy/sql/migrations/055_request_logs_upstream_status_code.sql.
#
# Why chunked (not one shot):
#   - request_logs holds 100M+ rows on production
#   - The LATERAL touches model_offers (a JOIN) per candidate row; a
#     single transaction would lock partitions and starve live traffic
#   - 10k rows/batch * ~50ms latency is well under any single INSERT
#     spike; pg's MVCC keeps the table fully writable throughout
#
# Usage (production r112_postgres):
#   docker exec r112_postgres psql -U <user> -d llm_gateway \
#     < <(sed 's/<BATCH_SIZE>/10000/g; s/<SLEEP_MS>/100/g' \
#          scripts/backfill_request_logs_provider_model.sql)
# or run the heredoc directly in psql.
#
# Idempotent: only updates rows where provider_model IS NULL.
# Restartable: the cursor is "id > last_id_seen", so a killed run can
# resume from the next batch.
#
# 2026-07-04: 严格遵守 *_default 写入规则。本脚本的 UPDATE / JOIN 现在
# 只走 request_logs_default（heap）。SELECT 仍然走父表以便聚合检查。
# 这意味着：本脚本只补 *_default 里的 provider_model，不会回填已经
# 迁移到列存分区里的历史数据。这是有意为之——历史数据走迁移工具的
# 二次补数，不要在应用层动列存表。

set -euo pipefail

cat <<'SQL'
-- ============================================================================
-- Backfill: provider_model column on request_logs (migration 057)
-- ============================================================================
-- Walk in id order, 10k rows per batch, sleeping 100ms between batches
-- so production inserts aren't starved. Only updates rows where
-- provider_model IS NULL, so the script is idempotent and restartable.
--
-- Adjust the batch size and sleep at the bottom of this script before
-- running if your environment is tight on replication lag or IOPS.

\set ON_ERROR_STOP on
\timing on

DO $$
DECLARE
  batch_size      int := 10000;     -- rows per UPDATE
  sleep_ms        int := 100;       -- sleep between batches
  last_id         bigint := -1;     -- resume cursor
  rows_updated    int;
  total_updated   bigint := 0;
  start_ts        timestamptz := clock_timestamp();
  iter            int := 0;
BEGIN
  LOOP
    -- 2026-07-04: SELECT on *_default (only heap rows; columnar partitions
    -- are intentionally excluded from the cursor's id-space).
    WITH next_batch AS (
      SELECT id
      FROM request_logs_default
      WHERE provider_model IS NULL
        AND id > last_id
      ORDER BY id ASC
      LIMIT batch_size
      FOR UPDATE SKIP LOCKED
    ),
    computed AS (
      SELECT r.id,
             COALESCE(
               NULLIF(TRIM(mo.outbound_model_name), ''),
               NULLIF(TRIM(mo.raw_model_name), '')
             ) AS provider_model
      FROM next_batch nb
      -- 2026-07-04: JOIN on *_default so the result set is consistent.
      JOIN request_logs_default r ON r.id = nb.id
      LEFT JOIN models_canonical mc ON mc.id = r.canonical_id
      LEFT JOIN LATERAL (
        SELECT mo.outbound_model_name, mo.raw_model_name
        FROM model_offers mo
        WHERE mo.credential_id = r.credential_id
          AND (
            (r.canonical_id IS NOT NULL AND mo.canonical_id = r.canonical_id)
            OR (
              r.canonical_id IS NULL AND (
                lower(mo.standardized_name) = lower(COALESCE(mc.canonical_name, r.client_model, ''))
                OR lower(mo.raw_model_name)   = lower(COALESCE(r.outbound_model, r.client_model, ''))
              )
            )
          )
        ORDER BY
          CASE WHEN r.outbound_model IS NOT NULL
                 AND lower(COALESCE(NULLIF(TRIM(mo.outbound_model_name), ''), TRIM(mo.raw_model_name)))
                    = lower(r.outbound_model)
               THEN 0 ELSE 1 END,
          CASE WHEN NULLIF(TRIM(mo.outbound_model_name), '') IS NOT NULL THEN 0 ELSE 1 END,
          CASE WHEN lower(TRIM(mo.raw_model_name))
                 <> lower(TRIM(COALESCE(mo.standardized_name, mc.canonical_name, r.client_model, '')))
               THEN 0 ELSE 1 END,
          mo.available DESC NULLS LAST,
          mo.id DESC
        LIMIT 1
      ) mo ON TRUE
    )
    -- 2026-07-04: UPDATE only *_default (heap), never the parent.
    UPDATE request_logs_default r
    SET provider_model = c.provider_model
    FROM computed c
    WHERE r.id = c.id;

    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    total_updated := total_updated + rows_updated;
    iter := iter + 1;

    -- Move cursor forward: max(id) of the just-updated batch. If zero
    -- rows updated, the table is fully backfilled (or no rows match
    -- the WHERE), so exit.
    IF rows_updated = 0 THEN
      RAISE NOTICE 'Backfill complete: % rows updated in % batches (elapsed %)',
        total_updated, iter - 1, clock_timestamp() - start_ts;
      EXIT;
    END IF;

    SELECT MAX(id) INTO last_id FROM computed;

    -- Throttle to avoid starving live writers.
    PERFORM pg_sleep(sleep_ms / 1000.0);

    IF iter % 50 = 0 THEN
      RAISE NOTICE '... % rows updated in % batches (elapsed %)',
        total_updated, iter, clock_timestamp() - start_ts;
    END IF;
  END LOOP;
END $$;

-- Final sanity: how many NULLs remain? (Should be 0 except for rows
-- inserted AFTER the backfill started; those are filled by the write
-- path going forward.)
SELECT
  COUNT(*) FILTER (WHERE provider_model IS NULL) AS remaining_null,
  COUNT(*) AS total
FROM request_logs;
SQL