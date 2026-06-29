# 生产环境部署检查清单

## 📋 部署前准备

### 环境信息确认
- [ ] 目标环境：生产/预发布/测试 _______________
- [ ] 数据库版本：PostgreSQL _____
- [ ] 当前数据量：
  - [ ] routing_decision_log: _______ 行
  - [ ] credential_model_index: _______ 行
  - [ ] request_logs: _______ 行
- [ ] 预计迁移时间：_______ 分钟
- [ ] 部署时间窗口：_______________

### 备份确认
- [ ] 数据库全量备份已完成
  - 备份文件：_______________________
  - 备份大小：_______________________
  - 备份时间：_______________________
- [ ] 备份已验证可恢复
- [ ] 备份文件已存储到安全位置

### 权限确认
- [ ] 数据库用户有 CREATE TABLE 权限
- [ ] 数据库用户有 CREATE FUNCTION 权限
- [ ] 数据库用户有 ALTER TABLE 权限
- [ ] 数据库用户有 DROP TABLE 权限（如需删除旧表）
- [ ] Citus columnar 扩展已安装
  ```sql
  SELECT * FROM pg_extension WHERE extname = 'citus_columnar';
  ```

### 测试环境验证
- [ ] 在测试环境完成完整迁移流程
- [ ] 测试环境运行 48 小时无异常
- [ ] 性能测试通过
- [ ] 查询功能验证通过
- [ ] 归档功能手动触发成功

---

## 🚀 部署步骤

### 第1步：准备阶段（提前1小时）

#### 1.1 通知相关方
- [ ] 通知运维团队
- [ ] 通知开发团队
- [ ] 通知业务团队（如需停机）
- [ ] 发送部署通知邮件

#### 1.2 系统检查
```bash
# 检查数据库连接
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT version();"

# 检查磁盘空间（需要足够空间存储临时数据）
df -h

# 检查数据库大小
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT pg_size_pretty(pg_database_size('$DB_NAME'));"
```
- [ ] 数据库连接正常
- [ ] 磁盘空间充足（至少有当前数据量的2倍空余）
- [ ] 数据库负载正常

#### 1.3 代码准备
```bash
# 拉取最新代码
git fetch origin
git checkout main
git pull origin main

# 编译新版本
go build -o gateway-v2.3.0 ./cmd/gateway

# 验证编译成功
./gateway-v2.3.0 --version
```
- [ ] 代码已更新到最新版本
- [ ] 编译成功无错误
- [ ] 二进制文件大小正常

---

### 第2步：数据库迁移（预计15-30分钟）

#### 2.1 执行前检查
```sql
-- 检查当前数据量
SELECT 'routing_decision_log' as table_name, COUNT(*) as row_count FROM routing_decision_log
UNION ALL
SELECT 'credential_model_index', COUNT(*) FROM credential_model_index;

-- 检查是否有长事务（如有，等待完成或终止）
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE state = 'active' AND now() - pg_stat_activity.query_start > interval '5 minutes';
```
- [ ] 数据量已记录
- [ ] 无长时间运行的事务

#### 2.2 执行迁移脚本
```bash
# 设置超时（防止挂起）
export PGOPTIONS="-c statement_timeout=600000"  # 10分钟

# 执行920迁移（routing_decision_log分区）
echo "执行 920_routing_decision_log_partition.sql..."
time psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -f deploy/sql/migrations/920_routing_decision_log_partition.sql \
  2>&1 | tee migration_920.log

# 检查920执行结果
if [ $? -eq 0 ]; then
  echo "✓ 920迁移成功"
else
  echo "✗ 920迁移失败，查看 migration_920.log"
  exit 1
fi

# 执行921迁移（routing_decision_log归档）
echo "执行 921_routing_decision_log_archive.sql..."
time psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -f deploy/sql/migrations/921_routing_decision_log_archive.sql \
  2>&1 | tee migration_921.log

if [ $? -eq 0 ]; then
  echo "✓ 921迁移成功"
else
  echo "✗ 921迁移失败，查看 migration_921.log"
  exit 1
fi

# 执行922迁移（credential_model_index归档）
echo "执行 922_credential_model_index_archive.sql..."
time psql -h $DB_HOST -U $DB_USER -d $DB_NAME \
  -f deploy/sql/migrations/922_credential_model_index_archive.sql \
  2>&1 | tee migration_922.log

if [ $? -eq 0 ]; then
  echo "✓ 922迁移成功"
else
  echo "✗ 922迁移失败，查看 migration_922.log"
  exit 1
fi
```

**检查点：**
- [ ] 920迁移执行成功（routing_decision_log已分区）
- [ ] 921迁移执行成功（归档表和函数已创建）
- [ ] 922迁移执行成功（credential_model_index归档已创建）
- [ ] 日志文件已保存（migration_*.log）

#### 2.3 迁移后验证
```sql
-- 验证分区表
SELECT 
    parent.relname as 主表,
    child.relname as 分区名,
    COALESCE(am.amname, 'heap') as 存储类型
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
LEFT JOIN pg_am am ON child.relam = am.oid
WHERE parent.relname = 'routing_decision_log'
ORDER BY child.relname;

-- 验证数据迁移（数量应该一致）
SELECT COUNT(*) FROM routing_decision_log;
-- 与旧表对比（如果还在）
SELECT COUNT(*) FROM routing_decision_log_old;

-- 验证归档函数
\df archive_*
\df cleanup_*

-- 验证归档表
SELECT tablename FROM pg_tables WHERE tablename LIKE '%_archive%';
```

**检查点：**
- [ ] routing_decision_log 已显示为分区表
- [ ] 分区包含：当前月、下月、default
- [ ] 数据量与迁移前一致
- [ ] 归档表已创建
- [ ] 归档函数已创建

---

### 第3步：应用部署（预计5-10分钟）

#### 3.1 停止旧版本
```bash
# 记录停止时间
echo "应用停止时间: $(date)" >> deployment.log

# 停止应用（根据实际部署方式选择）
# 方式1: Systemd
sudo systemctl stop llm-gateway

# 方式2: Docker
docker stop llm-gateway

# 方式3: Kubernetes
kubectl scale deployment llm-gateway --replicas=0

# 验证已停止
ps aux | grep gateway
```
- [ ] 应用已停止
- [ ] 进程已终止
- [ ] 停止时间已记录

#### 3.2 部署新版本
```bash
# 备份旧版本
sudo cp /usr/local/bin/gateway /usr/local/bin/gateway.backup.$(date +%Y%m%d)

# 部署新版本
sudo cp gateway-v2.3.0 /usr/local/bin/gateway

# 验证文件
ls -lh /usr/local/bin/gateway*
```
- [ ] 旧版本已备份
- [ ] 新版本已部署
- [ ] 文件权限正确

#### 3.3 启动新版本
```bash
# 记录启动时间
echo "应用启动时间: $(date)" >> deployment.log

# 启动应用
# 方式1: Systemd
sudo systemctl start llm-gateway

# 方式2: Docker
docker start llm-gateway

# 方式3: Kubernetes
kubectl scale deployment llm-gateway --replicas=3

# 等待启动
sleep 10
```
- [ ] 应用已启动
- [ ] 启动时间已记录

---

### 第4步：验证（预计10分钟）

#### 4.1 检查应用日志
```bash
# 检查启动日志
journalctl -u llm-gateway -n 200 | grep -E "archive|postgres|started"

# 应该看到：
# ✓ "postgres connected"
# ✓ "routing_decision_log_archive schema ensured"
# ✓ "credential_model_index_archive schema ensured"
# ✓ "telemetry_archiver: started"
```
- [ ] 应用启动成功
- [ ] 数据库连接正常
- [ ] 归档表初始化成功
- [ ] TelemetryArchiver已启动
- [ ] 无ERROR级别日志

#### 4.2 健康检查
```bash
# HTTP健康检查
curl http://localhost:8781/health

# 预期返回: {"status":"ok"}
```
- [ ] 健康检查返回正常
- [ ] API端点可访问

#### 4.3 功能测试
```bash
# 测试查询routing_decision_log
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT COUNT(*) FROM routing_decision_log WHERE ts >= NOW() - INTERVAL '1 day';"

# 测试查询credential_model_index
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
SELECT COUNT(*) FROM credential_model_index;"

# 测试写入（发送一个测试请求）
curl -X POST http://localhost:8781/v1/chat/completions \
  -H "Authorization: Bearer test-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"test"}]}'
```
- [ ] 查询功能正常
- [ ] 写入功能正常
- [ ] 响应时间正常

#### 4.4 手动测试归档功能（可选）
```sql
-- 测试cleanup函数
SELECT cleanup_old_credential_model_index();

-- 测试归档函数（如果有上月数据）
SELECT * FROM archive_routing_decision_log('2026-05-01');
SELECT * FROM archive_credential_model_index('2026-05-01');
```
- [ ] cleanup函数执行成功
- [ ] archive函数执行成功（或跳过）

---

### 第5步：监控设置（部署后立即）

#### 5.1 设置日志监控
```bash
# 持续监控归档相关日志
tail -f /var/log/llm-gateway/app.log | grep -E "archive|telemetry"

# 或使用 journalctl
journalctl -u llm-gateway -f | grep -E "archive|telemetry"
```
- [ ] 日志监控已启动
- [ ] 无异常日志

#### 5.2 设置告警（根据监控系统）
- [ ] 归档执行失败告警（关键字: `archive.*failed`）
- [ ] 主表大小告警（routing_decision_log > 500MB）
- [ ] 分区缺失告警（下月分区不存在）
- [ ] 查询性能告警（P95 > 阈值）

#### 5.3 设置每日检查
```bash
# 添加到crontab
crontab -e

# 每天检查主表大小
0 9 * * * psql -h $DB_HOST -c "SELECT pg_size_pretty(pg_total_relation_size('routing_decision_log'))" | mail -s "主表大小" admin@example.com

# 每月1日检查归档状态
0 10 1 * * psql -h $DB_HOST -c "SELECT * FROM pg_tables WHERE tablename LIKE '%_archive_%'" | mail -s "归档分区状态" admin@example.com
```
- [ ] 每日检查已配置
- [ ] 月度检查已配置

---

### 第6步：清理（部署后1-3天）

#### 6.1 验证稳定性
- [ ] 应用运行3天无异常
- [ ] 日志无ERROR
- [ ] 查询性能正常
- [ ] 写入功能正常

#### 6.2 清理旧表
```sql
-- 最后一次验证数据一致性
SELECT 
    'old' as source, COUNT(*) as count FROM routing_decision_log_old
UNION ALL
SELECT 
    'new' as source, COUNT(*) FROM routing_decision_log;

-- 确认一致后删除
DROP TABLE routing_decision_log_old;
```
- [ ] 数据一致性已确认
- [ ] 旧表已删除
- [ ] 磁盘空间已释放

---

## 🆘 回滚方案

### 触发条件
- [ ] 应用启动失败
- [ ] 功能异常无法修复
- [ ] 性能严重下降
- [ ] 数据丢失或损坏

### 回滚步骤

#### 1. 停止新版本应用
```bash
sudo systemctl stop llm-gateway
```

#### 2. 恢复旧版本代码
```bash
sudo cp /usr/local/bin/gateway.backup.* /usr/local/bin/gateway
```

#### 3. 回滚数据库（如果已执行迁移）
```sql
-- 回滚 routing_decision_log
ALTER TABLE routing_decision_log RENAME TO routing_decision_log_new;
ALTER TABLE routing_decision_log_old RENAME TO routing_decision_log;

-- 禁用归档函数（防止误触发）
ALTER FUNCTION archive_routing_decision_log 
  RENAME TO archive_routing_decision_log_disabled;
ALTER FUNCTION archive_credential_model_index 
  RENAME TO archive_credential_model_index_disabled;
```

#### 4. 启动旧版本应用
```bash
sudo systemctl start llm-gateway
```

#### 5. 验证
```bash
curl http://localhost:8781/health
journalctl -u llm-gateway -n 50
```

#### 6. 通知
- [ ] 通知相关团队
- [ ] 记录回滚原因
- [ ] 安排问题分析会议

---

## 📊 部署后检查（首周）

### 每日检查
- [ ] Day 1: 应用正常运行，无ERROR日志
- [ ] Day 2: 查询性能正常，响应时间符合预期
- [ ] Day 3: 内存使用正常，无内存泄漏
- [ ] Day 4: 数据写入正常，主表大小增长符合预期
- [ ] Day 5: CPU使用正常，无异常峰值
- [ ] Day 6: 准备首次月度归档（如果在月初）
- [ ] Day 7: 系统稳定，可安排清理旧表

### 首次月度归档检查（下月1日）
- [ ] 凌晨2:00归档任务自动执行
- [ ] 日志显示归档成功
- [ ] 归档表有新数据
- [ ] 主表分区已删除
- [ ] 查询功能正常
- [ ] 性能无下降

---

## ✅ 签字确认

| 角色 | 姓名 | 日期 | 签名 |
|-----|------|------|------|
| 部署工程师 | _________ | _________ | _________ |
| 数据库管理员 | _________ | _________ | _________ |
| 技术负责人 | _________ | _________ | _________ |
| 运维负责人 | _________ | _________ | _________ |

---

**备注**：
- 本检查清单必须在部署过程中逐项完成
- 任何偏离标准流程的操作必须记录在案
- 遇到问题立即上报并决定是否继续或回滚
- 部署完成后归档此文档备查
