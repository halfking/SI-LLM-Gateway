# 📦 附件归档功能部署指南

## 快速开始

### 1. 上传部署包到服务器

```bash
# 在本机执行
scp deploy-attachments-20260701.tar.gz root@192.168.1.71:/tmp/
```

### 2. SSH 登录服务器并解压

```bash
ssh root@192.168.1.71
cd /tmp
tar xzf deploy-attachments-20260701.tar.gz
```

### 3. 执行部署（交互式）

```bash
sudo bash scripts/deploy_attachments_71.sh
```

脚本会自动：
- ✅ 检查前置条件（权限、文件、服务、数据库）
- ✅ 备份当前二进制
- ✅ 执行数据库迁移（request_logs 新增字段）
- ✅ 创建附件存储目录
- ✅ 停止服务 → 部署新二进制 → 启动服务
- ✅ 配置环境变量（交互式）
- ✅ 启动后健康检查

### 4. 执行验证测试

```bash
# 获取 API Key（从数据库或配置文件）
export API_KEY="your-api-key-here"

# 可选：获取 Admin JWT（用于测试下载 API）
export ADMIN_JWT="your-admin-jwt-token"

# 运行验证脚本
bash scripts/verify_attachments.sh "$API_KEY" "$ADMIN_JWT"
```

验证脚本会自动测试：
- ✅ 服务健康检查
- ✅ OpenAI 格式图片请求
- ✅ Anthropic 格式图片请求
- ✅ 数据库记录（request_logs + attachments）
- ✅ 文件系统（附件文件存在）
- ✅ Admin 下载 API
- ✅ 按 request_id 列表 API
- ✅ 日志检查（成功/错误）
- ✅ 去重验证

---

## 详细说明

### 部署包内容

| 文件 | 说明 |
|------|------|
| `llm-gateway-linux-amd64` | 交叉编译的 linux/amd64 二进制 (43MB) |
| `scripts/deploy_attachments_71.sh` | 自动化部署脚本 |
| `scripts/verify_attachments.sh` | 验证测试脚本 |
| `DEPLOYMENT_AUDIT_REPORT_2026-07-01_attachments.md` | 完整审计报告（**部署前必读**） |

### 环境变量配置

部署脚本会提示配置以下环境变量（在 systemd service 文件中）：

```bash
Environment="ATTACHMENT_ENABLED=true"
Environment="ATTACHMENT_STORAGE_PATH=/opt/llm-gateway-go/data/attachments"
Environment="ATTACHMENT_MAX_SIZE_MB=10"
```

如果不配置或设为 `false`，功能自动禁用（向后兼容，不影响现有流程）。

### 数据库迁移

部署脚本会自动执行：

```sql
ALTER TABLE request_logs
    ADD COLUMN IF NOT EXISTS has_attachments BOOLEAN,
    ADD COLUMN IF NOT EXISTS attachment_count INTEGER;
```

`attachments` 表由网关启动时自动创建。

---

## 手动验证步骤（可选）

如果不想用验证脚本，可以手动测试：

### 1. 发送带图片的请求

```bash
# 1x1 红色 PNG
IMG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

# OpenAI 格式
curl -X POST http://192.168.1.71:8080/v1/chat/completions \
  -H "Authorization: Bearer <your-api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "what color?"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,'"$IMG_B64"'"}}
      ]
    }],
    "max_tokens": 50
  }'
```

### 2. 检查数据库

```bash
psql -d llm_gateway

-- request_logs 有计数
SELECT request_id, has_attachments, attachment_count, ts
FROM request_logs
WHERE has_attachments = true
ORDER BY ts DESC LIMIT 5;

-- attachments 表有记录
SELECT id, request_id, media_type, file_size, content_hash
FROM attachments
ORDER BY created_at DESC LIMIT 5;
```

### 3. 下载附件

```bash
# 获取 attachment_id（从上一步 SQL）
ATT_ID="<从数据库查到的 id>"

# 下载
curl -H "Authorization: Bearer <admin-jwt>" \
  "http://192.168.1.71:8080/api/admin/attachments/${ATT_ID}" \
  -o /tmp/test.png

# 验证
file /tmp/test.png  # 应显示 PNG image data
```

---

## 监控与告警

### 部署后 24 小时关注

```bash
# 实时日志
journalctl -u llm-gateway -f

# 归档成功日志
journalctl -u llm-gateway --since '1 hour ago' | grep "attachments archived"

# 归档失败日志（应为 0）
journalctl -u llm-gateway --since '1 hour ago' | grep -i "attachment.*failed"

# 磁盘空间
df -h /opt/llm-gateway-go/data/attachments

# 附件统计
psql -d llm_gateway -c "
    SELECT 
        COUNT(*) AS total_files,
        SUM(file_size) AS total_bytes,
        COUNT(DISTINCT content_hash) AS unique_hashes
    FROM attachments
    WHERE created_at > NOW() - INTERVAL '1 hour';
"
```

### 关键指标

| 指标 | 预期 | 告警阈值 |
|------|------|---------|
| 请求成功率 | 无下降 | <99% |
| 图片请求延迟增量 | <50ms | >200ms |
| 归档失败率 | <1% | >5% |
| 磁盘使用率 | 正常增长 | >80% |

---

## 回滚

### 快速回滚（保留新功能但禁用归档）

```bash
# 方案 A: 修改环境变量
sudo systemctl edit llm-gateway
# 添加或修改:
# Environment="ATTACHMENT_ENABLED=false"

sudo systemctl restart llm-gateway
```

### 完全回滚到旧版本

```bash
# 方案 B: 恢复旧二进制
sudo systemctl stop llm-gateway
sudo cp /opt/llm-gateway-go/llm-gateway.backup.<timestamp> /opt/llm-gateway-go/llm-gateway
sudo systemctl start llm-gateway
```

回滚后：
- ✅ 附件归档功能禁用
- ✅ 图片转发恢复原有逻辑
- ⚠️ 数据库新字段保留（NULL 值，不影响查询）

---

## 故障排查

### 问题 1: 服务启动失败

```bash
# 查看详细日志
journalctl -u llm-gateway -n 100

# 常见原因
# - 端口被占用: ss -tlnp | grep 8080
# - 数据库连接失败: psql -d llm_gateway -c "SELECT 1;"
# - 权限问题: ls -l /opt/llm-gateway-go/llm-gateway
```

### 问题 2: 附件未归档

```bash
# 检查环境变量
systemctl cat llm-gateway | grep ATTACHMENT

# 期待看到:
# Environment="ATTACHMENT_ENABLED=true"

# 检查启动日志
journalctl -u llm-gateway --since '5 minutes ago' | grep "attachment manager"

# 期待看到:
# "attachment manager enabled" storage_path=... max_size_mb=10
```

### 问题 3: 附件下载 404

```bash
# 检查 API 路由是否注册
journalctl -u llm-gateway --since '5 minutes ago' | grep "attachment download API"

# 检查 JWT 是否有效（admin 权限）
# 检查 attachment_id 是否存在
psql -d llm_gateway -c "SELECT id FROM attachments LIMIT 5;"
```

### 问题 4: 磁盘空间不足

```bash
# 清理旧附件（手动）
find /opt/llm-gateway-go/data/attachments -type f -mtime +30 -delete

# 或配置定期清理任务
# （后续迭代可加自动清理逻辑）
```

---

## 成功标准

- [ ] 部署脚本无错误完成
- [ ] 服务正常启动，/healthz 返回 200
- [ ] 验证脚本所有测试通过
- [ ] OpenAI + Anthropic 格式图片请求均成功
- [ ] 数据库有 attachments 记录
- [ ] 文件系统有附件文件
- [ ] Admin API 能下载图片
- [ ] 日志无 "attachment failed" 错误

---

## 支持

如遇问题，请提供：
1. 完整的部署日志（deploy 脚本输出）
2. 验证测试结果（verify 脚本输出）
3. 最近 100 行服务日志: `journalctl -u llm-gateway -n 100`
4. 数据库状态: `psql -d llm_gateway -c "\d request_logs"` 和 `\d attachments`

---

**部署前请务必阅读 `DEPLOYMENT_AUDIT_REPORT_2026-07-01_attachments.md`，了解修复的严重 bug 和风险评估。**
