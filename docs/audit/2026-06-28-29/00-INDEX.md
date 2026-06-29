# 最近 2 天分支同步审计 — 文档索引

**审计日期**：2026-06-29
**审计模式**：只读仓库扫描 + commit 区间 diff
**审计范围**：分支 `github`（HEAD `b6ea9ff6`）的 2026-06-28 ~ 2026-06-29 提交
**目标读者**：其他分支（`main`、各 release/feature 分支）的同步工程师、运维 SRE、QA

---

## 一、文档导览

本目录是为"在其它分支进行同步审计与检查和优化"而整理的结构化审计集，共 9 份详细文档。
**根目录另有 1 份归并后的总览文档**：

| 入口 | 位置 | 用途 |
|------|------|------|
| 🌟 **总览入口** | [`/CHANGELOG_2026-06-28-29.md`](../../CHANGELOG_2026-06-28-29.md) | 按 4 大功能领域归类，适合先读这一份建立全景视角 |

### 1.1 详细审计卡

| # | 文件 | 内容 | 必读程度 |
|---|------|------|----------|
| 00 | `00-INDEX.md`（本文件） | 文档导览 + commit 速查 | ⭐⭐⭐ |
| 01 | [`01-SUMMARY.md`](01-SUMMARY.md) | 2 天修改全景 + 风险矩阵 + 同步顺序 | ⭐⭐⭐ |
| 02 | [`02-P0-upstream-hard-timeout.md`](02-P0-upstream-hard-timeout.md) | 9c614f44 审计卡：上游挂起硬超时 | ⭐⭐⭐ P0 |
| 03 | [`03-P1-missing-model-400.md`](03-P1-missing-model-400.md) | a1417474 审计卡：missing_model 返回 400 | ⭐⭐ P1 |
| 04 | [`04-session-and-reconnect.md`](04-session-and-reconnect.md) | 7576c021 审计卡：会话统一 + 断线重连配置 | ⭐⭐ P1 |
| 05 | [`05-provider-perf-97pct.md`](05-provider-perf-97pct.md) | b65a7e94 审计卡：Provider 页 97% 性能优化 | ⭐ P2 |
| 06 | [`06-content-based-dedup.md`](06-content-based-dedup.md) | b6ea9ff6 审计卡：基于内容的请求去重 | ⭐ P2 |
| 07 | [`07-test-and-deploy-artifacts.md`](07-test-and-deploy-artifacts.md) | tests/prod_e2e + 部署脚本 + .gitignore | ⭐⭐ |
| 08 | [`08-CROSS-BRANCH-SYNC-CHECKLIST.md`](08-CROSS-BRANCH-SYNC-CHECKLIST.md) | **跨分支同步操作清单（关键交付物）** | ⭐⭐⭐ |

## 二、覆盖的 8 个 Commit 速查

| SHA | 时间 (+0800) | 等级 | 类型 | 一句话 |
|-----|--------------|------|------|--------|
| `9c614f44` | 06-29 02:57 | **P0** | fix | 上游挂起硬超时 + 10 套件 e2e 测试 |
| `a5249500` | 06-29 02:58 | chore | chore | 排除 prod_e2e 流式捕获临时文件 |
| `b1ba5be3` | 06-29 05:07 | test | test | 部署验证 + 150s 超时 + 生产报告 |
| `a1417474` | 06-29 11:34 | **P1** | fix | missing_model 返回 400 而非 503 |
| `7576c021` | 06-29 12:05 | **P1** | feat+fix | 会话统一管理 + 断线重连配置 |
| `b65a7e94` | 06-29 12:51 | **P2** | perf | Provider 页加载 1007ms → 28ms（↓97%） |
| `39740fe8` | 06-29 12:54 | docs | docs | 完整项目 changelog（本目录不审计） |
| `b6ea9ff6` | 06-29 13:15 | **P2** | feat | 基于内容的请求去重（新功能） |

> **说明**：`39740fe8` 仅包含 `PROJECT_CHANGELOG_FULL.md` 一份文档，不含代码改动；其他分支需要时直接复制或重新生成即可，本目录不为其单独建审计卡。

## 三、风险与影响一览

| 风险维度 | 涉及 commit | 同步时需注意 |
|----------|-------------|--------------|
| 触及核心执行路径 | 9c614f44, a1417474, b6ea9ff6 | 必须先在测试环境验证 |
| 新增包 / 新 import | 7576c021（`reconnect/`）, b6ea9ff6（`relay` 新文件） | go.mod 无新增依赖 |
| 数据库 schema 变更 | b65a7e94（`ALTER TABLE model_probe_runs SET ACCESS METHOD heap`） | DDL 操作，需停机或 PG ≥ 14 在线操作 |
| HTTP 路由新增 | 7576c021（`/api/reconnect/config`） | main.go 注册 |
| 配置项新增 | 7576c021, b6ea9ff6 | config.json / env 同步 |
| 环境变量新增 | 7576c021 | 部署脚本需更新 |
| 二进制/API 兼容性 | 全部保持向后兼容 | 默认行为不变（reconnect / content_dedup 默认 disabled） |

## 四、阅读建议

1. **第一次接触 / 业务方读者**：先读根目录的 [`/CHANGELOG_2026-06-28-29.md`](../../CHANGELOG_2026-06-28-29.md)，按 4 大功能领域建立全景视角。
2. **仅做代码 review（不做同步）**：从 `01-SUMMARY.md` 开始，速读风险矩阵和 P0 章节。
3. **要做同步 cherry-pick**：从 `01-SUMMARY.md` 跳到 `08-CROSS-BRANCH-SYNC-CHECKLIST.md`，按表操作。
4. **要做性能/新功能评估**：直接读 `05` 和 `06`，并关注作者列出的"未来优化"段落。
5. **QA 回归验证**：优先跑 `02` / `03` / `04` / `06` 末尾的"最小重现命令"段落。
