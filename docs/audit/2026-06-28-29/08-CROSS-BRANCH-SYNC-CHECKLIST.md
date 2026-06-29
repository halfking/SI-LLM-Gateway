# 08 · 跨分支同步操作清单（关键交付物）

**审计日期**：2026-06-29
**目标读者**：把 `github` 分支最近 2 天提交同步到**其他分支**（`main`、release 分支、staging 分支）的工程师
**核心目标**：让其他分支的代码 review 和 cherry-pick 操作**有据可依、有序可循、有法可验**

---

## 一、同步策略选择

| 策略 | 适用场景 | 优点 | 缺点 | 推荐度 |
|------|----------|------|------|--------|
| **A. 完整 cherry-pick** | 与 `github` 分支差异小 | 保留 commit 历史；可逐项 revert | 可能引发 3-way merge 冲突 | ⭐⭐⭐ 推荐 |
| **B. 挑选性移植** | 与 `github` 分支差异大；只想要部分修复 | 灵活 | 需手动验证依赖关系 | ⭐⭐ 谨慎 |
| **C. 整体重写** | 已计划大重构；分支差异极大 | 干净 | 工作量大 | ⭐ 不推荐本次 |

**建议**：
- 与 `github` 分支 ≤ 50 个 commit 差异 → **策略 A**
- 与 `github` 分支 > 50 个 commit 差异 → **策略 B**，按本清单"推荐同步顺序"分批

## 二、逐 Commit 操作表

> ☐ = 待办；☑ = 已完成；✗ = 已拒绝（说明原因）

### 2.1 第一批：P0 + P1 紧急修复（必同步）

| Commit | 操作 | 前置依赖 | 验证步骤 | 风险 | 决策 |
|--------|------|----------|----------|------|------|
| `9c614f44` P0 硬超时 | ☐ cherry-pick | 无 | 跑 `routing/hard_timeout_test.go` 3 个测试 | 中 | ☐ |
| `a1417474` P1 missing_model 400 | ☐ cherry-pick | 无 | 跑 `TestChatHandler_MissingModelReturns400` | 低 | ☐ |
| `7576c021` P1 会话+重连 | ☐ cherry-pick | 无 | 跑 `reconnect/config_test.go` + `session_resolution_test.go` + `sessions/session_test.go` | 中 | ☐ |
| `b1ba5be3` 部署验证 | ☐ 跳过 | 需 71 服务器 | — | — | ☐ |
| `a5249500` gitignore | ☐ cherry-pick | 无 | 检查 `.gitignore` 内容 | 极低 | ☐ |

### 2.2 第二批：P2 性能 + 新功能（评估后同步）

| Commit | 操作 | 前置依赖 | 验证步骤 | 风险 | 决策 |
|--------|------|----------|----------|------|------|
| `b6ea9ff6` 内容去重 | ☐ cherry-pick | **必须先有 `7576c021`** | 跑 `relay/content_dedup_test.go` 11 个测试 | 中 | ☐ |
| `b65a7e94` 性能优化 | ☐ cherry-pick | 无；需 PG ≥ 14 | 跑 `credentialfpslot/slot_batch_test.go` + DB DDL | **中（DDL）** | ☐ |

### 2.3 随附同步

| Commit | 操作 | 说明 |
|--------|------|------|
| `tests/prod_e2e/` | ☐ cherry-pick | 回归测试套件（仅源文件，不含 results/） |
| `scripts/deploy-to-71.sh`（原版） | ☐ cherry-pick | 部署脚本原版，**不含本地密码改动** |
| `scripts/verify-deployment.sh` | ☐ cherry-pick | 部署验证 |

### 2.4 不建议同步

| Commit | 原因 |
|--------|------|
| `39740fe8` | 纯文档 commit，目标分支自生成 changelog 即可 |
| 根目录 `DEPLOYMENT_*.md` | 71 服务器部署产物，与目标分支无关 |
| 本地未提交改动（`scripts/deploy-to-71.sh` 密码部分） | 安全风险 |
| `llm-gateway-*` 二进制 | 不在仓库内 |

## 三、推荐同步顺序（按依赖序）

```
Step 1  ──→  9c614f44  P0 硬超时（独立）
   │
Step 2  ──→  a1417474  P1 missing_model（独立）
   │
Step 3  ──→  7576c021  P1 会话+重连（独立，但为 b6ea9ff6 提供包）
   │
Step 4  ──→  b6ea9ff6  P2 内容去重（依赖 7576c021）
   │
Step 5  ──→  b65a7e94  P2 性能优化（独立，但需 PG ≥ 14 + DDL）
   │
Step 6  ──→  a5249500  .gitignore（独立）
   │
Step 7  ──→  tests/prod_e2e/（独立）
   │
Step 8  ──→  scripts/*（独立）
```

**为什么这个顺序**：
- **Step 1-2**：紧急修复优先，无依赖
- **Step 3**：为 Step 4 提供基础（`reconnect/` 包）
- **Step 4**：依赖 Step 3，自身独立
- **Step 5**：独立但需要 DDL 窗口，单独安排
- **Step 6-8**：辅助产物，可分散到任意 commit 之后

## 四、跨分支验证清单（移植后逐项打勾）

### 4.1 单元测试

```bash
# 必跑（覆盖 5 张审计卡）
go test ./routing/... -run TestDoUpstreamWithHardTimeout -v
go test ./relay/... -run "TestChatHandler_MissingModelReturns400|TestResolveSessionFromRequest|TestComputeFingerprint|TestCheckAndReplay|TestParseMessagesForFingerprint" -v
go test ./reconnect/... -v
go test ./sessions/... -run TestSessionManager -v
go test ./credentialfpslot/... -run TestBatchStats -v
```

- [ ] 全部 PASS
- [ ] 0 FAIL
- [ ] 0 SKIP（除非有 ENV 标记的 skip）

### 4.2 编译 & 静态检查

```bash
go build ./...
go vet ./...
# 建议加：staticcheck ./...（如已配置）
```

- [ ] 编译无 error
- [ ] vet 无 warning

### 4.3 集成 / 端到端

```bash
# 1. 启动本地网关
./llm-gateway &

# 2. 跑 prod_e2e 套件
cd tests/prod_e2e && GATEWAY=http://localhost:8080 API_KEY=sk-xxx bash run_all.sh

# 3. 收集 jsonl 结果
cat results/*.summary | sort -u
```

- [ ] 10 套件全部退出码 0
- [ ] 92 PASS / 12 FAIL / 12 SKIP（与 `github` 分支 HEAD 持平或更好）
- [ ] F2 missing_model 4 个子用例全 PASS

### 4.4 手工验证 curl

> 完整命令见各审计卡"最小重现"段落。

- [ ] P0 硬超时：发送大请求 + 模拟挂起（可临时把 `upCtx` 改短），确认 < upCtx 时间内返回
- [ ] P1 missing_model：发送无 model 字段请求，确认返回 400
- [ ] P1 重连配置：`GET /api/reconnect/config` 返回 `{"enabled":false,...}`
- [ ] P2 性能优化：访问 `/providers/14`，DevTools 看 DB 查询 < 50ms；3 个前端请求并发
- [ ] P2 内容去重：开启 dedup → 同内容两次请求 → 第二次响应头有 `X-Gw-Content-Replay: true`

### 4.5 配置项核对

| 配置 | 来源 commit | 目标分支动作 |
|------|-------------|--------------|
| `reconnect.enabled` | 7576c021 | 加入 config.json，默认 `false` |
| `reconnect.auto_resume_by_default` | 7576c021 | 加入 config.json，默认 `false` |
| `reconnect.cache_ttl` | 7576c021 | 加入 config.json，默认 `168h` (7d) |
| `reconnect.max_cache_body_bytes` | 7576c021 | 加入 config.json，默认 `1048576` |
| `reconnect.content_dedup_enabled` | b6ea9ff6 | 加入 config.json，默认 `false` |
| `reconnect.content_dedup_window` | b6ea9ff6 | 加入 config.json，默认 `10m` |
| `reconnect.content_dedup_depth` | b6ea9ff6 | 加入 config.json，默认 `3` |

- [ ] 所有配置项已加入目标分支的 config.json
- [ ] 默认值与源分支一致
- [ ] 部署脚本的 env 注入（若有）已更新

### 4.6 数据库迁移核对

| 迁移 | 来源 commit | 目标分支动作 |
|------|-------------|--------------|
| `reconnect_global_config` 表 | 7576c021 | **未提供迁移 SQL**；需手动从 `reconnect.Manager.SaveToDB` 反推 |
| `reconnect_tenant_config` 表 | 7576c021 | 同上 |
| `ALTER TABLE model_probe_runs SET ACCESS METHOD heap` | b65a7e94 | **未提供迁移 SQL**；需手动从 `PERFORMANCE_OPTIMIZATION_REPORT.md` 复制 |
| `CREATE INDEX idx_mpr_provider_recent_failures` | b65a7e94 | 同上 |

- [ ] reconnect_*_config 表已创建
- [ ] model_probe_runs 已转为 heap
- [ ] 索引已创建（`\di+ idx_mpr_provider_recent_failures` 可查）

### 4.7 路由注册核对

- [ ] `admin/reconnect_config.go` 中的 `GET/POST /api/reconnect/config` 已在 `main.go` 注册
- [ ] （如有） `/api/reconnect/config/{tenantID}` 路由已注册

### 4.8 监控 / 告警核对

- [ ] `metrics.go` 中 `error_code_total{code="missing_model"}` 暴露
- [ ] （建议）增加 `upstream_hard_timeout_total` 指标
- [ ] （建议）增加 `content_dedup_hit_total` / `content_dedup_miss_total` 指标
- [ ] 告警规则：missing_model 400 突增（> 5% RPS）= 客户端异常

## 五、优化机会清单（其他分支可借机改进）

> 这些是**源分支作者未完成**的 P1/P2 优化点；其他分支可在同步时**顺手实现**。

### 5.1 P0 硬超时（`9c614f44`）
- [ ] 抽 `doUpstream*HardTimeout` 公共函数到 `routing/internal/timeout/`，供 completions / embeddings 复用
- [ ] watchdog 时间改为 config（当前硬编码 5s）
- [ ] 增加 `upstream_hard_timeout_total{provider,model}` metric

### 5.2 P1 missing_model（`a1417474`）
- [ ] 抽 `validateModelField()` 到 `relay/request_context.go`，messages/responses 共用
- [ ] 补 `max_tokens` 缺失校验（已有 `missing_max_tokens` 错误码但未在 chat handler 检查）
- [ ] 修 F3 `messages=[]` 边界（仍触发上游挂起）

### 5.3 P1 会话+重连（`7576c021`）
- [ ] 补 `reconnect_*_config` 迁移 SQL（commit 缺）
- [ ] `Touch()` 双写 DB+Redis 失败兜底
- [ ] `IsEnabledForTenant` 加指标埋点

### 5.4 P2 性能优化（`b65a7e94`）
- [ ] 补 `db/migrations/0XX_model_probe_runs_heap.sql` 迁移文件（commit 缺）
- [ ] 实现 `BatchAcquire` / `BatchRelease`（与 `BatchStats` 对称）
- [ ] `admin/provider_credential.go` 的 `listCredentials` 加 `LIMIT` 优化

### 5.5 P2 内容去重（`b6ea9ff6`）
- [ ] 覆盖 `messages` / `responses` handler（当前仅 ChatHandler）
- [ ] 自适应 depth 策略
- [ ] 跨 session dedup（service-token 场景）
- [ ] `metrics.go` 增加 `content_dedup_hit_total` / `content_dedup_miss_total`

### 5.6 测试 & 部署（`9c614f44` / `b1ba5be3` / `a5249500`）
- [ ] `deploy-to-71.sh` 移除 sshpass 硬编码密码
- [ ] `common.sh` 抽公共 SDK（用 Go 重写以便 CI 集成）
- [ ] `.gitignore` 补 `coverage.out` / `*.test`

## 六、回滚方案

如同步后发现问题：

```bash
# 单 commit 回滚
git revert <commit-sha>

# 大批量回滚（保留前 N 个 commit）
git revert <start-sha>..<end-sha>

# 重新部署
bash scripts/deploy-to-71.sh --skip-tests
```

**回滚后验证**：
- [ ] prod_e2e 套件 92 PASS 数字保持或更好
- [ ] 监控无新增 error spike
- [ ] 客户端无新增 4xx/5xx 投诉

## 七、附：分主题审计卡快速跳转

- [00 · 索引](00-INDEX.md)
- [01 · 总览与风险矩阵](01-SUMMARY.md)
- [02 · P0 上游挂起硬超时](02-P0-upstream-hard-timeout.md)
- [03 · P1 missing_model 400](03-P1-missing-model-400.md)
- [04 · 会话统一 + 断线重连](04-session-and-reconnect.md)
- [05 · Provider 页 97% 性能优化](05-provider-perf-97pct.md)
- [06 · 基于内容的请求去重](06-content-based-dedup.md)
- [07 · 端到端测试 + 部署脚本](07-test-and-deploy-artifacts.md)

---

**操作完毕请将本清单的"☑/☐"状态更新后归档到目标分支的 PR 描述中。**
