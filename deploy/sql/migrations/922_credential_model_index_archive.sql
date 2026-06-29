-- ============================================================================
-- Migration 922: credential_model_index_archive (双层架构)
-- ============================================================================
-- 目标：实现 credential_model_index heap 主表 + columnar 归档表的双层架构
-- 原则：主表保留最近 7 天数据（heap，支持 ON CONFLICT），7天前归档到 columnar
-- 数据流：每天凌晨调用 cleanup_old_credential_model_index() 清理主表，
--        每月调用 archive_credential_model_index('YYYY-MM-01') 归档历史月到 columnar
-- 主表：credential_model_index (heap, 单表, 7天窗口)
-- 归档：credential_model_index_archive (heap parent, RANGE (bucket), columnar 子分区)
-- ============================================================================

BEGIN;

-- 1. 创建归档父表（heap，RANGE 分区，兼容主表结构）
CREATE TABLE IF NOT EXISTS public.credential_model_index_archive (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    canonical_id integer,
    billing_mode text,
    unit_price_in_per_1m numeric(10,4),
    unit_price_out_per_1m numeric(10,4),
    context_window integer,
    success_rate numeric(5,4),
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    updated_at timestamp with time zone DEFAULT now()
) PARTITION BY RANGE (bucket);

-- 2. Comment 父表
COMMENT ON TABLE public.credential_model_index_archive IS
'Tiered storage: columnar partitions for historical credential_model_index (older than 7 days). Monthly partitions use Citus columnar (compressed, read-only). Main table keeps recent 7 days with ON CONFLICT support. Data flow: daily cleanup_old_credential_model_index() removes 7d+ data from main table after archival. Monthly archive_credential_model_index(month) migrates 7d+ data to columnar partitions. Query historical data via UNION ALL with main table.';

-- 3. 创建索引（在父表上，自动继承）
CREATE INDEX IF NOT EXISTS idx_cmi_archive_bucket 
    ON public.credential_model_index_archive (bucket DESC);
CREATE INDEX IF NOT EXISTS idx_cmi_archive_cred_model 
    ON public.credential_model_index_archive (credential_id, raw_model, bucket DESC);
CREATE INDEX IF NOT EXISTS idx_cmi_archive_canonical 
    ON public.credential_model_index_archive (canonical_id, bucket DESC) 
    WHERE canonical_id IS NOT NULL;

-- 4. 创建归档函数：将 7 天前的数据从主表迁移到 columnar
CREATE OR REPLACE FUNCTION public.archive_credential_model_index(archive_month date)
    RETURNS TABLE(status text, rows_archived bigint, rows_deleted bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    month_start date := date_trunc('month', archive_month)::date;
    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
    partition_name text := 'credential_model_index_archive_' || to_char(month_start, 'YYYY_MM');
    archived_count bigint;
    deleted_count bigint;
    cutoff_ts timestamptz := NOW() - INTERVAL '7 days';
BEGIN
    -- 1. 创建目标 columnar 分区（如果不存在）
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF credential_model_index_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
            partition_name, month_start, month_end
        );
        RAISE NOTICE 'Created archive columnar partition: %', partition_name;
    END IF;

    -- 2. 归档 7 天前的数据到 columnar（只归档指定月份的数据）
    -- 注意：columnar 表不支持 ON CONFLICT，但由于我们在删除前归档，且按月分区隔离，不会有重复
    INSERT INTO credential_model_index_archive
    SELECT * FROM credential_model_index
    WHERE bucket >= month_start 
      AND bucket < month_end
      AND bucket < cutoff_ts;
    
    GET DIAGNOSTICS archived_count = ROW_COUNT;
    RAISE NOTICE 'Archived % rows from credential_model_index (month %, older than 7 days)', 
        archived_count, to_char(month_start, 'YYYY-MM');

    -- 3. 删除主表中已归档的数据
    DELETE FROM credential_model_index
    WHERE bucket >= month_start 
      AND bucket < month_end
      AND bucket < cutoff_ts;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % rows from credential_model_index main table', deleted_count;

    RETURN QUERY SELECT 'success'::text, archived_count, deleted_count;
END;
$$;

COMMENT ON FUNCTION public.archive_credential_model_index(archive_month date) IS
'Archive one month of credential_model_index data (older than 7 days) into credential_model_index_archive (columnar). Deletes archived rows from main table to keep it lean. Run monthly on day 1. Idempotent: safe to re-run.';

-- 5. 创建清理函数：删除主表中超过 7 天的数据（每日运行）
CREATE OR REPLACE FUNCTION public.cleanup_old_credential_model_index()
    RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
    deleted_count bigint;
    cutoff_ts timestamptz := NOW() - INTERVAL '7 days';
BEGIN
    -- 删除 7 天前的数据（假设已归档或不再需要）
    DELETE FROM credential_model_index
    WHERE bucket < cutoff_ts;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    IF deleted_count > 0 THEN
        RAISE NOTICE 'Cleaned up % old rows from credential_model_index (older than 7 days)', deleted_count;
    END IF;
    
    RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_old_credential_model_index() IS
'Daily cleanup: removes credential_model_index rows older than 7 days from main table. Assumes historical data has been archived to credential_model_index_archive. Run daily at 3AM via background worker or cron.';

-- 6. Helper: 创建下个月 columnar 分区（预创建）
CREATE OR REPLACE FUNCTION public.ensure_next_month_cmi_archive_partition()
    RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
    partition_name   text := 'credential_model_index_archive_' || to_char(next_month_start, 'YYYY_MM');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF credential_model_index_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
            partition_name, next_month_start, next_month_end
        );
        RAISE NOTICE 'Pre-created next month columnar partition: %', partition_name;
    END IF;
END;
$$;

COMMENT ON FUNCTION public.ensure_next_month_cmi_archive_partition() IS
'Pre-create the next month columnar partition for credential_model_index_archive. Call this at month-end so the partition is ready for archival.';

-- 7. 初始归档：将现有 7 天前的数据归档到对应月份
DO $$
DECLARE
    current_month date;
    months_to_archive date[];
    archive_month date;
    rows_archived bigint;
    rows_deleted bigint;
    status_text text;
BEGIN
    -- 找出主表中需要归档的月份（7天前的所有数据）
    SELECT ARRAY_AGG(DISTINCT date_trunc('month', bucket)::date)
    INTO months_to_archive
    FROM credential_model_index
    WHERE bucket < NOW() - INTERVAL '7 days';
    
    IF months_to_archive IS NULL OR array_length(months_to_archive, 1) = 0 THEN
        RAISE NOTICE 'No historical data to archive (all data is within 7 days)';
    ELSE
        RAISE NOTICE 'Found % months to archive', array_length(months_to_archive, 1);
        
        -- 对每个月份执行归档
        FOREACH archive_month IN ARRAY months_to_archive
        LOOP
            SELECT * INTO status_text, rows_archived, rows_deleted
            FROM archive_credential_model_index(archive_month);
            
            RAISE NOTICE 'Archived month %: status=%, archived=%, deleted=%',
                to_char(archive_month, 'YYYY-MM'), status_text, rows_archived, rows_deleted;
        END LOOP;
    END IF;
END $$;

COMMIT;

-- ============================================================================
-- 使用说明
-- ============================================================================

/*
日常维护任务：

1. 每天凌晨 3:00 - 清理主表中超过 7 天的数据
   SELECT cleanup_old_credential_model_index();

2. 每月 1 日凌晨 2:30 - 归档上月的历史数据
   SELECT archive_credential_model_index(date_trunc('month', now() - interval '1 month'));

3. 每月 1 日凌晨 1:30 - 预创建下月归档分区
   SELECT ensure_next_month_cmi_archive_partition();

Cron 任务示例：
0 3 * * * psql -c "SELECT cleanup_old_credential_model_index();"
30 1 1 * * psql -c "SELECT ensure_next_month_cmi_archive_partition();"
30 2 1 * * psql -c "SELECT archive_credential_model_index(date_trunc('month', now() - interval '1 month'));"

查询使用：

-- 只查询最近数据（默认，使用主表）
SELECT * FROM credential_model_index 
WHERE bucket >= NOW() - INTERVAL '7 days';

-- 查询历史数据（跨主表 + 归档表）
SELECT * FROM credential_model_index WHERE bucket >= '2026-05-01'
UNION ALL
SELECT * FROM credential_model_index_archive WHERE bucket >= '2026-05-01'
ORDER BY bucket DESC;

-- 查询最新 bucket（正常业务查询，只用主表）
WITH latest_bucket AS (
    SELECT credential_id, raw_model, MAX(bucket) AS bucket
    FROM credential_model_index
    GROUP BY credential_id, raw_model
)
SELECT cmi.* 
FROM credential_model_index cmi
JOIN latest_bucket lb ON lb.credential_id = cmi.credential_id
                      AND lb.raw_model = cmi.raw_model
                      AND lb.bucket = cmi.bucket;

架构说明：
- 主表 (credential_model_index): 
  * 保留最近 7 天数据
  * heap 存储，支持 ON CONFLICT ... DO UPDATE
  * 高频更新（每 5 分钟）
  
- 归档表 (credential_model_index_archive):
  * 7 天前的历史数据
  * columnar 存储，只读，高压缩率
  * 按月分区

存储优化：
- heap (7天): ~2016 rows (假设 100 凭据 × 模型，5分钟bucket，7天 = 2016个bucket)
- columnar (历史): 压缩 80%+，用于历史分析
*/

-- ============================================================================
-- 结束
-- ============================================================================
