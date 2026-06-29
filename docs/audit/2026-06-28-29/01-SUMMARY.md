# 最近 2 天修改全景与风险矩阵

**审计日期**：2026-06-29
**审计模式**：只读 commit diff + 代码定位
**审计范围**：分支 `github`，8 个 commit（已剔除 `39740fe8` 纯文档 commit），代码增删合计 ≈ +6 000 行 / -27 行
**核心问题域**：生产可用性（P0/P1 修复）+ 性能优化 + 新功能（去重）+ 端到端测试

---

## 一、修改全景（按风险等级重组）

| # | 主题 | 等级 | 涉及 commit | 关键文件 / 行号 | 净增/改 |
|---|------|------|-------------|----------------|---------|
| 1 | 上游挂起硬超时（核心路径 P0） | **P0** | `9c614f44` | `routing/executor_chat.go:988-1110` | +160 |
| 2 | missing_model 修复为 400 | **P1** | `a1417474` | `relay/handler.go:453-490, 854-862, 2212, 2258` | +59 |
| 3 | 会话统一管理 + 断线重连配置 | **P1** | `7576c021` | `relay/session_resolution.go:1-249` + `reconnect/`（新包） | +1 200 |
| 4 | Provider 页性能优化 97% | **P2** | `b65a7e94` | `credentialfpslot/slot.go:1253+` + `admin/*` + `web/src/views/ProviderDetailView.vue:42` | +380 |
| 5 | 基于内容的请求去重（新功能） | **P2** | `b6ea9ff6` | `relay/content_dedup.go:1-216` + `relay/handler.go:1325-1370` | +430 |
| 6 | 端到端测试套件 + 部署脚本 + 报告 | — | `9c614f44` / `b1ba5be3` / `a5249500` / `7576c021` | `tests/prod_e2e/`（10 套件）+ `scripts/*` | +5 200 |

> 注：行数粗略估算（与 git log --stat 一致），含新增/修改。

## 二、跨主题关联表

> 其他分支同步时，**共享文件 / 共享配置 / 共享接口** 是最容易引发合并冲突的地方。

| 共享点 | 涉及 commit | 同步注意 |
|--------|-------------|----------|
| `reconnect/config.go`（含 `ContentDedupEnabled/Window/Depth` 字段） | `7576c021` + `b6ea9ff6` | 必须**先 cherry-pick 7576c021** 拿到 `reconnect/` 包，**再 cherry-pick b6ea9ff6** 拿到 `ContentDedup*` 配置项 |
| `relay/handler.go`（多 commit 改动） | `a1417474` + `b6ea9ff6` | 两个 commit 都改了 `handler.go`，cherry-pick 时按时间序，并人工解决可能的小冲突 |
| `routing/executor_chat.go` | 仅 `9c614f44` | 无冲突，独立可移植 |
| `tests/prod_e2e/results/` 临时文件 | `a5249500` | 通过 `.gitignore` 解决，不需要 cherry-pick 结果文件 |
| `scripts/deploy-to-71.sh` | `7576c021` 提供原始版 + 本地未提交改动 | 目标分支应优先使用 `7576c021` 提供的脚本，再叠加本地 IP / SSH 认证增强 |
| `reconnect.Config` 字段名 | `7576c021` 定义基础字段 + `b6ea9ff6` 追加 dedup 字段 | 同步 `7576c021` 即可拿到 `ContentDedup*` 字段所在的结构体（b6ea9ff6 只是在同结构体上 append） |
| 数据库 schema 变更 | 仅 `b65a7e94` 中的 `model_probe_runs` 改 `columnar→heap` | 独立可移植；同步后需要单独跑 DDL |

## 三、风险矩阵（优先级 × 影响面）

| 主题 | 业务影响 | 同步风险 | 性能影响 | 兼容性 | 紧急度 |
|------|----------|----------|----------|--------|--------|
| P0 上游挂起硬超时 | 高（生产事故，3-4 分钟/请求） | 中（触及核心路径） | 正向（节省后端资源） | 100% 向后兼容 | **立即同步** |
| P1 missing_model 400 | 中（错误码一致性） | 低（单点改 handler.go） | 微弱（提前拒绝） | 100% 向后兼容 | **本周内** |
| P1 会话+重连配置 | 中（修空响应问题） | 中（新建包 + admin 路由） | 中性 | 100% 向后兼容（默认 disabled） | **本周内** |
| P2 Provider 性能优化 | 低（仅运营端） | 低（DDL + 索引 + 前端并发） | **正向 97%** | 100% 向后兼容 | 视目标分支需求 |
| P2 内容去重 | 低（新功能） | 中（relay/handler.go 改动 + 新增字段） | **正向（命中时 0 延迟）** | 默认 disabled，需主动开 | 视目标分支需求 |

## 四、按风险×价值的推荐同步顺序

> **核心原则**：先同步会"修事故"的 P0/P1，再考虑性能与新功能。

**第一批（必须同步，单 PR 可合）**：
1. `9c614f44` P0 上游挂起硬超时（独立可移植，零依赖）
2. `a1417474` P1 missing_model 400（独立可移植，零依赖）
3. `7576c021` P1 会话统一 + 断线重连配置（独立可移植，新增包）
   - 顺带 `scripts/deploy-to-71.sh` + `scripts/verify-deployment.sh`（含部署所需的 P0 工具链）

**第二批（评估后同步）**：
4. `b6ea9ff6` P2 内容去重（**前置依赖**：必须先有 `7576c021` 提供的 `reconnect/` 包）
5. `b65a7e94` P2 Provider 性能优化（独立，但含 DDL，谨慎评估）

**随附同步（强烈建议）**：
- `tests/prod_e2e/` 完整 10 套件 + `run_all.sh`（用作同步后回归验证）
- `.gitignore` 的 prod_e2e 流式捕获排除（`a5249500`）
- `tests/prod_e2e/REPORT.md` 报告（理解 P0 修复背景）

**不推荐同步**：
- `39740fe8`（纯文档，目标分支自己生成 changelog 即可）

## 五、暂不做（Out-of-Scope）

为避免范围蔓延，本次审计**不覆盖**：
- ❌ `bg/model_probe.go` 的 probe 状态机重构（属历史重构）
- ❌ `db/migrations/` 历史迁移脚本
- ❌ 根目录的 `DEPLOYMENT_*.md` / `MANUAL_DEPLOY_GUIDE.md` 等部署产物（仅在 `07` 章节引用）
- ❌ 未追踪的二进制 `llm-gateway-*`（不在仓库内）
- ❌ `PROJECT_CHANGELOG_FULL.md`（仅作引用，不重新生成）

## 六、下一步

跳转到 [`08-CROSS-BRANCH-SYNC-CHECKLIST.md`](08-CROSS-BRANCH-SYNC-CHECKLIST.md) 开始操作。
