# 手动部署指南 - V2.2.9-session-fix

## 当前状态
- ✅ 代码已提交: commit 7576c021
- ✅ 版本标签: V2.2.9-session-fix
- ✅ 二进制已编译: llm-gateway-V2.2.9-session-fix (41M)
- ⏳ 待部署到: root@llm.kxpms.cn (14.103.169.56)

## 部署步骤

### 方式 1: 使用脚本（需要 SSH 访问权限）

```bash
# 在本地执行
cd /Users/xutaohuang/workspace/llm-gateway-go-2
./scripts/deploy-session-fix.sh
```

**如果遇到 SSH 权限问题：**
- 方式 A: 添加 SSH 公钥到服务器
- 方式 B: 使用密码登录（交互式）
- 方式 C: 配置 SSH config

### 方式 2: 手动上传和部署

#### Step 1: 上传二进制

```bash
# 在本地执行（会提示输入密码）
cd /Users/xutaohuang/workspace/llm-gateway-go-2
scp llm-gateway-V2.2.9-session-fix root@llm.kxpms.cn:/opt/llm-gateway-go/
```

#### Step 2: 登录服务器部署

```bash
# SSH 登录到服务器
ssh root@llm.kxpms.cn

# 在服务器上执行以下命令
cd /opt/llm-gateway-go

# 备份当前版本
cp llm-gateway llm-gateway.backup.$(date +%Y%m%d_%H%M%S)

# 停止服务
systemctl stop llm-gateway

# 部署新版本
cp llm-gateway-V2.2.9-session-fix llm-gateway
chmod +x llm-gateway

# 启动服务
systemctl start llm-gateway

# 等待几秒
sleep 5

# 检查状态
systemctl status llm-gateway

# 健康检查
curl -f http://localhost:8080/health
```

#### Step 3: 验证部署

在服务器上执行：
```bash
# 查看日志
journalctl -u llm-gateway -f -n 50

# 检查进程
ps aux | grep llm-gateway

# 测试端点
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer <your-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"test"}],"max_tokens":10}'
```

### 方式 3: 使用原有的 deploy_fix_to_71.sh

```bash
cd /Users/xutaohuang/workspace/llm-gateway-go-2

# 这个脚本会在服务器上重新编译
./scripts/deploy_fix_to_71.sh root@llm.kxpms.cn
```

**注意：** 这个方式会在服务器上重新编译，可能需要更长时间，但版本号仍会保留。

## 部署后验证清单

### 1. 基础验证（在本地执行）

```bash
# 需要替换 <your-api-key>
./scripts/verify-deployment.sh 14.103.169.56 <your-api-key>
```

### 2. 会话管理验证（在服务器或本地执行）

```bash
SERVER="http://llm.kxpms.cn:8080"
API_KEY="<your-api-key>"

# 测试 /v1/chat/completions 会话
curl -v -X POST $SERVER/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"test"}],"max_tokens":10}'

# 检查响应头是否包含 X-Gw-Session-Id-Resume

# 测试 /v1/messages 会话
curl -v -X POST $SERVER/v1/messages \
  -H "Authorization: Bearer $API_KEY" \
  -H "X-Conversation-Id: test-conv-$(date +%s)" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"test"}]}'

# 检查响应头是否包含 X-Gw-Session-Id-Resume
```

### 3. 数据库验证（在服务器执行）

```bash
# 检查 request_logs 中的 gw_session_id 覆盖率
psql -h localhost -U postgres -d llm_gateway -c "
SELECT 
  COUNT(*) AS total_requests,
  COUNT(*) FILTER (WHERE gw_session_id IS NOT NULL) AS with_session,
  COUNT(*) FILTER (WHERE gw_session_id IS NULL) AS without_session,
  ROUND(100.0 * COUNT(*) FILTER (WHERE gw_session_id IS NOT NULL) / COUNT(*), 2) AS coverage_pct
FROM request_logs
WHERE ts >= NOW() - INTERVAL '10 minutes'
  AND api_key_id IS NOT NULL;
"
```

### 4. Redis 验证（在服务器执行）

```bash
# 检查会话数量
redis-cli KEYS "session:*" | wc -l

# 检查最近创建的会话
redis-cli KEYS "session:gw_*" | head -5

# 检查某个会话的 expires_at 字段
SESSION_ID=$(redis-cli KEYS "session:gw_*" | head -1 | cut -d: -f2)
redis-cli HGET "session:$SESSION_ID" expires_at
redis-cli TTL "session:$SESSION_ID"
```

## 回滚计划

如果部署后发现问题：

```bash
# 在服务器上执行
cd /opt/llm-gateway-go

# 停止服务
systemctl stop llm-gateway

# 恢复备份（找到最新的备份文件）
ls -lt llm-gateway.backup.* | head -1
cp llm-gateway.backup.20260629_XXXXXX llm-gateway

# 启动服务
systemctl start llm-gateway

# 验证
systemctl status llm-gateway
curl -f http://localhost:8080/health
```

## 监控指标

部署后 24 小时内重点监控：

1. **request_logs.gw_session_id 覆盖率**
   - 目标：> 95%（对于已认证请求）
   
2. **错误率变化**
   - 对比部署前后的错误率
   
3. **前端"空响应"报错**
   - 应该显著减少

4. **Redis 内存使用**
   - 监控是否有异常增长

## 下一步

部署成功后：

1. 观察 24 小时，收集指标
2. 如果效果良好，考虑启用断线重连功能：
   ```bash
   curl -X POST http://llm.kxpms.cn:8080/api/reconnect/config \
     -H "Authorization: Bearer <admin-token>" \
     -H "Content-Type: application/json" \
     -d '{"enabled": true, "auto_resume_by_default": false}'
   ```

## 联系信息

- **部署时间：** 2026-06-29
- **版本：** V2.2.9-session-fix
- **Git Commit：** 7576c021
- **开发负责人：** @xutaohuang

---

**准备好手动部署了吗？** 

请按照上述步骤执行，或者提供 SSH 密钥/密码，我可以协助自动化部署。
