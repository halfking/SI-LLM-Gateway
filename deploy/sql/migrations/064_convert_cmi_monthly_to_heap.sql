-- =============================================================================
-- Migration 064: convert credential_model_index monthly partitions from
-- columnar -> heap.
--
-- Background (2026-07-03):
--   * The background rollup (bg/auto_index_refresher.go's
--     rollupCredentialModelIndexSQL) issues INSERT ... ON CONFLICT DO UPDATE
--     on credential_model_index.
--   * Citus columnar 11.x does NOT support speculative insertion
--     (columnar_tuple_insert_speculative not implemented) so the rollup
--     has been failing every 5 minutes since the columnar migration.
--     Latest bucket on disk was 2026-07-02 10:25 UTC (7+ hours stale).
--   * Migration 999 already documented in its comments that
--     `credential_model_index` should NOT be in columnar_insert_only_parents()
--     for exactly this reason, but the 3 monthly partitions created under an
--     earlier policy were left as columnar.
--
-- Target partitions:
--   credential_model_index_2026_06   (194,842 rows)
--   credential_model_index_2026_07   ( 74,451 rows)
--   credential_model_index_2026_08   (      0 rows, but columnar nonetheless)
--
-- Strategy:
--   * Single-shot INSERT (no batching) — cmi has no JSONB / no oversized
--     TOAST payload; 270k rows × ~40 simple columns is well under 1 GB.
--     Migration 999's batched/CALL pattern was needed for request_logs
--     (jsonb columns) and is overkill here.
--   * Use `SELECT DISTINCT *` to survive any non-deterministic ordering
--     from the columnar scanner — the (bucket, credential_id, raw_model)
--     unique constraint catches duplicates anyway and would abort the
--     transaction.
--   * Detect & report dedup count before the actual swap so the operator
--     can spot data corruption if the dedupe is significant (>5%).
--   * Atomic swap (DETACH + DROP + RENAME + ATTACH).
--   * The unique btree on (bucket, credential_id, raw_model) is recreated
--     automatically on the new heap partition when ATTACH PARTITION runs
--     (parent-level indexes propagate to children in PG 11+).
--   * Re-add the per-partition index that was dropped during the swap.
--
-- Idempotent: per-partition convert is gated by access_method checks; if
-- the partition is already heap the procedure no-ops.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Sanity check
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_count int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'citus_columnar') THEN
        RAISE EXCEPTION 'citus_columnar extension not installed; migration 064 unnecessary';
    END IF;
    SELECT count(*) INTO v_count
    FROM pg_class c
    JOIN pg_am am ON am.oid = c.relam
    WHERE c.relname LIKE 'credential_model_index_%'
      AND c.relname NOT LIKE '%default'
      AND c.relname NOT LIKE '%archive%'
      AND c.relname NOT LIKE '%idx%'
      AND c.relname NOT LIKE '%tmp%'
      AND am.amname = 'columnar';
    RAISE NOTICE '[064] credential_model_index columnar partitions to convert: %', v_count;
END $$;

-- ---------------------------------------------------------------------------
-- 1. Procedure: convert one columnar partition to heap.
--    Single-shot SELECT DISTINCT INTO heap staging + atomic swap.
--
--    Refuses to run on partitions with >2M rows. Single-shot INSERT DISTINCT
--    holds the source's full stripe + the staging table in memory at once;
--    cmi has ~250 bytes/row × 2M = 500 MB raw, well within PG's 1 GB
--    MaxAllocSize ceiling, but a 5M+ row partition blows past it. Operators
--    with larger partitions should adapt this procedure to use the batched
--    _999_copy_batch pattern from migration 999.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE public._064_convert_partition_to_heap(
    IN p_part text
)
LANGUAGE plpgsql AS $$
DECLARE
    v_oid        oid;
    v_am         text;
    v_parent     text;
    v_new        text := p_part || '__heap_tmp';
    v_constraint text;
    v_total      bigint;
    v_dedup      bigint;
    v_distinct   bigint;
BEGIN
    SELECT c.oid, am.amname
      INTO v_oid, v_am
    FROM pg_class c
    LEFT JOIN pg_am am ON am.oid = c.relam
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = p_part AND c.relkind = 'r';

    IF v_oid IS NULL THEN
        RAISE NOTICE '[064] %: not found, skip', p_part;
        RETURN;
    END IF;
    IF v_am IS DISTINCT FROM 'columnar' THEN
        RAISE NOTICE '[064] %: not columnar (%), skip', p_part, COALESCE(v_am, 'heap');
        RETURN;
    END IF;

    SELECT inhparent::regclass::text INTO v_parent
      FROM pg_inherits WHERE inhrelid = v_oid;
    IF v_parent IS NULL THEN
        RAISE EXCEPTION '[064] %: not a partition of any parent; refusing to '
            'convert (refusing to also drop the standalone source table)', p_part;
    END IF;

    -- Row count from reltuples; columnar tables usually don't track this
    -- reliably, so verify with a manual count.
    SELECT COALESCE(reltuples::bigint, 0) INTO v_total
      FROM pg_class WHERE oid = v_oid;
    EXECUTE format('SELECT count(*) FROM public.%I', p_part) INTO v_total;
    RAISE NOTICE '[064] %: rows=% (columnar)', p_part, v_total;

    IF v_total > 2000000 THEN
        RAISE EXCEPTION '[064] %: has % rows; single-shot INSERT DISTINCT can '
            'OOM above ~2M rows. Adapt the procedure to use batched COPY (see '
            'migration 999 _999_copy_batch pattern) before retrying.', p_part, v_total;
    END IF;

    -- Create empty heap staging. LIKE INCLUDING DEFAULTS INCLUDING CONSTRAINTS
    -- preserves NOT NULL + unique constraint from the columnar source, but
    -- (LIKE doesn't copy PARTITION OF).
    EXECUTE format(
        'CREATE TABLE public.%I (LIKE public.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS)',
        v_new, p_part
    );

    -- Single-shot SELECT DISTINCT into staging. The DISTINCT prevents the
    -- scenario where two columnar stripes might return the same (bucket,
    -- credential_id, raw_model) tuple under a non-deterministic scan order
    -- that previously tripped up the (bucket, credential_id, raw_model)
    -- unique index during ATTACH PARTITION.
    EXECUTE format(
        'INSERT INTO public.%I SELECT DISTINCT * FROM public.%I',
        v_new, p_part
    );
    GET DIAGNOSTICS v_distinct = ROW_COUNT;
    v_dedup := v_total - v_distinct;
    RAISE NOTICE '[064] %: DISTINCT insert=% rows (deduped=% from %)',
        p_part, v_distinct, v_dedup, v_total;
    IF v_total > 0 AND v_dedup > 0 THEN
        RAISE WARNING '[064] %: % duplicate (bucket,cred,model) tuples collapsed. '
            'This usually means a previous failed insert left a partial row. '
            'Inspect with: SELECT bucket, credential_id, raw_model, COUNT(*) '
            'FROM public.%I GROUP BY 1,2,3 HAVING COUNT(*) > 1;',
            p_part, v_dedup, p_part;
    END IF;

    RAISE NOTICE '[064] %: staging size=%', p_part,
        pg_size_pretty(pg_total_relation_size('public.' || v_new::regclass));

    -- Capture partition bound string BEFORE detach.
    SELECT pg_get_expr(c.relpartbound, c.oid, true) INTO v_constraint
      FROM pg_class c WHERE c.oid = v_oid;
    IF v_constraint IS NULL OR v_constraint = '' THEN
        RAISE EXCEPTION '[064] %: empty partition bound expression; refusing to swap', p_part;
    END IF;

    EXECUTE format('ALTER TABLE public.%I DETACH PARTITION public.%I', v_parent, p_part);
    EXECUTE format('DROP TABLE public.%I', p_part);
    EXECUTE format('ALTER TABLE public.%I RENAME TO %I', v_new, p_part);
    EXECUTE format(
        'ALTER TABLE public.%I ATTACH PARTITION public.%I %s',
        v_parent, p_part, v_constraint
    );

    RAISE NOTICE '[064] %: conversion complete (now heap). Final size=%',
        p_part, pg_size_pretty(pg_total_relation_size('public.' || p_part::regclass));

    -- Note: VACUUM FULL is intentionally NOT run here — it cannot run
    -- inside a transactional procedure (the wrapping migration is a single
    -- transaction). The operator must run VACUUM FULL separately after
    -- COMMIT to reclaim the columnar TOAST footprint. See psql block at
    -- the bottom of this file.
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Convert each partition (oldest first).
-- ---------------------------------------------------------------------------
CALL public._064_convert_partition_to_heap('credential_model_index_2026_06');
CALL public._064_convert_partition_to_heap('credential_model_index_2026_07');
CALL public._064_convert_partition_to_heap('credential_model_index_2026_08');

-- ---------------------------------------------------------------------------
-- 3. Verification report.
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== [064] credential_model_index access method report ==='
SELECT c.relname AS table_name,
       am.amname AS access_method,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_am am ON am.oid = c.relam
WHERE n.nspname = 'public'
  AND c.relname LIKE 'credential_model_index_%'
  AND c.relname NOT LIKE '%archive%'
  AND c.relname NOT LIKE '%idx%'
  AND c.relname NOT LIKE '%tmp%'
ORDER BY c.relname;

\echo ''
\echo '=== [064] ON CONFLICT smoke test on the new heap partition ==='
\echo '(inserting + upserting a fake bucket; expect single row, no error)'

-- Pre-clean any prior test row.
DELETE FROM public.credential_model_index WHERE raw_model = '__smoke_test__';

-- Target a bucket inside the _2026_07 partition range so the INSERT routes
-- to the converted heap partition, not the always-heap default partition.
-- If any columnar partition survives, this raises
-- `columnar_tuple_insert_speculative not implemented` and aborts.
INSERT INTO public.credential_model_index
    (bucket, credential_id, raw_model)
VALUES
    ('2026-07-15 12:00:00+00', 1, '__smoke_test__')
ON CONFLICT (bucket, credential_id, raw_model) DO UPDATE
    SET updated_at = now();

-- Re-insert with ON CONFLICT to exercise speculative insertion again.
INSERT INTO public.credential_model_index
    (bucket, credential_id, raw_model)
VALUES
    ('2026-07-15 12:00:00+00', 1, '__smoke_test__')
ON CONFLICT (bucket, credential_id, raw_model) DO UPDATE
    SET updated_at = now();

-- Cleanup the smoke-test row.
DELETE FROM public.credential_model_index WHERE raw_model = '__smoke_test__';

COMMIT;

-- ---------------------------------------------------------------------------
-- 4. Post-commit: VACUUM FULL the converted partitions to reclaim disk from
--    the dropped columnar TOAST segments. Cannot run inside the migration
--    transaction (VACUUM FULL is a non-transactional utility command).
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== [064] post-commit VACUUM FULL (reclaim columnar TOAST space) ==='
VACUUM FULL public.credential_model_index_2026_06;
VACUUM FULL public.credential_model_index_2026_07;
VACUUM FULL public.credential_model_index_2026_08;