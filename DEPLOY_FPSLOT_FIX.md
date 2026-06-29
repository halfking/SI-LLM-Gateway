# minimax-prod-1 fp_slot 问题修复部署指南

## 修复概述

**问题**: minimax-prod-1 凭据出现 52% 失败率
**根因**: 同一 holder 的并发请求未共享 slot，导致 slot 资源耗尽
**修复**: 实现真正的 slot 共享机制

## 修复内容

### 1. 代码修复（已完成 ✅）

- **credentialfpslot/slot.go**: 添加 holder 共享快速路径
- **errorsx/classify.go**: 增强 MiniMax 错误分类
- **Git Commit**: `09730a3a`
- **Git Tag**: `deploy/fix-fpslot-sharing-20260629-181208`

### 2. 数据库修复（待执行 ⏳）

```sql
-- 将 minimax-prod-1 的 fp_slot_limit 从 25 降低到 5
UPDATE credentials 
SET fp_slot_limit = 5, updated_at = NOW() 
WHERE id = 6;
```

### 3. 二进制部署（待执行 ⏳）

- **编译产物**: `llm-gateway-fpslot-fix-20260629-181208` (42MB)
- **部署目标**: 71 机器 (llm.kxpms.cn) **仅部署 71，不部署 184**
- **服务名**: llm-gateway

---

## 部署步骤

### Step 1: 数据库配置更新（在 184 机器上执行）

```bash
# SSH 到 184 机器
ssh root@<184-host>

# 执行 SQL 更新
psql -U postgres -d llm_gateway << 'EOF'
BEGIN;

-- 查看修改前
SELECT id, label, concurrency_limit, fp_slot_limit 
FROM credentials WHERE id = 6;

-- 更新 fp_slot_limit
UPDATE credentials 
SET fp_slot_limit = 5, updated_at = NOW() 
WHERE id = 6;

-- 确认修改后
SELECT id, label, concurrency_limit, fp_slot_limit 
FROM credentials WHERE id = 6;

COMMIT;
EOF

# 预期输出：
# fp_slot_limit: 25 → 5
```

### Step 2: 部署到 71 机器

```bash
# 在本地执行
cd /Users/xutaohuang/workspace/llm-gateway-go-2

# 上传二进制文件
scp llm-gateway-fpslot-fix-20260629-181208 root@llm.kxpms.cn:/opt/llm-gateway-go/

# SSH 到 71 机器
ssh root@llm.kxpms.cn

# 备份当前版本
cd /opt/llm-gateway-go
cp /usr/local/bin/llm-gateway /usr/local/bin/llm-gateway.backup-$(date +%Y%m%d-%H%M%S)

# 停止服务
systemctl stop llm-gateway
sleep 5

# 部署新版本
cp llm-gateway-fpslot-fix-20260629-181208 /usr/local/bin/llm-gateway
chmod +x /usr/local/bin/llm-gateway

# 启动服务
systemctl start llm-gateway
sleep 3

# 检查服务状态
systemctl status llm-gateway

# 健康检查
curl http://localhost:8080/health
```

### Step 3: 验证修复效果

#### 3.1 检查服务日志

```bash
# SSH 到 71 机器
ssh root@llm.kxpms.cn

# 查看最近日志，寻找 "cred_fp_slot reused" 日志
journalctl -u llm-gateway -f | grep -E "cred_fp_slot|minimax-m3"

# 预期看到：
# "cred_fp_slot reused existing slot" (说明共享机制生效)
```

#### 3.2 检查 Redis slot 使用情况

```bash
# 在本地执行诊断脚本
cd /Users/xutaohuang/workspace/llm-gateway-go-2
./scripts/diagnose-fpslot-issue.sh

# 或手动检查
ssh root@llm.kxpms.cn << 'EOF'
redis-cli -h 172.31.0.4 KEYS "llmgw:cred_fp_slot:6:*" | wc -l
redis-cli -h 172.31.0.4 KEYS "llmgw:cred_fp_slot:6:*" | while read key; do
    redis-cli -h 172.31.0.4 GET "$key"
done | sort -u | wc -l
EOF

# 预期结果：
# - 活跃 slot 数量: 2-3 个（对应 2-3 个实际用户）
# - 不同 holder 数量: 2-3 个
```

#### 3.3 检查 inflight 计数

```bash
ssh root@llm.kxpms.cn << 'EOF'
redis-cli -h 172.31.0.4 KEYS "llmgw:cred_fp_inflight:6:*" | while read key; do
    redis-cli -h 172.31.0.4 GET "$key"
done | paste -sd+ | bc
EOF

# 预期结果：
# - Inflight 总数: > 0 (说明并发共享生效)
# - 修复前: 0 (没有 inflight 机制)
# - 修复后: 10-20 (您的并发请求共享 1 个 slot)
```

#### 3.4 监控失败率

```bash
# 实时监控 minimax-prod-1 的成功率
watch -n 5 'curl -s http://llm.kxpms.cn/api/credentials/monitor-summary | jq ".credentials[] | select(.id==6) | {label, aggregated_success_rate, models: [.models[] | select(.raw_model_name | test(\"m3\"; \"i\"))]}"'

# 预期结果：
# aggregated_success_rate: 从 0.48 (52%失败) → 0.95+ (5%失败)
```

#### 3.5 数据库验证（在 184 机器上）

```bash
# 在本地执行数据库诊断
psql -h <184-host> -U postgres -d llm_gateway -f /Users/xutaohuang/workspace/llm-gateway-go-2/scripts/diagnose-fpslot-db-queries.sql

# 观察最近 1 小时的失败率趋势
# 预期看到失败率明显下降
```

---

## 预期效果对比

| 指标 | 修复前 | 修复后 | 说明 |
|------|--------|--------|------|
| **失败率** | 52% | < 5% | 主要改善指标 |
| **Slot 占用** | 15+ 个 | 2-3 个 | 对应实际用户数 |
| **Holder 数量** | 2-3 个 | 2-3 个 | 不变 |
| **Inflight 总数** | 0 | 10-20 | 证明共享机制生效 |
| **并发能力** | 受限于 25 slot | 每用户可有多并发 | 解除瓶颈 |

---

## 回滚步骤（如需要）

### 回滚代码

```bash
# SSH 到 71 机器
ssh root@llm.kxpms.cn

# 停止服务
systemctl stop llm-gateway

# 恢复备份
cp /usr/local/bin/llm-gateway.backup-* /usr/local/bin/llm-gateway
chmod +x /usr/local/bin/llm-gateway

# 启动服务
systemctl start llm-gateway

# 检查状态
systemctl status llm-gateway
```

### 回滚数据库

```bash
# 在 184 机器上执行
psql -U postgres -d llm_gateway << 'EOF'
UPDATE credentials 
SET fp_slot_limit = 25, updated_at = NOW() 
WHERE id = 6;
EOF
```

---

## 诊断工具

### 1. Redis 诊断脚本

```bash
cd /Users/xutaohuang/workspace/llm-gateway-go-2
./scripts/diagnose-fpslot-issue.sh
```

生成报告：
- `/tmp/fpslot-diagnosis-*/summary.txt` - 汇总报告
- `/tmp/fpslot-diagnosis-*/slot_details.csv` - Slot 详情
- `/tmp/fpslot-diagnosis-*/unique_holders.txt` - Holder 列表

### 2. 数据库诊断 SQL

```bash
psql -h <184-host> -U postgres -d llm_gateway \
  -f scripts/diagnose-fpslot-db-queries.sql
```

输出：
- 失败率趋势（按小时）
- 并发峰值统计
- Transient 错误详情
- 错误类型分布

---

## 常见问题

### Q1: 修复后失败率没有明显改善？

**检查清单**：
1. 确认服务已重启：`systemctl status llm-gateway`
2. 检查 Redis slot 数量是否减少
3. 查看 inflight 计数是否 > 0
4. 检查日志是否有 "reused existing slot"
5. 确认数据库 fp_slot_limit 已更新为 5

### Q2: 如何确认并发请求真的在共享 slot？

**验证方法**：
```bash
# 查看某个 slot 的 inflight 计数
redis-cli -h 172.31.0.4 GET "llmgw:cred_fp_inflight:6:0"

# 如果返回值 > 1，说明有多个请求共享这个 slot
```

### Q3: 为什么要调整 fp_slot_limit 到 5？

**原因**：
- 实际用户数：2-3 个
- 修复后每个用户只需 1 个 slot
- 设置 5 个：留 2 个冗余，应对临时新用户或会话切换

### Q4: 184 机器需要部署吗？

**不需要**。184 机器是数据库服务器，只需：
1. 更新数据库配置（`fp_slot_limit`）
2. 无需部署二进制文件

---

## 部署检查清单

- [ ] 数据库配置已更新（184 机器）
- [ ] 二进制文件已上传到 71 机器
- [ ] 服务已重启且状态正常
- [ ] Redis slot 数量已减少（15+ → 2-3）
- [ ] Inflight 计数 > 0（证明共享生效）
- [ ] 日志中看到 "reused existing slot"
- [ ] 失败率明显下降（52% → < 5%）
- [ ] 监控已配置（可选）

---

## 联系信息

- **部署时间**: 2026-06-29
- **Git Commit**: `09730a3a`
- **Git Tag**: `deploy/fix-fpslot-sharing-20260629-181208`
- **二进制文件**: `llm-gateway-fpslot-fix-20260629-181208`
- **部署目标**: 71 (llm.kxpms.cn)

---

**重要提示**：
- ⚠️ 仅部署到 71 机器，不要部署到 184
- ⚠️ 部署前先更新数据库配置
- ⚠️ 保留备份文件以便回滚
- ⚠️ 监控失败率至少 1 小时以确认效果
