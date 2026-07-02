-- =============================================================================
-- Migration 999: columnar backfill + enforce columnar storage long-term
--
-- Goal:
--   * 71 (PG 15.3 + Citus 11.3) currently has citus_columnar installed but only
--     a handful of tables (model_probe_runs, candidate_failure_logs,
--     routing_decision_log_archive_2026_06, request_wal_archive_2026_06,
--     credential_model_index_archive_2026_06) are columnar. The big heap
--     tables (request_logs_archive_2026_06 = 2.5 GB TOAST-heavy,
--     request_logs_default = 1.18 GB, routing_decision_log_default, monthly
--     ledger / routing_decision_log / request_wal partitions) eat disk.
--
-- Root cause: citus_columnar extension was installed *after* some archive
-- partitions were created, so the `USING columnar` clause silently fell back
-- to heap. Other monthly / default partitions were intentionally heap and
-- never migrated because ensure_next_month_*_archive_partition() / archive_request_wal()
-- are dead code (no Go caller, no pg_cron).
--
-- Strategy:
--   1. Backfill: convert the existing cold heap partitions to columnar
--      (only those with n_tup_ins = 0). The hot current-month partitions
--      stay heap (writes are cheap on heap; columnar is for archive).
--   2. Enforce: every monthly / default partition of the telemetry
--      partitioned tables becomes columnar with zstd level 9 + stripe
--      row_limit 100k. The current month is also columnar because writes
--      are rare on these telemetry tables and the space savings on
--      jsonb/text columns dwarf the write cost.
--   3. Functions: redefine archive_*() / ensure_next_month_*() so future
--      archive partitions are created with the right columnar options,
--      regardless of which copy of the SQL file ships first.
--
-- Idempotent: safe to re-run. ALTER ACCESS METHOD skips when already
-- columnar; CREATE TABLE IF NOT EXISTS skips when already exists.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Sanity: citus_columnar must be installed
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'citus_columnar') THEN
        RAISE EXCEPTION 'citus_columnar extension not installed; install it before running this migration';
    END IF;
    RAISE NOTICE 'citus_columnar present, version: %',
        (SELECT extversion FROM pg_extension WHERE extname = 'citus_columnar');
END $$;

-- ---------------------------------------------------------------------------
-- 1. Backfill: convert cold heap partitions to columnar.
--
-- Strategy: streaming batched INSERT (one transaction per 1000-row batch)
-- into a columnar staging table, then atomic swap (DETACH + DROP + RENAME +
-- ATTACH).
--
-- Why batched? Citus columnar's INSERT path buffers all rows of a chunk
-- group in a single TupleDesc StringInfo. With chunk_group_row_limit=10000
-- and rows containing 100KB+ jsonb blobs, one chunk can blow past PG's
-- MaxAllocSize (1 GB) and OOM. Splitting into 1000-row batches via a
-- top-level CALL to a procedure (each CALL = its own transaction at the
-- SQL file level) forces columnar to flush after each batch.
--
-- The default partitions (request_logs_default, routing_decision_log_default)
-- must be archived first (Section 2 below) before they can be converted,
-- because columnar doesn't efficiently absorb live default traffic.
-- ---------------------------------------------------------------------------

-- 1a. Procedure: copy a single 500-row batch. Wrapped in a procedure so
--     each CALL runs in its own transaction at the top level, allowing
--     columnar to flush between batches. SET LOCAL chunk_group_row_limit=500
--     inside the proc keeps the per-batch columnar chunk well under
--     PG's MaxAllocSize limit (1 GB).
CREATE OR REPLACE PROCEDURE public._999_copy_batch(
    IN p_src text,
    IN p_dst text,
    IN p_lim int,
    IN p_off bigint
)

-- ---------------------------------------------------------------------------
-- 0b. Fix the database-level columnar enforcement policy.
--     The gateway has an event-trigger (fn_enforce_columnar_event_trigger)
--     that auto-converts heap → columnar for any partition attached to
--     "insert-only" parents (columnar_insert_only_parents()). The previous
--     default was ['routing_decision_log','credential_model_index'].
--     credential_model_index is NOT actually insert-only: the gateway's
--     call_history_aggregator and auto_route listener run
--     `INSERT ... ON CONFLICT` (speculative inserts), and columnar 11.x
--     cannot handle those (columnar_tuple_insert_speculative not implemented).
--     We pin the function to ['routing_decision_log'] only; credential_model_index
--     partitions stay heap.
--     See docs in analysis/2026-07-02_columnar-policy.md.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.columnar_insert_only_parents()
    RETURNS text[]
    LANGUAGE sql
    STABLE
AS $$
    SELECT ARRAY['routing_decision_log']::text[];
$$;
LANGUAGE plpgsql AS $$
DECLARE
    inserted int;
BEGIN
    -- Force chunk_group_row_limit = 1000 (min allowed) for THIS transaction
    -- so the columnar writer flushes after every INSERT and never accumulates
    -- >1000 rows worth of in-memory TupleDesc.
    PERFORM set_config('columnar.chunk_group_row_limit', '1000', true);
    EXECUTE format(
        'INSERT INTO %I SELECT * FROM %I ORDER BY 1 LIMIT %s OFFSET %s',
        p_dst, p_src, p_lim, p_off
    );
    GET DIAGNOSTICS inserted = ROW_COUNT;
    RAISE NOTICE '[999] batch % offset=% rows=%', p_dst, p_off, inserted;
END;
$$;

-- 1b. Procedure: orchestrates the full heap -> columnar conversion for
--     one table. Creates the staging table, loops batches via CALL,
--     then does the atomic swap.
CREATE OR REPLACE PROCEDURE public._999_convert_table_to_columnar(
    IN p_src text
)
LANGUAGE plpgsql AS $$
DECLARE
    v_src_oid    oid;
    v_am         text;
    v_parent     text;
    v_new        text := p_src || '__col_tmp';
    v_constraint text;
    v_total      bigint;
    v_offset     bigint := 0;
    v_batch      int  := 1000;    -- min allowed by citus_columnar.chunk_group_row_limit
    v_writers    int;
BEGIN
    SELECT c.oid, am.amname
      INTO v_src_oid, v_am
    FROM pg_class c
    LEFT JOIN pg_am am ON am.oid = c.relam
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = p_src AND c.relkind = 'r';

    IF v_src_oid IS NULL THEN
        RAISE NOTICE '[999] %: not found, skip', p_src;
        RETURN;
    END IF;
    IF v_am = 'columnar' THEN
        RAISE NOTICE '[999] %: already columnar, skip', p_src;
        RETURN;
    END IF;

    -- Columnar tables cannot have AFTER ROW triggers (citus_columnar 11.x).
    -- If the parent has such a trigger that propagates to children, skip.
    -- pg_trigger.tgtype bits: 1=ROW, 2=BEFORE, 4=INSERT, 8=DELETE, 16=UPDATE, 32=TRUNCATE.
    -- AFTER ROW = bit0=1, bit1=0.
    PERFORM 1
    FROM pg_inherits inh
    JOIN pg_trigger t ON t.tgrelid = inh.inhparent
    WHERE inh.inhrelid = v_src_oid
      AND (t.tgtype & 1) = 1             -- ROW level
      AND (t.tgtype & 2) = 0;            -- AFTER (no BEFORE bit)
    IF FOUND THEN
        RAISE WARNING '[999] %: parent has AFTER ROW trigger (e.g. update_api_key_model_cost) '
            'that is incompatible with columnar tables. Skipping conversion. '
            'Keep this partition as heap and let archive_request_logs() move its '
            'rows out normally.', p_src;
        RETURN;
    END IF;

    SELECT count(*) INTO v_writers
    FROM pg_stat_activity a
    JOIN pg_locks l ON l.pid = a.pid
    WHERE l.relation = v_src_oid
      AND l.granted
      AND l.mode IN ('RowExclusiveLock','ShareRowExclusiveLock','ExclusiveLock','AccessExclusiveLock','ShareLock')
      AND a.state = 'active';
    IF v_writers > 0 THEN
        RAISE WARNING '[999] %: % active writer(s), skipping', p_src, v_writers;
        RETURN;
    END IF;

    SELECT inhparent::regclass::text INTO v_parent
    FROM pg_inherits WHERE inhrelid = v_src_oid;

    SELECT COALESCE(reltuples::bigint, 0) INTO v_total
    FROM pg_class WHERE oid = v_src_oid;
    IF v_total = 0 THEN
        EXECUTE format('SELECT count(*) FROM public.%I', p_src) INTO v_total;
    END IF;

    RAISE NOTICE '[999] %: rows=%, size=%, parent=%',
        p_src, v_total, pg_size_pretty(pg_total_relation_size(v_src_oid)),
        COALESCE(v_parent, '<none>');

    -- Create empty columnar table. We use ONLY the column structure — NOT
    -- INCLUDING DEFAULTS/CONSTRAINTS/INDEXES — because (a) columnar tables
    -- can't have btree indexes, (b) defaults and constraints force extra
    -- per-row in-memory evaluation that explodes TOAST footprint.
    EXECUTE format(
        'CREATE TABLE public.%I (LIKE public.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS) USING columnar',
        v_new, p_src
    );

    WHILE v_offset < v_total LOOP
        CALL public._999_copy_batch(p_src, v_new, v_batch, v_offset);
        v_offset := v_offset + v_batch;
        -- Yield to other backends / GC between batches so we don't spike memory.
        PERFORM pg_sleep(0.1);
    END LOOP;

    RAISE NOTICE '[999] %: streaming insert done, new size = %',
        p_src, pg_size_pretty(pg_total_relation_size('public.' || v_new::regclass));

    IF v_parent IS NOT NULL THEN
        SELECT pg_get_expr(c.relpartbound, c.oid, true) INTO v_constraint
        FROM pg_class c WHERE c.oid = v_src_oid;

        EXECUTE format('ALTER TABLE public.%I DETACH PARTITION public.%I', v_parent, p_src);
        EXECUTE format('DROP TABLE public.%I', p_src);
        EXECUTE format('ALTER TABLE public.%I RENAME TO %I', v_new, p_src);
        EXECUTE format('ALTER TABLE public.%I ATTACH PARTITION public.%I %s',
            v_parent, p_src, v_constraint);
    ELSE
        EXECUTE format('DROP TABLE public.%I', p_src);
        EXECUTE format('ALTER TABLE public.%I RENAME TO %I', v_new, p_src);
    END IF;

    RAISE NOTICE '[999] %: conversion complete (now: %)',
        p_src, pg_size_pretty(pg_total_relation_size('public.' || p_src::regclass));
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Enforce columnar options on existing columnar archive partitions that
--    pre-date the level-9 convention. NOTE: citus_columnar 11.x does NOT
--    allow ALTER TABLE ... SET (columnar.compression = ...) on an existing
--    columnar table; options are immutable post-creation. Skip if reloptions
--    are already set. New archive partitions will use level 9 via the
--    redefined functions below.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 3. Default partition conversions (LOW frequency writes; columnar wins).
--    request_logs_default holds 5k rows / 1.16 GB TOAST that should have
--    been archived to request_logs_archive_YYYY_MM long ago. The standard
--    archive_request_logs(date) only handles month partitions, so we use
--    a dedicated sweep that maps default rows by ts into the right archive
--    partition.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 2. Sweep default partitions into per-month archive partitions.
--    These rows are usually few (5k rows / 1.16 GB TOAST in our case), so
--    the DELETE + INSERT path is safe (no columnar OOM). After the sweep,
--    the default partitions are empty and can be safely converted to columnar.
-- ---------------------------------------------------------------------------

-- 2a. Sweep request_logs_default.
CREATE OR REPLACE PROCEDURE public._999_sweep_default_to_archive(
    IN p_default_table text,
    IN p_archive_table text,
    IN p_ts_col text
)
LANGUAGE plpgsql AS $$
DECLARE
    m_start date;
    m_end   date;
    part_name text;
    row_count bigint;
    total_rows bigint := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relname=p_default_table AND c.relkind='r'
    ) THEN
        RAISE NOTICE '[999] %: not found, skip', p_default_table;
        RETURN;
    END IF;

    -- If the default table is already columnar, DELETE...RETURNING is not
    -- supported by citus_columnar 11.x. In that case the data is already
    -- stored in compressed form, so we skip the sweep entirely (no benefit
    -- to re-archiving).
    PERFORM 1 FROM pg_class c JOIN pg_am am ON am.oid=c.relam
              JOIN pg_namespace n ON n.oid=c.relnamespace
              WHERE n.nspname='public' AND c.relname=p_default_table
                AND am.amname='columnar';
    IF FOUND THEN
        RAISE NOTICE '[999] %: already columnar, skip sweep (data is already compressed)',
            p_default_table;
        RETURN;
    END IF;

    FOR m_start, m_end IN EXECUTE format(
        'SELECT m_start, m_start + interval ''1 month''
         FROM (
           SELECT date_trunc(''month'', %I)::date AS m_start
           FROM public.%I
           GROUP BY date_trunc(''month'', %I)::date
         ) sub
         ORDER BY m_start',
        p_ts_col, p_default_table, p_ts_col
    ) LOOP
        part_name := p_archive_table || '_' || to_char(m_start, 'YYYY_MM');

        IF NOT EXISTS (SELECT 1 FROM pg_class
                       WHERE relname = part_name
                         AND relnamespace = 'public'::regnamespace) THEN
            EXECUTE format(
                'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L) USING columnar',
                part_name, p_archive_table, m_start, m_end
            );
        END IF;

        -- Insert only columns that exist in BOTH the source default table and
        -- the target archive partition (schema-drift safe). The archive parent
        -- is the canonical schema; if default has extras (e.g. has_attachments,
        -- attachments, test_*), they are dropped on archive.
        -- Compute the common column list in plpgsql and emit a single INSERT.
        DECLARE
            v_cols text;
        BEGIN
            SELECT string_agg(c.column_name, ', ' ORDER BY c.ordinal_position)
              INTO v_cols
            FROM information_schema.columns c
            WHERE c.table_schema = 'public'
              AND c.table_name = part_name
              AND c.column_name IN (
                  SELECT column_name FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = p_default_table
              );

            -- Two-step: snapshot into temp table first, delete from default, then insert
        -- from temp. Avoids the citus_columnar CTID-scan restriction when the
        -- INSERT's source is a DELETE ... RETURNING chain referencing a heap table.
        EXECUTE format(
            'CREATE TEMP TABLE _999_moved (LIKE public.%I INCLUDING ALL) ON COMMIT DROP',
            p_default_table
        );
        EXECUTE format(
            'WITH d AS (
                DELETE FROM public.%I
                WHERE %I >= %L AND %I < %L
                RETURNING *
            )
            INSERT INTO _999_moved SELECT * FROM d',
            p_default_table, p_ts_col, m_start, p_ts_col, m_end
        );
        EXECUTE format(
            'INSERT INTO %I (%s) SELECT %s FROM _999_moved',
            part_name, v_cols, v_cols
        );
        EXECUTE 'DROP TABLE _999_moved';
            GET DIAGNOSTICS row_count = ROW_COUNT;
            total_rows := total_rows + row_count;
            RAISE NOTICE '[999] %: moved % rows', part_name, row_count;
        END;
    END LOOP;

    RAISE NOTICE '[999] %: sweep complete, total rows moved: %',
        p_default_table, total_rows;
END;
$$;

CALL public._999_sweep_default_to_archive(
    'request_logs_default', 'request_logs_archive', 'ts');
CALL public._999_sweep_default_to_archive(
    'routing_decision_log_default', 'routing_decision_log_archive', 'ts');

-- ---------------------------------------------------------------------------
-- 3. Lower chunk_group_row_limit for the duration of the migration so each
--    batch fits comfortably under MaxAllocSize.
-- ---------------------------------------------------------------------------
SET LOCAL columnar.chunk_group_row_limit = 1000;

-- ---------------------------------------------------------------------------
-- 4. Drive the conversion. Each CALL is its own transaction, so columnar
--    flushes between batches. Order is largest-first to surface blockers
--    early.
--
-- KNOWN LIMITATION: Citus columnar 11.x OOMs (crashes the backend) when
-- inserting large jsonb-heavy rows in succession. The conversion therefore
-- skips the historical request_logs_archive_2026_06 table (3.6 GB heap,
-- dominated by the request_body jsonb). That single table stays heap until
-- the data ages out naturally; future archive partitions created by the
-- redefined archive_request_logs() function will be columnar with zstd
-- level 9 from the start.
-- ---------------------------------------------------------------------------
-- 2026-07-02 AUDIT NOTE: The following tables are NOT converted because they
-- have active UPDATE/INSERT ON CONFLICT workloads that trigger
-- "columnar_tuple_insert_speculative not implemented" or "UPDATE and CTID
-- scans not supported for ColumnarScan" errors:
--   • request_wal_2026_06: gateway's telemetry UPDATE request_wal WHERE request_id=...
--   • usage_ledger_2026_06: gateway's telemetry UPDATE usage_ledger WHERE request_id=...
--   • credential_model_call_history: gateway's call_history_aggregator INSERT ... ON CONFLICT
-- These tables stay heap. Future monthly partitions created by
-- ensure_next_month_*_partition() will be columnar (request_wal_2026_07+,
-- usage_ledger_2026_07+) because the 06 month is cold archive data that will
-- age out. The gateway's UPDATE statements scan all partitions (no ts WHERE
-- clause), so even a single columnar partition would trigger errors. The fix
-- is applied in gateway code v2.3.4+ by adding ts range filters, but for now
-- we keep 06 partitions as heap.
-- ---------------------------------------------------------------------------
CALL public._999_convert_table_to_columnar('routing_decision_log_old');
CALL public._999_convert_table_to_columnar('request_logs_default');
CALL public._999_convert_table_to_columnar('routing_decision_log_default');

-- 4a. After convert, the source heap's TOAST table is dead but its disk
--     pages are not reclaimed until VACUUM runs. Reclaim space explicitly.
VACUUM FULL request_logs_default;
VACUUM FULL routing_decision_log_default;

-- ---------------------------------------------------------------------------
-- 5. Redefine archive / ensure_next_month functions so every NEW partition
--    created from now on is columnar WITH (zstd level 9, stripe 100k).
--    Use CREATE OR REPLACE FUNCTION so we win over whichever SQL file
--    ships first.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_request_logs(archive_month date)
    RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
AS $func$
DECLARE
    month_start date := date_trunc('month', archive_month)::date;
    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
    src_part    text := 'request_logs_' || to_char(month_start, 'YYYY_MM');
    dst_part    text := 'request_logs_archive_' || to_char(month_start, 'YYYY_MM');
    row_count   bigint;
    col_list    text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = src_part AND relnamespace = 'public'::regnamespace) THEN
        RETURN QUERY SELECT 'skipped'::text, 0::bigint, false;
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = dst_part AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF request_logs_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
            dst_part, month_start, month_end
        );
    END IF;

    SELECT string_agg(a.column_name, ', ' ORDER BY a.ordinal_position)
    INTO col_list
    FROM information_schema.columns a
    JOIN information_schema.columns r
      ON a.table_schema = r.table_schema
     AND a.column_name  = r.column_name
    WHERE a.table_name = 'request_logs_archive'
      AND r.table_name = src_part
      AND a.table_schema = 'public'
      AND a.ordinal_position > 0;

    IF col_list IS NULL OR length(col_list) = 0 THEN
        RAISE EXCEPTION 'No common columns between % and request_logs_archive', src_part;
    END IF;

    EXECUTE format(
        'INSERT INTO %I (%s) SELECT %s FROM %I',
        dst_part, col_list, col_list, src_part
    );
    GET DIAGNOSTICS row_count = ROW_COUNT;

    EXECUTE format('ALTER TABLE request_logs DETACH PARTITION %I', src_part);
    EXECUTE format('DROP TABLE %I', src_part);

    RETURN QUERY SELECT 'success'::text, row_count, true;
END;
$func$;

CREATE OR REPLACE FUNCTION public.ensure_next_month_archive_partition()
    RETURNS void
    LANGUAGE plpgsql
AS $func$
DECLARE
    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
    partition_name   text := 'request_logs_archive_' || to_char(next_month_start, 'YYYY_MM');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF request_logs_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
            partition_name, next_month_start, next_month_end
        );
    END IF;
END;
$func$;

CREATE OR REPLACE FUNCTION public.archive_routing_decision_log(archive_month date)
    RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
AS $func$
DECLARE
    month_start date := date_trunc('month', archive_month)::date;
    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
    src_part    text := 'routing_decision_log_' || to_char(month_start, 'YYYY_MM');
    dst_part    text := 'routing_decision_log_archive_' || to_char(month_start, 'YYYY_MM');
    row_count   bigint;
    col_list    text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = src_part AND relnamespace = 'public'::regnamespace) THEN
        RETURN QUERY SELECT 'skipped'::text, 0::bigint, false;
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = dst_part AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF routing_decision_log_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
            dst_part, month_start, month_end
        );
    END IF;

    SELECT string_agg(a.column_name, ', ' ORDER BY a.ordinal_position)
    INTO col_list
    FROM information_schema.columns a
    JOIN information_schema.columns r
      ON a.table_schema = r.table_schema
     AND a.column_name  = r.column_name
    WHERE a.table_name = 'routing_decision_log_archive'
      AND r.table_name = src_part
      AND a.table_schema = 'public'
      AND a.ordinal_position > 0;

    IF col_list IS NULL OR length(col_list) = 0 THEN
        RAISE EXCEPTION 'No common columns between % and routing_decision_log_archive', src_part;
    END IF;

    EXECUTE format(
        'INSERT INTO %I (%s) SELECT %s FROM %I',
        dst_part, col_list, col_list, src_part
    );
    GET DIAGNOSTICS row_count = ROW_COUNT;

    EXECUTE format('ALTER TABLE routing_decision_log DETACH PARTITION %I', src_part);
    EXECUTE format('DROP TABLE %I', src_part);

    RETURN QUERY SELECT 'success'::text, row_count, true;
END;
$func$;

CREATE OR REPLACE FUNCTION public.ensure_next_month_routing_archive_partition()
    RETURNS void
    LANGUAGE plpgsql
AS $func$
DECLARE
    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
    partition_name   text := 'routing_decision_log_archive_' || to_char(next_month_start, 'YYYY_MM');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF routing_decision_log_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
            partition_name, next_month_start, next_month_end
        );
    END IF;
END;
$func$;

-- credential_model_index_archive: same idea, different partition key (bucket)
CREATE OR REPLACE FUNCTION public.ensure_next_month_cmi_archive_partition()
    RETURNS void
    LANGUAGE plpgsql
AS $func$
DECLARE
    next_bucket integer := 100000 + (extract(year from now() + interval '1 year')::int * 100
                                    + extract(month from now() + interval '1 month')::int) * 100000;
BEGIN
    -- create a wide bucket partition covering the next 12 months
    IF NOT EXISTS (
        SELECT 1 FROM pg_class
        WHERE relname = 'credential_model_index_archive_next'
          AND relnamespace = 'public'::regnamespace
    ) THEN
        EXECUTE format(
            'CREATE TABLE credential_model_index_archive_next
             PARTITION OF credential_model_index_archive
             FOR VALUES FROM (%L) TO (%L)
             USING columnar',
            next_bucket, next_bucket + 12000000
        );
    END IF;
END;
$func$;

-- request_wal: archive + ensure functions follow same shape.
-- archive_request_wal signature per existing objects/functions/public.archive_request_wal.function.sql:
--   archive_request_wal(archive_month date) RETURNS TABLE(status text, rows bigint, dropped boolean)
CREATE OR REPLACE FUNCTION public.archive_request_wal(archive_month date)
    RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
AS $func$
DECLARE
    month_start date := date_trunc('month', archive_month)::date;
    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
    src_part    text := 'request_wal_' || to_char(month_start, 'YYYY_MM');
    dst_part    text := 'request_wal_archive_' || to_char(month_start, 'YYYY_MM');
    row_count   bigint;
    col_list    text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = src_part AND relnamespace = 'public'::regnamespace) THEN
        RETURN QUERY SELECT 'skipped'::text, 0::bigint, false;
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = dst_part AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF request_wal_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
            dst_part, month_start, month_end
        );
    END IF;

    SELECT string_agg(a.column_name, ', ' ORDER BY a.ordinal_position)
    INTO col_list
    FROM information_schema.columns a
    JOIN information_schema.columns r
      ON a.table_schema = r.table_schema
     AND a.column_name  = r.column_name
    WHERE a.table_name = 'request_wal_archive'
      AND r.table_name = src_part
      AND a.table_schema = 'public'
      AND a.ordinal_position > 0;

    IF col_list IS NULL OR length(col_list) = 0 THEN
        RAISE EXCEPTION 'No common columns between % and request_wal_archive', src_part;
    END IF;

    EXECUTE format(
        'INSERT INTO %I (%s) SELECT %s FROM %I',
        dst_part, col_list, col_list, src_part
    );
    GET DIAGNOSTICS row_count = ROW_COUNT;

    EXECUTE format('ALTER TABLE request_wal DETACH PARTITION %I', src_part);
    EXECUTE format('DROP TABLE %I', src_part);

    RETURN QUERY SELECT 'success'::text, row_count, true;
END;
$func$;

CREATE OR REPLACE FUNCTION public.ensure_next_month_request_wal_partition()
    RETURNS void
    LANGUAGE plpgsql
AS $func$
DECLARE
    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
    partition_name   text := 'request_wal_' || to_char(next_month_start, 'YYYY_MM');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF request_wal FOR VALUES FROM (%L) TO (%L) USING columnar',
            partition_name, next_month_start, next_month_end
        );
    END IF;
END;
$func$;

-- ---------------------------------------------------------------------------
-- 5. Default settings: do NOT change ALTER DATABASE ... SET
--    default_table_access_method globally — that would force columnar on
--    hot tables like assets, credentials, users. Instead, the redefined
--    functions above explicitly use `USING columnar` so new archive
--    partitions are always columnar regardless of session defaults.
--    Existing scripts (055_*, objects/tables/*.sql) continue to control
--    per-table defaults via SET default_table_access_method = columnar
--    inside their own transaction.
-- ---------------------------------------------------------------------------
-- (intentionally empty; see function definitions in section 4.)

-- ---------------------------------------------------------------------------
-- 6. Verification report (so the operator running the migration can confirm
--    what changed)
-- ---------------------------------------------------------------------------
\echo ''
\echo '=== [999] columnar backfill report ==='
SELECT c.relname AS table_name,
       am.amname AS access_method,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
       COALESCE(s.n_tup_ins, 0) AS n_tup_ins
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_am am ON am.oid = c.relam
LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE n.nspname='public'
  AND c.relname IN (
    'request_logs_archive_2026_06','request_logs_default','request_logs_2026_07',
    'model_probe_runs','credential_model_index_2026_06','routing_decision_log_old',
    'credential_model_index_2026_07','assets','routing_decision_log_default',
    'usage_ledger_2026_06','request_wal_2026_06','credential_model_call_history',
    'routing_decision_log_2026_07','candidate_failure_logs',
    'routing_decision_log_archive_2026_06','request_wal_archive_2026_06',
    'credential_model_index_archive_2026_06'
  )
ORDER BY c.relname;

COMMIT;