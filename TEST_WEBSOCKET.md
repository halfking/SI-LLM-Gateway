# WebSocket 连接测试指南

## 🔍 问题分析

**根本原因：** 旧版布局（`LiveRequestStream.vue`）和新版布局（`LiveRequestStreamLanes.vue`）都调用了 `useLiveStream()`，导致创建了两个 WebSocket 连接，消息被分散到不同的实例中。

## ✅ 修复方案

**单例模式：**
- 全局只创建一个 WebSocket 连接
- 使用 refCount 跟踪引用计数
- 所有组件共享同一个数据流
- 最后一个组件卸载时才断开连接

## 🚀 本地测试步骤

### 1. 启动后端服务

```bash
# 方式1：使用脚本（推荐）
/tmp/start-gateway.sh

# 方式2：手动启动
cd /path/to/llm-gateway-go-2
export LLM_GATEWAY_DATABASE_URL="postgresql://user:password@localhost:5432/llm_gateway"
export LLM_GATEWAY_SECRET_KEY="your-secret-key"
export LLM_GATEWAY_LISTEN=":9088"
go run ./cmd/gateway
```

**预期日志：**
```
{"level":"INFO","msg":"live request stream hub enabled (websocket /api/admin/live-stream)","has_db":true,"has_telemetry":true}
{"level":"INFO","msg":"gateway listening","listen":":9088"}
```

⚠️ **关键指标：** `has_db=true` 和 `has_telemetry=true` 必须都为 true

---

### 2. 启动前端开发服务器

```bash
cd $PROJECT_DIR/web
npm run dev
```

访问：http://localhost:5173

---

### 3. 打开浏览器开发者工具

按 F12 或 Cmd+Option+I 打开控制台

**预期日志（单例模式）：**
```
[useLiveStream] called, refCount: 0
[useLiveStream] creating new global instance
[createLiveStreamInstance] options: {}
[createLiveStreamInstance] auto-connecting...
[liveStream] connecting to: ws://localhost:5173/api/admin/live-stream?token=***
[liveStream] WebSocket connected
[liveStream] received message: {"type":"initial_data",...}
[liveStream] parsed envelope: {type: "initial_data", hasRequest: false, requestsCount: 50}
[liveStream] initial_data: 50 requests
[liveStream] initial_data processed, buffer size: 50
[LiveStreamLanes] loaded initial stats: {...}
```

⚠️ **如果还看到两次 "creating new global instance"，说明单例模式失败**

---

### 4. 测试切换布局

点击右上角的布局切换按钮（新版 ↔ 旧版）

**预期行为：**
- ✅ 控制台只会显示 `refCount` 变化，不会重新创建连接
- ✅ WebSocket 连接保持打开状态
- ✅ 消息继续正常接收

```
[useLiveStream] called, refCount: 1  // 新组件挂载
[useLiveStream] component unmounted, refCount: 0  // 旧组件卸载
```

---

### 5. 发送测试请求

```bash
# 生成一个测试请求
curl -X POST http://localhost:9088/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "test websocket"}]
  }'
```

**预期前端日志：**
```
[liveStream] received message: {"type":"request",...}
[liveStream] parsed envelope: {type: "request", hasRequest: true}
[liveStream] new request: {request_id: "xxx", model: "gpt-4o", status: "success"}
[LiveStreamLanes] requests changed: {oldCount: 50, newCount: 51, newReqs: [...]}
[laneRequests] computing, requests.length: 51
[laneRequests] lanes: ["OpenAI", "Anthropic", "Google", "Meta", "Other"]
[laneRequests] latestRequestMap size: 51
[laneRequests] result: OpenAI: 1, Anthropic: 0, Google: 0, Meta: 0, Other: 0
```

**预期 UI 变化：**
- ✅ 新请求块出现在 OpenAI 泳道
- ✅ 累计统计数字增加
- ✅ 泳道顺序可能重新排序

---

## 🐛 常见问题排查

### 问题1：WebSocket 连接失败 (404/403)

**检查：**
```bash
curl http://localhost:9088/api/admin/live-stream
# 应该返回 404（因为 WebSocket 需要 upgrade header）

# 检查后端日志是否包含
grep "live request stream hub enabled" /tmp/gateway.log
```

**解决：**
- 确认后端已启动并监听正确端口
- 确认数据库连接正常（`has_db=true`）

---

### 问题2：收不到新请求消息

**检查：**
```bash
# 后端日志中是否有 telemetry 相关错误
docker logs r112_postgres --tail 50

# 数据库是否有 request_logs 表
docker exec r112_postgres psql -U kxuser -d llm_gateway -c "\dt request_logs"
```

**解决：**
- 确认 `has_telemetry=true`
- 检查 `telemetryClient.SetOnRequestLogPersisted` 是否被调用
- 确认数据库有写入权限

---

### 问题3：泳道显示为空

**检查前端日志：**
```
[LiveStreamLanes] loaded initial stats: {...}
[laneRequests] latestRequestMap size: 0
```

**解决：**
- 确认 `/api/usage/live-stream-init` 返回数据
- 确认数据库中有历史记录
- 尝试刷新页面重新加载

```bash
# 测试初始化接口
curl http://localhost:9088/api/usage/live-stream-init?days=7 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## 📊 已提交的改进

### Commit 1: 添加调试日志
- WebSocket 连接日志
- 消息接收日志
- envelope 处理日志

### Commit 2: 冷启动初始化
- 新增 `/api/usage/live-stream-init` 接口
- 前端组件挂载时加载历史统计
- 避免刷新后泳道为空

### Commit 3: 单例模式修复 ✅
- 全局唯一 WebSocket 连接
- refCount 引用计数
- 组件间共享数据流

---

## 🎯 验证清单

- [ ] 后端启动成功，日志显示 `has_db=true` 和 `has_telemetry=true`
- [ ] 前端控制台显示 WebSocket 已连接
- [ ] 控制台只显示一次 "creating new global instance"
- [ ] 初始数据加载成功，泳道显示历史统计
- [ ] 发送测试请求后，新请求出现在泳道中
- [ ] 切换布局时，WebSocket 连接保持不断开
- [ ] 刷新页面后，泳道显示历史数据（不为空）

---

## 📝 下一步

如果测试通过，可以：
1. 部署到测试环境（184 服务器）
2. 移除调试日志（减少 console 输出）
3. 添加错误重试机制
4. 优化泳道排序算法
