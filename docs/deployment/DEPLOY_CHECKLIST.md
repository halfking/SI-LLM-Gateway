# 🚀 部署执行清单 — 附件归档功能

## ✅ 准备阶段（已完成）

- [x] 代码审计：发现并修复 7 个问题（5 个严重/致命）
- [x] 单元测试：11 个测试全部通过
- [x] 全量回归：attachments/admin/relay/telemetry 全部通过
- [x] 交叉编译：linux/amd64 二进制（43MB）
- [x] 部署脚本：自动化部署 + 验证测试
- [x] 审计报告：完整文档（风险评估 + 回滚方案）
- [x] 打包产物：deploy-attachments-20260701.tar.gz (20MB)

## 📋 执行步骤（需要你操作）

### 步骤 1: 上传部署包

在你的**本机终端**执行：

```bash
cd /Users/xutaohuang/workspace/llm-gateway-go-2

# 上传到 71 服务器
scp deploy-attachments-20260701.tar.gz root@192.168.1.71:/tmp/

# 确认上传成功
ssh root@192.168.1.71 "ls -lh /tmp/deploy-attachments-20260701.tar.gz"
```

### 步骤 2: SSH 登录并解压

```bash
ssh root@192.168.1.71

cd /tmp
tar xzf deploy-attachments-20260701.tar.gz

# 验证文件完整
ls -lh llm-gateway-linux-amd64 scripts/*.sh *.md
```

### 步骤 3: 阅读审计报告（强烈建议）

```bash
less DEPLOYMENT_AUDIT_REPORT_2026-07-01_attachments.md

# 重点关注：
# - "审计发现与修正" 章节（了解修复的严重 bug）
# - "回滚方案" 章节（出问题时怎么办）
# - "已知限制" 章节（功能边界）
```

### 步骤 4: 执行部署（交互式）

```bash
sudo bash scripts/deploy_attachments_71.sh
```

脚本会：
1. ✅ 检查权限、文件、服务、数据库
2. ✅ 询问确认（可以随时取消）
3. ✅ 备份当前二进制到 `llm-gateway.backup.<timestamp>`
4. ✅ 执行数据库迁移（request_logs 新增字段）
5. ✅ 创建附件存储目录
6. ✅ 停止服务 → 部署 → 启动
7. ✅ 交互式配置环境变量（ATTACHMENT_ENABLED=true）
8. ✅ 启动后健康检查

**预计耗时：3-5 分钟**

### 步骤 5: 验证测试

获取 API Key（从数据库或环境变量）：

```bash
# 方法 1: 从数据库查询
psql -d llm_gateway -c "SELECT key_prefix, remark FROM api_keys WHERE enabled = true LIMIT 3;"

# 方法 2: 从配置文件
grep API_KEY /opt/llm-gateway-go/.env 2>/dev/null || echo "未找到"
```

运行验证脚本：

```bash
export API_KEY="sk-xxxxx"  # 替换为你的实际 API Key

# 可选：获取 Admin JWT（用于测试下载 API）
# export ADMIN_JWT="eyJhbGc..."

bash scripts/verify_attachments.sh "$API_KEY" "${ADMIN_JWT:-}"
```

验证脚本会自动测试 11 个场景，**预计耗时：30-60 秒**

### 步骤 6: 持续监控（部署后 30 分钟）

在另一个终端窗口保持日志监控：

```bash
ssh root@192.168.1.71
journalctl -u llm-gateway -f
```

关注：
- ✅ 请求是否正常处理
- ✅ 是否有 "attachments archived" 日志（发送图片请求后）
- ⚠️ 是否有 "attachment failed" 错误

---

## 🎯 成功标准

部署成功的标志：

- [ ] 部署脚本显示 "部署完成！"
- [ ] 服务正常运行：`systemctl status llm-gateway`
- [ ] 验证脚本显示 "✓ 所有测试通过"
- [ ] 日志显示 "attachment manager enabled"
- [ ] 日志无 ERROR 级别消息

---

## 🔄 回滚方案（如果出问题）

### 快速回滚（推荐）

```bash
# 禁用归档功能但保留图片转换修复
sudo systemctl stop llm-gateway
sudo systemctl edit llm-gateway
# 修改: Environment="ATTACHMENT_ENABLED=false"
sudo systemctl start llm-gateway
```

### 完全回滚到旧版本

```bash
sudo systemctl stop llm-gateway
sudo cp /opt/llm-gateway-go/llm-gateway.backup.<timestamp> /opt/llm-gateway-go/llm-gateway
sudo systemctl start llm-gateway

# 查看可用备份
ls -lt /opt/llm-gateway-go/llm-gateway.backup.* | head -5
```

---

## 📊 预期效果

部署后 24 小时内观察：

| 指标 | 预期变化 |
|------|---------|
| **图片请求成功率** | 📈 **提升**（修复了 3 个致命转换 bug） |
| **OpenAI→Anthropic 转换** | ✅ 图片不再丢失（之前是文本占位符） |
| **Anthropic→OpenAI 转换** | ✅ base64 正确转 image_url（之前全丢） |
| **请求延迟** | ➡️ 基本无变化（归档是异步旁观者） |
| **attachments 表** | 📈 新增记录（有图片请求时） |
| **磁盘空间** | 📈 ~50-100MB/天（取决于流量） |

---

## 🐛 已修复的严重 Bug

本次部署修复了以下用户可见的 bug：

1. **[致命] Anthropic→OpenAI 图片丢失**  
   位置: `anthropic_to_chat_request.go:216`  
   现象: 用户用 Anthropic SDK 发图片，转发到 OpenAI 上游时变成 "[Image: base64 data]" 文本  
   影响: Anthropic 客户端 → OpenAI 上游的图片请求失败

2. **[致命] OpenAI→Anthropic data URL 被拒**  
   位置: `chat_to_anthropic.go:117`  
   现象: 用户用 OpenAI SDK 发 data URL 图片，Anthropic API 返回 400 错误  
   影响: OpenAI 客户端 → Anthropic 上游的 data URL 图片请求失败

3. **[致命] 初版破坏图片转发**  
   位置: `attachments/manager.go`（已完全重写）  
   现象: 初版把 body 里的 base64 替换成 `attachment_ref` 对象，上游 LLM 不认识  
   影响: 所有图片请求失败

这些 bug 在**本次部署前**可能导致图片请求失败，**部署后立即修复**。

---

## 📞 需要帮助？

如果部署过程中遇到问题，请：

1. **不要慌**：所有改动都有备份，可以回滚
2. **保存日志**：`journalctl -u llm-gateway -n 200 > /tmp/deploy-error.log`
3. **检查状态**：
   ```bash
   systemctl status llm-gateway
   df -h /opt/llm-gateway-go/data/attachments
   psql -d llm_gateway -c "\d request_logs"
   ```
4. **告诉我**：提供上述信息，我帮你排查

---

## ✅ 准备就绪

所有准备工作已完成，随时可以部署。建议在**非高峰时段**执行（如有），整个流程预计 **10-15 分钟**（含验证）。

**现在可以开始了！请从「步骤 1: 上传部署包」开始执行。**
