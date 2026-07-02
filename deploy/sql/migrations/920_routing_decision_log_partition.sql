-- ============================================================================
-- Migration 920: routing_decision_log 按月分区
-- ============================================================================
-- 目标：将 routing_decision_log 从单表改为按月分区（heap）
-- 原则：当月数据 heap（高频写入），历史月份通过归档函数迁移到 columnar
-- 数据流：主表分区 (heap) → 每月调用 archive_routing_decision_log() 归档到
--        routing_decision_log_archive_<YYYY_MM>（columnar 子分区）
-- 父表：routing_decision_log (heap, RANGE (ts))
-- 子分区：routing_decision_log_2026_06/07/... (USING heap)
-- ============================================================================

BEGIN;

-- 1. 创建分区父表（结构与原表完全一致）
CREATE TABLE IF NOT EXISTS public.routing_decision_log_partitioned (
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

-- 2. 创建索引（在父表上，自动继承到所有分区）
CREATE INDEX IF NOT EXISTS idx_routing_decision_log_part_ts 
    ON public.routing_decision_log_partitioned (ts DESC);
CREATE INDEX IF NOT EXISTS idx_routing_decision_log_part_request_id 
    ON public.routing_decision_log_partitioned (request_id);
CREATE INDEX IF NOT EXISTS idx_routing_decision_log_part_tenant_ts 
    ON public.routing_decision_log_partitioned (tenant_id, ts DESC) 
    WHERE tenant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_routing_decision_log_part_credential 
    ON public.routing_decision_log_partitioned (chosen_credential_id, ts DESC) 
    WHERE chosen_credential_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_routing_decision_log_part_model 
    ON public.routing_decision_log_partitioned (model, ts DESC);
CREATE INDEX IF NOT EXISTS idx_routing_decision_log_part_success 
    ON public.routing_decision_log_partitioned (success, ts DESC);

-- 3. 创建当月分区（columnar）
-- 2026-07-02: switched from heap to columnar. routing_decision_log has no
-- AFTER ROW triggers, so columnar am is safe. Historical months are also
-- columnar (archive function creates USING columnar). Result: every partition
-- of routing_decision_log is columnar from creation; archive_request_logs()
-- function handles retention.
CREATE TABLE IF NOT EXISTS public.routing_decision_log_2026_06
    PARTITION OF public.routing_decision_log_partitioned
    FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00')
    USING columnar;

-- 4. 创建下月分区（columnar）
CREATE TABLE IF NOT EXISTS public.routing_decision_log_2026_07
    PARTITION OF public.routing_decision_log_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00')
    USING columnar;

-- 5. 创建默认分区（columnar）
CREATE TABLE IF NOT EXISTS public.routing_decision_log_default
    PARTITION OF public.routing_decision_log_partitioned DEFAULT
    USING columnar;

-- 6. 迁移现有数据
-- 检查原表是否存在数据
DO $$
DECLARE
    row_count bigint;
BEGIN
    -- 检查原表是否存在
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'routing_decision_log') THEN
        -- 获取原表行数
        EXECUTE 'SELECT COUNT(*) FROM routing_decision_log' INTO row_count;
        RAISE NOTICE 'Migrating % rows from routing_decision_log to partitioned table', row_count;
        
        -- 迁移数据
        INSERT INTO routing_decision_log_partitioned 
        SELECT * FROM routing_decision_log;
        
        RAISE NOTICE 'Migration complete: % rows migrated', row_count;
    ELSE
        RAISE NOTICE 'Original routing_decision_log table does not exist, skipping migration';
    END IF;
END $$;

-- 7. 验证数据
DO $$
DECLARE
    old_count bigint;
    new_count bigint;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'routing_decision_log') THEN
        EXECUTE 'SELECT COUNT(*) FROM routing_decision_log' INTO old_count;
        EXECUTE 'SELECT COUNT(*) FROM routing_decision_log_partitioned' INTO new_count;
        
        IF old_count != new_count THEN
            RAISE EXCEPTION 'Data migration verification failed: old_count=%, new_count=%', old_count, new_count;
        END IF;
        
        RAISE NOTICE 'Data verification passed: % rows in both tables', old_count;
    END IF;
END $$;

-- 8. 切换表名
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'routing_decision_log') THEN
        ALTER TABLE routing_decision_log RENAME TO routing_decision_log_old;
        RAISE NOTICE 'Renamed routing_decision_log to routing_decision_log_old';
    END IF;
END $$;

ALTER TABLE routing_decision_log_partitioned RENAME TO routing_decision_log;

-- 9. Comment 表
COMMENT ON TABLE public.routing_decision_log IS
'Routing decision logs - partitioned by month (RANGE on ts). Current month uses heap storage. Historical months are archived to routing_decision_log_archive (columnar) via archive_routing_decision_log() function. Call this monthly on day 1.';

-- 10. 清理说明（手动执行，确认无误后）
COMMENT ON TABLE public.routing_decision_log_old IS
'DEPRECATED: Old non-partitioned routing_decision_log table. Verify routing_decision_log works correctly, then DROP TABLE routing_decision_log_old;';

COMMIT;

-- ============================================================================
-- 使用说明
-- ============================================================================

/*
分区维护：

1. 每月 1 日凌晨 1:00 - 创建下个月的分区
   SELECT create_next_month_partitions();

2. 每月 1 日凌晨 2:00 - 归档上月的分区
   SELECT archive_routing_decision_log('2026-06-01');

3. 手动创建特定月份分区（如需要）
   CREATE TABLE routing_decision_log_2026_08
   PARTITION OF routing_decision_log
   FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00')
   USING heap;

查询使用：
- 应用代码无需修改，PostgreSQL 自动路由到正确的分区
- WHERE ts >= '2026-06-01' 会自动只扫描相关分区
- 跨主表和归档表查询需要 UNION ALL:
  SELECT * FROM routing_decision_log WHERE ts >= ...
  UNION ALL
  SELECT * FROM routing_decision_log_archive WHERE ts >= ...

清理旧表：
-- 确认新表工作正常后执行
DROP TABLE IF EXISTS routing_decision_log_old;
*/

-- ============================================================================
-- 结束
-- ============================================================================
