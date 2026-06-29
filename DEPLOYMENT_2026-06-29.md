# 2026-06-29 会话管理修复与断线重连增强部署指南

## 变更概述

本次部署包含两大核心改进：

### 1. 会话管理修复（P0 - 解决"空响应"问题）

**问题现象：**
- 前端频繁报"模型未返回任何内容"
- `request_logs` 中找不到对应的错误记录
- 部分请求缺少 `gw_session_id` 关联

**根本原因：**
- `/v1/messages` 和 `/v1/responses` 端点没有统一的会话管理
- 会话过期后未自动创建替代会话
- `Touch()` 方法未实现滑动续期，导致活跃会话意外过期

**修复内容：**
1. 提取统一的 `resolveSessionFromRequest()` 方法（`relay/session_resolution.go`）
2. `/v1/messages` 和 `/v1/responses` 集成完整会话管理
3. `Touch()` 现在同时更新 `expires_at` 和 Redis TTL（真正的滑动窗口）
4. 扩展 `gwSessionTaskFromRequest()` 识别所有会话头（`X-Conversation-Id`, `X-Thread-Id` 等）

**影响范围：**
- `relay/session_resolution.go` (新文件)
- `relay/messages.go` (集成会话解析)
- `relay/responses.go` (集成会话解析)
- `relay/request_context.go` (扩展头识别)
- `sessions/session.go` (`Touch` 方法增强)

### 2. 断线重连配置管理（增强功能）

**新增功能：**
- 全局和租户级别的断线重连配置开关
- 支持 `auto_resume_by_default` 控制默认行为
- 管理 API 端点：`GET/POST /api/reconnect/config`

**配置选项：**
```json
{
  "enabled": false,                    // 全局开关（默认关闭，向后兼容）
  "auto_resume_by_default": false,     // 是否自动尝试恢复（默认需显式请求）
  "cache_ttl_seconds": 604800,         // 缓存 TTL（默认 7 天）
  "max_cache_body_bytes": 1048576      // 最大缓存体积（默认 1 MiB）
}
```

**新增文件：**
- `reconnect/config.go` (配置管理)
- `reconnect/config_test.go` (测试覆盖)
- `admin/reconnect_config.go` (管理 API)

## 部署前准备

### 1. 备份当前版本

```bash
# 在 71 服务器上
cd /path/to/llm-gateway-go
git stash
git branch backup-pre-session-fix-$(date +%Y%m%d)
```

### 2. 检查 Redis 连接

确保 Redis 可用且连接正常：
```bash
redis-cli ping
# 应返回 PONG
```

### 3. 检查当前会话数据

```bash
# 查看当前会话数量
redis-cli KEYS "session:*" | wc -l

# 查看 pending 响应数量
redis-cli KEYS "pending_response:*" | wc -l
```

## 部署步骤

### 1. 代码部署

```bash
# 在开发机上
cd /Users/xutaohuang/workspace/llm-gateway-go-2
git add .
git commit -m "fix(sessions): unified session management + reconnect config

- Extract resolveSessionFromRequest() for chat/messages/responses
- Implement sliding window session expiry (Touch refreshes expires_at)
- Wire session context into /v1/messages and /v1/responses
- Add reconnect configuration management (disabled by default)
- Extend gwSessionTaskFromRequest() to recognize all session headers

Fixes: 'empty response' with missing request_logs
"
git push origin github

# 在 71 服务器上
cd /path/to/llm-gateway-go
git pull origin github
```

### 2. 编译

```bash
# 在 71 服务器上
cd /path/to/llm-gateway-go
go build -o llm-gateway-new ./cmd/gateway

# 验证编译成功
./llm-gateway-new --version
```

### 3. 停止当前服务

```bash
# 查找当前进程
ps aux | grep llm-gateway

# 优雅停止（给 30 秒处理完现有请求）
sudo systemctl stop llm-gateway
# 或
kill -TERM <pid>
sleep 30
```

### 4. 替换二进制

```bash
# 备份旧版本
sudo cp /usr/local/bin/llm-gateway /usr/local/bin/llm-gateway.bak.$(date +%Y%m%d)

# 部署新版本
sudo mv llm-gateway-new /usr/local/bin/llm-gateway
sudo chmod +x /usr/local/bin/llm-gateway
```

### 5. 启动新版本

```bash
sudo systemctl start llm-gateway

# 检查启动状态
sudo systemctl status llm-gateway

# 查看日志
sudo journalctl -u llm-gateway -f --since "1 minute ago"
```

## 验证测试

### 1. 基础健康检查

```bash
# 健康检查端点
curl -f http://localhost:8080/health || echo "FAIL"

# 应返回 200 OK
```

### 2. 会话管理验证

```bash
# 测试 /v1/chat/completions（原有端点，应正常工作）
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer sk-test-xxx" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "test"}],
    "stream": false
  }'

# 检查响应头中的 X-Gw-Session-Id-Resume
# 应返回 2xx 并包含会话 ID
```

### 3. 测试 /v1/messages 会话管理

```bash
# 测试 Anthropic Messages 端点
curl -X POST http://localhost:8080/v1/messages \
  -H "Authorization: Bearer sk-test-xxx" \
  -H "X-Gw-Session-Id: gw_test_session_001" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "test"}]
  }'

# 检查：
# 1. 响应头包含 X-Gw-Session-Id-Resume（如果会话不存在）
# 2. request_logs 中能找到对应记录，且 gw_session_id 正确
```

### 4. 测试会话过期自动恢复

```bash
# 1. 创建会话
SESSION_ID=$(curl -X POST http://localhost:8080/v1/sessions \
  -H "Authorization: Bearer sk-test-xxx" \
  -H "Content-Type: application/json" \
  -d '{"device_seed":"test-device"}' | jq -r '.session_id')

# 2. 手动设置会话为已过期（需要 Redis 访问）
redis-cli HSET "session:${SESSION_ID}" expires_at "2020-01-01T00:00:00Z"

# 3. 使用过期会话发起请求
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer sk-test-xxx" \
  -H "X-Gw-Session-Id: ${SESSION_ID}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "test"}]
  }'

# 预期：
# - 不返回 403 或 410
# - 响应头包含 X-Gw-Session-Id-Resume（新会话 ID）
# - 日志显示 "session expired, creating replacement"
```

### 5. 检查 request_logs 关联

```bash
# 查询最近的 request_logs，确认 gw_session_id 字段已填充
psql -h localhost -U postgres -d llm_gateway -c "
  SELECT request_id, gw_session_id, request_mode, success
  FROM request_logs
  WHERE ts >= NOW() - INTERVAL '10 minutes'
  ORDER BY ts DESC
  LIMIT 10;
"

# 预期：gw_session_id 列不应该有 NULL 值（对于已认证请求）
```

### 6. 断线重连配置验证

```bash
# 查询当前配置（默认应为 disabled）
curl -X GET http://localhost:8080/api/reconnect/config \
  -H "Authorization: Bearer <admin-token>"

# 预期返回：
# {
#   "enabled": false,
#   "auto_resume_by_default": false,
#   "cache_ttl_seconds": 604800,
#   "max_cache_body_bytes": 1048576
# }
```

## 回滚计划

如果发现问题，立即回滚：

```bash
# 停止新版本
sudo systemctl stop llm-gateway

# 恢复旧版本
sudo cp /usr/local/bin/llm-gateway.bak.$(date +%Y%m%d) /usr/local/bin/llm-gateway

# 启动旧版本
sudo systemctl start llm-gateway

# 验证
curl -f http://localhost:8080/health
```

## 监控指标

部署后 24 小时内重点监控：

1. **会话创建率**
   - 指标：新创建的 `gw_*` 会话数量
   - 预期：应与请求量成比例，不应暴涨

2. **request_logs 覆盖率**
   - 查询：`gw_session_id IS NULL` 的行数
   - 预期：应降至接近 0（仅未认证请求可为 NULL）

3. **错误率**
   - 查询：`request_status = 'failure' AND error_kind != 'empty_response'`
   - 预期：不应明显增加

4. **Redis 内存使用**
   - 监控：Redis `used_memory` 指标
   - 预期：稳定，不应因会话 TTL 刷新而持续增长

5. **前端"空响应"报错**
   - 监控：前端日志中的 `（空响应）` 出现次数
   - 预期：显著减少

## 后续配置（可选）

### 启用断线重连功能

在验证会话管理修复效果后，可选择启用断线重连：

```bash
# 1. 全局启用（但不自动恢复，需客户端显式请求）
curl -X POST http://localhost:8080/api/reconnect/config \
  -H "Authorization: Bearer <admin-token>" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "auto_resume_by_default": false}'

# 2. 观察 7 天，监控：
#    - pending-response 缓存命中率
#    - Redis pending_response:* 键数量
#    - 客户端恢复成功率

# 3. 如果效果良好，启用自动恢复
curl -X POST http://localhost:8080/api/reconnect/config \
  -H "Authorization: Bearer <admin-token>" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "auto_resume_by_default": true}'
```

## 故障排查

### 问题：会话频繁过期

**症状：**
- 日志大量 "session expired, creating replacement"
- 客户端频繁收到新的 `X-Gw-Session-Id-Resume`

**排查：**
```bash
# 检查会话 TTL 配置
redis-cli TTL "session:gw_<some-session-id>"

# 检查 Touch 是否正常工作
redis-cli HGET "session:gw_<some-session-id>" last_active
redis-cli HGET "session:gw_<some-session-id>" expires_at

# 预期：expires_at 应随 last_active 更新而延后
```

### 问题：request_logs 仍有 NULL session_id

**症状：**
- 部分请求的 `gw_session_id` 仍为 NULL

**排查：**
```bash
# 查询这些请求的特征
psql -h localhost -U postgres -d llm_gateway -c "
  SELECT request_id, request_mode, api_key_id, error_kind
  FROM request_logs
  WHERE gw_session_id IS NULL
    AND ts >= NOW() - INTERVAL '1 hour'
  LIMIT 20;
"

# 常见原因：
# 1. 未认证请求（api_key_id IS NULL）— 预期行为
# 2. 认证失败的请求（error_kind = 'invalid_key'）— 预期行为
# 3. 其他情况 — 需要排查日志
```

### 问题：Redis 内存持续增长

**症状：**
- Redis `used_memory` 持续上升

**排查：**
```bash
# 检查键数量
redis-cli INFO keyspace

# 检查 session 和 pending 键的 TTL
redis-cli SCAN 0 MATCH "session:*" COUNT 100 | xargs -I {} redis-cli TTL {}
redis-cli SCAN 0 MATCH "pending_response:*" COUNT 100 | xargs -I {} redis-cli TTL {}

# 预期：所有键都应有 TTL（不应是 -1）
```

## 联系方式

如遇问题，联系：
- 开发：@xutaohuang
- 运维：<运维团队联系方式>

## 变更日志

### 2026-06-29 初始版本
- 会话管理统一化
- 滑动窗口会话过期
- 断线重连配置框架（默认禁用）
