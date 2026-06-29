# minimax-prod-1 fp_slot 修复 - 部署执行清单

## 📦 准备工作（已完成 ✅）

- ✅ 代码修复完成并测试通过
- ✅ 二进制文件编译完成：`llm-gateway-fpslot-fix-20260629-181208` (42MB)
- ✅ Git 提交：`09730a3a`
- ✅ Git 标签：`deploy/fix-fpslot-sharing-20260629-181208`
- ✅ 部署脚本准备就绪
- ✅ 诊断工具准备就绪

---

## 🚀 快速开始

```bash
# 在本地执行部署脚本（会引导您完成所有步骤）
cd /Users/xutaohuang/workspace/llm-gateway-go-2
./scripts/deploy-to-71-fpslot-fix.sh
```

**注意**: 部署前需要先更新数据库配置！

---

## 📋 详细步骤

### Step 1: 数据库配置更新 ⏳

```bash
# SSH 到 184 机器并执行
ssh root@<184-host>

psql -U postgres -d llm_gateway << 'SQL'
BEGIN;
UPDATE credentials SET fp_slot_limit = 5, updated_at = NOW() WHERE id = 6;
SELECT id, label, fp_slot_limit FROM credentials WHERE id = 6;
COMMIT;
SQL
```

### Step 2: 部署到 71 机器 ⏳

```bash
cd /Users/xutaohuang/workspace/llm-gateway-go-2
./scripts/deploy-to-71-fpslot-fix.sh
```

### Step 3: 验证修复效果 ⏳

```bash
# 检查 slot 复用
ssh root@llm.kxpms.cn 'journalctl -u llm-gateway --since "5 min ago" | grep "reused existing slot"'

# 运行完整诊断
./scripts/diagnose-fpslot-issue.sh

# 监控失败率（至少 1 小时）
watch -n 10 'curl -s http://llm.kxpms.cn/api/credentials/monitor-summary | jq ".credentials[] | select(.id==6)"'
```

---

## ✅ 成功标准

- 失败率：52% → < 5%
- Slot 占用：15+ → 2-3 个
- Inflight 计数：0 → 10-20
- 日志中有 "reused existing slot"

---

## 🔄 回滚（如需要）

```bash
# 回滚服务
ssh root@llm.kxpms.cn 'systemctl stop llm-gateway && cp /usr/local/bin/llm-gateway.backup-* /usr/local/bin/llm-gateway && systemctl start llm-gateway'

# 回滚数据库
ssh root@<184-host> 'psql -U postgres -d llm_gateway -c "UPDATE credentials SET fp_slot_limit = 25 WHERE id = 6;"'
```

---

**准备好了吗？开始执行吧！** 🚀
