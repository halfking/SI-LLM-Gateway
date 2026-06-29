-- ============================================================================
-- Migration 921: routing_decision_log_archive (columnar tiered storage)
-- ============================================================================
-- 目标：实现 routing_decision_log heap 主表 + columnar 分区归档表的双层架构
-- 原则：当月数据 heap（高频写入），历史月份 columnar（只读 + 压缩节省空间）
-- 数据流：每月调用 archive_routing_decision_log('YYYY-MM-01') 将主表上月数据迁移到
--        routing_decision_log_archive_<YYYY_MM>（columnar 子分区），然后 DETACH + DROP 主表分区
-- 父表：routing_decision_log_archive (heap, RANGE (ts))
-- 子分区：routing_decision_log_archive_2026_05/06/... (USING columnar)
-- 注意：columnar 表不支持 UPDATE/DELETE，历史数据一旦迁移就只读
-- ============================================================================

BEGIN;

-- 1. 创建归档父表（heap，RANGE 分区，兼容主表结构）
CREATE TABLE IF NOT EXISTS public.routing_decision_log_archive (
    ts timestamp with time zone DEFAULT now() NOT NULL,
    request_id uuid NOT NULL,
    idempotency_key text,
    tenant_id text,
    api_key_id bigint,
    model text NOT NULL,
    chosen_credential_id bigint,
    chosen_provider_id bigint,
    tier smallint,
    candidates_tried smallint,
    latency_ms integer,
    success boolean NOT NULL,
    error_class text,
    prompt_tokens integer,
    completion_tokens integer,
    cost_usd numeric(12,6),
    request_bytes integer,
    response_bytes integer,
    client_model text,
    resolved_raw_model text,
    sticky_hit boolean,
    client_profile text,
    outbound_model text,
    request_mode text,
    identity_hash text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    resolution_path text,
    canonical_model text,
    resolution_raw_models jsonb,
    decision_trace jsonb
) PARTITION BY RANGE (ts);

-- 2. Comment 父表
COMMENT ON TABLE public.routing_decision_log_archive IS
'Tiered storage: columnar partitions for historical routing_decision_log. Monthly partitions use Citus columnar (compressed, read-only). Data flow: monthly archive_routing_decision_log(archive_month) migrates routing_decision_log_YYYY_MM (heap) into routing_decision_log_archive_YYYY_MM (columnar) and drops the source partition. Use UNION ALL across routing_decision_log + routing_decision_log_archive for time-range queries.';

-- 3. RLS policy: tenant isolation (与主表一致)
ALTER TABLE public.routing_decision_log_archive ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive;
CREATE POLICY tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive
    USING ((tenant_id)::text = (public.get_current_tenant())::text);

-- 4. 创建 archive_routing_decision_log 函数（列感知版）
CREATE OR REPLACE FUNCTION public.archive_routing_decision_log(archive_month date)
    RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
    AS $$
DECLARE
    month_start date := date_trunc('month', archive_month)::date;
    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
    src_part    text := 'routing_decision_log_' || to_char(month_start, 'YYYY_MM');
    dst_part    text := 'routing_decision_log_archive_' || to_char(month_start, 'YYYY_MM');
    row_count   bigint;
    partition_existed boolean := false;
    col_list    text;
BEGIN
    -- 1. 检查源分区是否存在
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = src_part AND relnamespace = 'public'::regnamespace) THEN
        RETURN QUERY SELECT 'skipped'::text, 0::bigint, false;
        RETURN;
    END IF;

    partition_existed := true;

    -- 2. 创建目标 columnar 分区（如果不存在）
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = dst_part AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF routing_decision_log_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
            dst_part, month_start, month_end
        );
        RAISE NOTICE 'Created archive columnar partition: %', dst_part;
    END IF;

    -- 3. 构建列交集 (源和目标都有的列)
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

    -- 4. INSERT columnar 用显式列列表（columnar 不会因为列序不同失败）
    EXECUTE format(
        'INSERT INTO %I (%s) SELECT %s FROM %I',
        dst_part, col_list, col_list, src_part
    );
    GET DIAGNOSTICS row_count = ROW_COUNT;
    RAISE NOTICE 'Migrated % rows from % to % (columnar, column-aware)', row_count, src_part, dst_part;

    -- 5. DETACH + DROP 源分区（释放 heap 空间）
    EXECUTE format('ALTER TABLE routing_decision_log DETACH PARTITION %I', src_part);
    EXECUTE format('DROP TABLE %I', src_part);
    RAISE NOTICE 'Dropped source heap partition: %', src_part;

    RETURN QUERY SELECT 'success'::text, row_count, partition_existed;
END;
$$;

COMMENT ON FUNCTION public.archive_routing_decision_log(archive_month date) IS
'Archive one month of routing_decision_log into routing_decision_log_archive (columnar). Column-aware: uses explicit column list, robust against column-order differences between source and target partitions. Drops the source heap partition after migration (releases space). Idempotent: skips if source partition does not exist.';

-- 5. Helper: 创建下个月 columnar 分区（用于下个月初的预创建）
CREATE OR REPLACE FUNCTION public.ensure_next_month_routing_archive_partition()
    RETURNS void
    LANGUAGE plpgsql
    AS $$
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
        RAISE NOTICE 'Pre-created next month columnar partition: %', partition_name;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.ensure_next_month_routing_archive_partition() IS
'Pre-create the next month columnar partition for routing_decision_log_archive. Call this from a cron job or background service at month-end so the columnar partition is ready when archive_routing_decision_log() is called.';

-- 6. 创建统一的分区创建函数（主表 + 归档表）
CREATE OR REPLACE FUNCTION public.create_next_month_routing_partitions()
    RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
    month_suffix     text := to_char(next_month_start, 'YYYY_MM');
    partition_name   text := 'routing_decision_log_' || month_suffix;
BEGIN
    -- 创建主表的下月分区（heap）
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF routing_decision_log FOR VALUES FROM (%L) TO (%L) USING heap',
            partition_name, next_month_start, next_month_end
        );
        RAISE NOTICE 'Created next month heap partition: %', partition_name;
    END IF;
    
    -- 创建归档表的下月分区（columnar）
    PERFORM ensure_next_month_routing_archive_partition();
    
    RAISE NOTICE 'Created routing partitions for %', month_suffix;
END;
$$;

COMMENT ON FUNCTION public.create_next_month_routing_partitions() IS
'Auto-create next month partitions for both routing_decision_log (heap) and routing_decision_log_archive (columnar). Run this on the last day of each month.';

COMMIT;

-- ============================================================================
-- 使用说明
-- ============================================================================

/*
每月自动任务：

1. 每月 1 日凌晨 1:00 - 创建下个月的分区
   SELECT create_next_month_routing_partitions();

2. 每月 1 日凌晨 2:00 - 归档上月的分区
   SELECT archive_routing_decision_log('2026-06-01');

Cron 任务示例：
0 1 1 * * psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT create_next_month_routing_partitions();"
0 2 1 * * psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT archive_routing_decision_log(date_trunc('month', now() - interval '1 month'));"

查询使用：
- 应用代码无需修改，PostgreSQL 自动路由到正确的分区
- WHERE ts >= '2026-06-01' 会自动只扫描相关分区
- columnar 分区只读，不支持 UPDATE/DELETE

跨主表和归档表查询：
SELECT * FROM routing_decision_log WHERE ts >= '2026-05-01'
UNION ALL
SELECT * FROM routing_decision_log_archive WHERE ts >= '2026-05-01'
ORDER BY ts DESC;

存储优化：
- heap: 当月实时数据，支持高频写入
- columnar: 历史归档，5-10x 压缩，只读
- 预计节省 80% 存储空间
*/

-- ============================================================================
-- 结束
-- ============================================================================
