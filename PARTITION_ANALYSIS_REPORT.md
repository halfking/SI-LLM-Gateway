# 大表分区结构分析报告

## 概述
本报告分析了三个大表的分区状态：`request_logs`、`credential_model_index` 和 `routing_decision_log`

---

## 1. request_logs 表

### ✅ 状态：已实现按月分区 + columnar 归档

### 表结构
- **分区策略**：PARTITION BY RANGE (ts)
- **主表存储**：heap（当前月份数据）
- **归档表存储**：columnar（历史月份数据）
- **主键**：(id, ts)

### 分区架构
```
request_logs (父表, heap)
├── request_logs_2026_07 (heap, 当前月)
├── request_logs_2026_08 (heap, 下月预创建)
└── request_logs_default (默认分区)

request_logs_archive (父表, heap, PARTITION BY RANGE)
└── request_logs_archive_YYYY_MM (columnar, 历史月份)
```

### 归档流程
1. **每月1日凌晨1:00** - 调用 `create_next_month_partitions()` 创建下月分区
2. **每月1日凌晨2:00** - 调用 `archive_request_logs(archive_month)` 归档上月数据
   - 从 heap 分区复制数据到 columnar 归档分区
   - DETACH + DROP 原 heap 分区释放空间

### 相关代码文件
- **Schema**: `deploy/sql/00_schema/006_request_logs.sql`
- **Migration**: `deploy/sql/migrations/910_request_logs_archive.sql`
- **Go代码**: `db/request_logs_archive_schema.go`
  - `EnsureRequestLogsArchive()` - 确保归档表结构存在
  - `archive_request_logs(date)` - SQL函数，归档指定月份
  - `ensure_next_month_archive_partition()` - SQL函数，预创建下月分区

### 数据操作代码
- **插入**: `telemetry/client.go:386` - `insertRequestLog()`
- **更新**: `telemetry/client.go:380` - `updateRequestLog()`
- **查询**: 多处查询，包括：
  - `admin/logs.go`
  - `admin/analytics.go`
  - `bg/auto_index_refresher.go:271` (聚合过去5分钟数据)

### 验证
✅ 分区结构完整
✅ 归档函数已实现
✅ 代码操作兼容分区（PostgreSQL自动路由）

---

## 2. credential_model_index 表

### ❌ 状态：**未实现分区，单表 heap 存储**

### 表结构
```sql
CREATE TABLE public.credential_model_index (
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
    updated_at timestamp with time zone DEFAULT now(),
    UNIQUE (bucket, credential_id, raw_model)
);
```

### 特点
- **非分区表**
- 使用 `UNIQUE (bucket, credential_id, raw_model)` 约束
- 存储凭据×模型×5分钟时间桶的实时评分
- 使用 `ON CONFLICT ... DO UPDATE` upsert模式

### 数据操作代码
- **插入/更新**: `bg/auto_index_refresher.go:224`
  - 每5分钟聚合 `request_logs` 数据并 upsert
  - SQL: `rollupCredentialModelIndexSQL`
  ```sql
  INSERT INTO credential_model_index (...)
  SELECT ... FROM request_logs rl
  WHERE rl.ts >= NOW() - INTERVAL '5 minutes'
  ON CONFLICT (bucket, credential_id, raw_model) DO UPDATE SET ...
  ```

### 问题分析
❌ **与用户描述不符**：用户说此表按月分区 + columnar 存储，但实际是单表 heap
❌ **缺少归档机制**：历史 bucket 数据会无限累积
❌ **ON CONFLICT 不兼容 columnar**：columnar 表不支持 UPDATE 和 UNIQUE 约束

### 建议
1. **如需实现分区**：
   - 采用类似 `request_logs` 的双层架构
   - 主表保留最近1-3个月数据（heap，支持 ON CONFLICT）
   - 归档表使用 columnar（只读，历史数据）
2. **或者实现 TTL**：
   - 定期清理超过 N 个月的旧 bucket
   - 保留统计数据在单独的汇总表

---

## 3. routing_decision_log 表

### ❌ 状态：**未实现分区，单表 heap 存储**

### 表结构
```sql
CREATE TABLE public.routing_decision_log (
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
);
```

### 特点
- **非分区表**
- **无主键或唯一约束**
- 存储每次路由决策的详细日志
- 只做 INSERT，无 UPDATE/DELETE

### 数据操作代码
- **插入**: `telemetry/client.go:320` - `insertDecisionLog()`
  ```sql
  INSERT INTO routing_decision_log (
      ts, request_id, idempotency_key, tenant_id, api_key_id,
      model, chosen_credential_id, chosen_provider_id, ...
  ) VALUES (now(), $1, $2, $3, ...)
  ```
- **查询**:
  - `admin/credential_monitor_decisions_test.go`
  - `admin/routing_resolve_probe.go:43`
  - `admin/telemetry.go:171, 331`

### 问题分析
❌ **与用户描述不符**：用户说此表按月分区 + columnar 存储，但实际是单表 heap
❌ **缺少归档机制**：决策日志会无限累积
✅ **适合 columnar**：只做 INSERT，无 UPDATE/DELETE，天然适合列存储

### 建议
**强烈建议实现按月分区 + columnar 归档**：
1. 模式与 `request_logs` 完全一致
2. 主表：当前月 heap 分区（高速写入）
3. 归档表：历史月 columnar 分区（压缩存储，只读查询）
4. 优势：
   - 减少存储成本 80%+
   - 查询性能提升（时间范围查询自动剪枝）
   - 易于实现数据保留策略

---

## 总结与行动建议

### 当前状态
| 表名 | 是否分区 | 归档机制 | 与用户描述是否一致 |
|-----|---------|---------|------------------|
| request_logs | ✅ 是 | ✅ columnar | ✅ 一致 |
| credential_model_index | ❌ 否 | ❌ 无 | ❌ **不一致** |
| routing_decision_log | ❌ 否 | ❌ 无 | ❌ **不一致** |

### 问题
1. **credential_model_index** 和 **routing_decision_log** 并未实现按月分区
2. 两个表都会无限累积历史数据
3. 存在存储空间浪费和查询性能下降风险

### 建议方案

#### 方案 A：为 routing_decision_log 实现分区 + 归档（推荐）
**优先级：高**

理由：
- 此表纯 INSERT，无 UPDATE，完美适配 columnar
- 数据量大，按月增长快
- 实现方式与 request_logs 完全一致

步骤：
1. 创建 `routing_decision_log_archive` 父表（heap, PARTITION BY RANGE(ts)）
2. 创建归档函数 `archive_routing_decision_log(archive_month)`
3. 将 `routing_decision_log` 转换为分区表
4. 配置月度 cron 任务执行归档

#### 方案 B：为 credential_model_index 实现保留策略
**优先级：中**

由于此表使用 ON CONFLICT，不适合直接 columnar。建议：

选项 1：**时间窗口保留**
- 只保留最近 3-6 个月的 bucket
- 创建定期清理任务删除旧数据
- 如需历史分析，先聚合到汇总表

选项 2：**双层架构**
- 主表：最近 3 个月，heap，支持 ON CONFLICT
- 归档表：3个月前，columnar，只读
- 每月1日将超过3个月的数据归档到 columnar

---

## 附录：相关 SQL 迁移文件

### 已实现
- `deploy/sql/migrations/900_partition_all_telemetry_tables.sql` - 分区 usage_ledger, credit_ledger, tool_usage_stats
- `deploy/sql/migrations/910_request_logs_archive.sql` - request_logs 归档

### 待创建
- `deploy/sql/migrations/9XX_routing_decision_log_partition.sql` - routing_decision_log 分区
- `deploy/sql/migrations/9XX_credential_model_index_retention.sql` - credential_model_index 保留策略

---

**生成时间**: 2026-06-30
**分析人**: Kiro AI
