# Fingerprint Slot 并发上限修复 (V3.2.2)

## 问题诊断

### 症状
- **minimax-m3 凭据频繁被占满**，导致请求失败
- 20 个 slot 全部被占用，但实际只有 5 个客户端
- 其他凭据的 slot 大量空闲

### 根本原因
**Acquire 快速路径缺陷**：在 `credentialfpslot/slot.go` 的 Acquire 方法中，快速路径允许同一 holder（客户端会话）的所有并发请求**无限制地共享同一 slot**。

```go
// 修复前的快速路径（第 328-376 行）
if m.client != nil && holder != "" {
    pinKey := pinRedisKey(holder, credentialID)
    slotStr, err := m.client.Get(ctx, pinKey).Result()
    if err == nil && slotStr != "" {
        // ... 验证持有权 ...
        // ❌ 直接 INCR inflight，没有检查上限
        newInflight, _ := m.client.Incr(ctx, inflightK).Result()
        // ... 返回现有 slot
    }
}
```

**错误的执行流程**：
1. 客户端 A 第一次请求 → 获得 slot#0，inflight=1
2. 客户端 A 第二次请求 → 快速路径命中，复用 slot#0，inflight=2
3. ... 客户端 A 的 20 个并发 → 全部挤在 slot#0，inflight=20
4. 客户端 B、C、D、E 也分别占满 slot#1-4
5. **5 个客户端 × 平均 4 个 slot = 20 个 slot 全部占满**
6. 后续新请求 → `Acquire` 失败，返回 `ok=false`

---

## 修复方案

### 核心修改：inflight 上限下沉到 Redis Lua 脚本（原子强制）

限制必须在 `acquireSlotScript` Lua 脚本内原子完成（读 inflight → 比较 → INCR 在同一个 EVALSHA 里），而非在 Go 层做 GET→INCR 的两次往返——后者存在 TOCTOU 竞态（两个并发同时读到 inflight=9 并各自 INCR 到 10+）。

脚本新增 `ARGV[6] = maxInflight`，在 `currentHolder == holder`（同 holder 复用）分支里，INCR 前检查上限：

```lua
elseif currentHolder == holder then
    -- 同 holder 复用：达上限则拒绝，让 Go 层 fallback 到 LRU
    local currentInflight = tonumber(redis.call('GET', inflightKey) or '0')
    if currentInflight >= maxInflight then
        return {0, ''}   -- 拒绝，Go 层 acquireRedis 会继续 Phase 2 LRU
    end
    redis.call('EXPIRE', slotKey, slotTTL)
```

Go 层 `acquireRedis()` 的 Phase 1（pin-reuse）收到 `{0, ''}` 后自然 fall through 到 Phase 2（LRU），由 `acquireLRUScript` 分配另一个空闲 slot。这样同 holder 超过 `maxInflight` 的并发会自动分散到多个 slot，而不是全挤在一个上。

**配套删除**：原 `Acquire()` 里有一段 Go 层快速路径（GET pin → 验证 → INCR inflight），它既是 `acquireSlotScript` pin-reuse 逻辑的非原子重复，又有 TOCTOU 竞态。删除后所有 Redis 请求统一走脚本，原子性由 Lua 保证。

### 配置参数

| 参数 | 环境变量 | 默认值 | 说明 |
|------|---------|--------|------|
| `MaxInflightPerSlot` | `LLM_GATEWAY_CREDENTIAL_FP_SLOT_MAX_INFLIGHT_PER_SLOT` | 10 | 单个 slot 的最大并发请求数 |

**推荐配置**：
- **默认场景（10）**：适合大多数场景，单客户端 10 个并发足够
- **高并发单客户端（20-30）**：如果单个客户端确实需要 20+ 并发
- **低并发多客户端（5）**：如果客户端很多但单客户端并发低

---

## 部署步骤

### 1. 编译新版本

```bash
cd /path/to/llm-gateway-go-2
git pull origin main
go build -o gateway-v3.2.2 ./cmd/gateway
```

### 2. 配置环境变量（可选）

```bash
# 如果需要调整默认值（默认 10 已足够大多数场景）
export LLM_GATEWAY_CREDENTIAL_FP_SLOT_MAX_INFLIGHT_PER_SLOT=10
```

### 3. 重启服务

```bash
# 停止旧版本
systemctl stop llm-gateway
# 或
kill -TERM $(cat /var/run/llm-gateway.pid)

# 启动新版本
./gateway-v3.2.2 &
# 或
systemctl start llm-gateway
```

### 4. 验证部署

使用验证脚本检查修复效果：

```bash
./scripts/verify_slot_inflight_fix.sh
```

---

## 验证方法

### 方法 1：前端监控面板

访问 `https://llm.kxpms.cn/routing-v2/credentials`，点击凭据详情：

1. 进入「模型」tab
2. 查看「双层槽位信息」面板
3. 观察 **Layer 2: 并发详情**
4. ✅ 正常：每个 slot 的 inflight ≤ 10
5. ❌ 异常：某个 slot 的 inflight > 10（说明修复未生效）

### 方法 2：Redis 直连检查

```bash
# 连接 Redis
redis-cli -h <redis_host> -a <redis_password>

# 查看某个凭据的所有 slot
SCAN 0 MATCH llmgw:cred_fp_slot:11:* COUNT 100

# 查看某个 slot 的 inflight 计数
GET llmgw:cred_fp_inflight:11:0
GET llmgw:cred_fp_inflight:11:1
# ... 依此类推

# ✅ 正常：返回值 ≤ 10
# ❌ 异常：返回值 > 10
```

### 方法 3：日志监控

```bash
# 查看 slot 复用日志（正常场景）
grep "cred_fp_slot reused existing slot" /var/log/llm-gateway/gateway.log | tail -20

# 查看 inflight 达上限日志（新增，说明修复生效）
grep "inflight limit reached, fallback to LRU" /var/log/llm-gateway/gateway.log | tail -20
```

**期望结果**：
- 部署后，应该能看到 `inflight limit reached` 日志
- minimax-m3 凭据的 slot 占用率应从 100% 降到 50-70%
- 请求成功率应从 ~80% 恢复到 95%+

---

## 系统设置 UI（参考用，修改需重启）

系统设置 UI（`/admin/settings` → Security 分类）会展示以下参数：
- `llmgw_fp_slot_max_inflight_per_slot`（单 slot 最大并发数）
- `llmgw_fp_slot_active_gate_seconds`（活跃槽位保护时间）
- `llmgw_fp_slot_reclaim_idle_seconds`（后台回收空闲阈值）

⚠️ **重要**：这些参数在 settings 注册表里标记为 `HotReload: false`——`credentialfpslot.Manager.cfg` 在进程启动时一次性读取，**修改后必须重启进程才生效**，UI 上改动不会热加载。要调整运行时值，请通过环境变量 + 重启的方式：

```bash
export LLM_GATEWAY_CREDENTIAL_FP_SLOT_MAX_INFLIGHT_PER_SLOT=20
systemctl restart llm-gateway
```

---

## 回滚方案

如果修复导致意外问题，可快速回滚：

```bash
# 方法 1：恢复旧二进制
systemctl stop llm-gateway
cp gateway-v3.2.1 gateway
systemctl start llm-gateway

# 方法 2：调大上限（临时缓解）
# 设置为 50，相当于"禁用"限制
export LLM_GATEWAY_CREDENTIAL_FP_SLOT_MAX_INFLIGHT_PER_SLOT=50
systemctl restart llm-gateway
```

---

## 预期效果

| 指标 | 修复前 | 修复后 |
|------|--------|--------|
| minimax-m3 slot 占用率 | 100% (20/20) | 50-70% (10-14/20) |
| 单 slot 最大 inflight | 无限制（实测 20+） | 10（可配置） |
| 请求成功率 | ~80% | 95%+ |
| slot 轮换 | 几乎不轮换 | 正常轮换 |
| 5 客户端 20 并发分布 | 5 个 slot | 10-15 个 slot |

---

## 技术细节

### 修改的文件
- `credentialfpslot/slot.go` — 核心修复：`acquireSlotScript` Lua 增加 maxInflight 上限检查；删除 `Acquire` 快速路径（TOCTOU + 与脚本重复）
- `credentialfpslot/slot.go` — **额外修复**：`acquireLRUScript`/`availableCountScript`/`resetSlotsScript` 的双冒号 key bug（`prefix(带尾冒号) + ':' + slot` 产生 `...:N::slot`，导致脚本读写的 key 与 Go 层完全脱节，inflight 计数分裂、AvailableCount 永远报空闲）
- `credentialfpslot/slot.go` — Config 增加 MaxInflightPerSlot 字段 + `resolveMaxInflightPerSlot()`
- `credentialfpslot/slot_max_inflight_test.go` — 新增测试：Lua 上限强制、LRU fallback、双冒号回归
- `config/config.go` — 增加环境变量 `LLM_GATEWAY_CREDENTIAL_FP_SLOT_MAX_INFLIGHT_PER_SLOT`
- `cmd/gateway/main.go` — 传递配置到 fpSlots Manager
- `settings/spec_fpslot.go` — 新增系统设置 spec（`HotReload: false`，修改需重启）
- `settings/specs.go` — 注册 FpSlot 设置

### 向后兼容性
- ✅ 完全向后兼容
- ✅ 未设置环境变量时使用默认值 10
- ✅ 旧版本的 Redis 数据结构无需迁移
- ✅ 不影响现有 API 和数据库 schema

---

## 联系人
- 技术负责人：[您的名字]
- 部署日期：2026-07-02
- 版本号：V3.2.2
