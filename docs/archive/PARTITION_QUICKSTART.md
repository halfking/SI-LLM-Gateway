# 分区与归档快速参考指南

## 📋 实施清单

- [x] 创建 3 个 SQL 迁移文件 (920, 921, 922)
- [x] 实现 2 个 Go 初始化函数
- [x] 创建后台归档 Worker
- [x] 集成到 db/db.go
- [x] 集成到 cmd/gateway/main.go

## 🚀 快速部署

### 1️⃣ 执行 SQL 迁移（生产环境必须手动执行）

```bash
psql -h $DB_HOST -U $DB_USER -d $DB_NAME << EOF
\i deploy/sql/migrations/920_routing_decision_log_partition.sql
\i deploy/sql/migrations/921_routing_decision_log_archive.sql
\i deploy/sql/migrations/922_credential_model_index_archive.sql
EOF
```

### 2️⃣ 重启应用

```bash
# 构建新版本
go build -o gateway ./cmd/gateway

# 重启服务
systemctl restart llm-gateway
```

### 3️⃣ 验证日志

```bash
journalctl -u llm-gateway -f | grep -E "archive|telemetry_archiver"
```

预期输出：
```
routing_decision_log_archive schema ensured
credential_model_index_archive schema ensured
telemetry_archiver: started (monthly archival + daily cleanup scheduler)
```

## 📊 数据架构速览

| 表名 | 主表策略 | 归档策略 | 自动化 |
|-----|---------|---------|--------|
| **request_logs** | 按月分区 (heap) | 月度归档到 columnar | ✅ 已有 |
| **routing_decision_log** | 按月分区 (heap) | 月度归档到 columnar | ✅ 新增 |
| **credential_model_index** | 单表保留7天 (heap) | 7天前归档到 columnar | ✅ 新增 |

## ⏰ 自动化时间表

| 时间 | 任务 | 函数 |
|------|------|------|
| 每月1日 02:00 | 归档上月数据 | `archive_request_logs()` |
| 每月1日 02:00 | 归档上月数据 | `archive_routing_decision_log()` |
| 每月1日 02:30 | 归档7天前数据 | `archive_credential_model_index()` |
| 每天 03:00 | 清理7天前数据 | `cleanup_old_credential_model_index()` |

## 🔍 验证命令

### 检查分区状态
```sql
SELECT 
    parent.relname as table_name,
    child.relname as partition_name,
    am.amname as storage_type,
    pg_size_pretty(pg_relation_size(child.oid)) as size
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
LEFT JOIN pg_am am ON child.relam = am.oid
WHERE parent.relname IN ('routing_decision_log', 'routing_decision_log_archive')
ORDER BY parent.relname, child.relname;
```

### 检查归档表
```sql
SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) 
FROM pg_tables 
WHERE tablename LIKE '%_archive%' 
ORDER BY tablename;
```

### 手动触发归档（测试）
```sql
-- 归档上月 routing_decision_log
SELECT * FROM archive_routing_decision_log('2026-05-01');

-- 归档 credential_model_index
SELECT * FROM archive_credential_model_index('2026-05-01');

-- 清理旧数据
SELECT cleanup_old_credential_model_index();
```

## 📝 查询代码适配

### ✅ 无需修改（查询最近7天）
```go
// routing_decision_log - 自动分区路由
db.Query(`SELECT * FROM routing_decision_log WHERE ts >= $1`, since)

// credential_model_index - 最新 bucket
db.Query(`SELECT * FROM credential_model_index WHERE bucket = (SELECT MAX(bucket) FROM credential_model_index)`)
```

### ⚠️ 需要修改（查询历史数据 > 7天）
```go
// 跨主表和归档表查询
query := `
    SELECT * FROM routing_decision_log WHERE ts >= $1
    UNION ALL
    SELECT * FROM routing_decision_log_archive WHERE ts >= $1
    ORDER BY ts DESC
`
```

## 🔧 故障排查

### 归档未执行
```bash
# 检查 worker 是否启动
journalctl -u llm-gateway | grep "telemetry_archiver: started"

# 检查是否有错误
journalctl -u llm-gateway | grep -i "archive.*failed"

# 手动触发测试
psql -c "SELECT archive_routing_decision_log('2026-05-01');"
```

### 分区不存在错误
```sql
-- 手动创建下月分区
CREATE TABLE routing_decision_log_2026_08
PARTITION OF routing_decision_log
FOR VALUES FROM ('2026-08-01') TO ('2026-09-01')
USING heap;
```

### 查询性能下降
```sql
-- 检查查询是否使用分区剪枝
EXPLAIN SELECT * FROM routing_decision_log WHERE ts >= '2026-06-01';
-- 应该看到 "Partition Pruning" 或只扫描部分分区
```

## 🎯 预期效果

- **存储节省**: 80-90% (columnar 压缩)
- **查询性能**: 提升 50-70% (分区剪枝)
- **运维成本**: 降低 (全自动归档)

## 📚 相关文档

- 详细实施总结: `PARTITION_IMPLEMENTATION_SUMMARY.md`
- 设计分析报告: `PARTITION_ANALYSIS_REPORT.md`
- SQL 迁移文件: `deploy/sql/migrations/920-922*.sql`

## 🆘 回滚方案

```sql
-- 回滚 routing_decision_log
ALTER TABLE routing_decision_log RENAME TO routing_decision_log_new;
ALTER TABLE routing_decision_log_old RENAME TO routing_decision_log;

-- 停止归档 worker（代码中注释掉启动行）
-- 或禁用归档函数
ALTER FUNCTION archive_routing_decision_log RENAME TO archive_routing_decision_log_disabled;
```

## ✅ 生产部署检查表

- [ ] 在测试环境完整验证
- [ ] 确认低流量时段（建议凌晨）
- [ ] 备份数据库
- [ ] 执行 SQL 迁移
- [ ] 部署新版本代码
- [ ] 验证日志输出
- [ ] 检查分区状态
- [ ] 测试查询功能
- [ ] 监控性能指标
- [ ] 确认归档函数可手动触发

---

**快速联系**: 遇到问题请查看 `PARTITION_IMPLEMENTATION_SUMMARY.md` 详细文档
