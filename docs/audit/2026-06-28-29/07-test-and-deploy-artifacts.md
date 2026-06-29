# 07 · 端到端测试套件 + 部署脚本 + 杂项

**涵盖 commit**：
- `9c614f44` — 含 `tests/prod_e2e/` 10 套件（核心）
- `b1ba5be3` — 部署验证 + 150s 超时调整 + 报告更新
- `a5249500` — `.gitignore` 排除 prod_e2e 临时文件
- `7576c021` — `scripts/deploy-to-71.sh` + `scripts/verify-deployment.sh`

**作者**：halfking <kimmy.huang@gmail.com>
**时间**：2026-06-29 02:57 ~ 12:05 (+0800)
**优先级**：**强烈建议同步**（含 P0 修复的回归验证工具链）
**破坏性变更**：否
**依赖**：见各节

---

## 一、`tests/prod_e2e/` 端到端测试套件（核心交付物）

> **9c614f44 + b1ba5be3 联合产出**

### 1.1 套件清单（10 个）

| # | 文件 | 行数 | 覆盖类别 | 关键测试 |
|---|------|------|----------|----------|
| 01 | `tests/prod_e2e/01_health.sh` | 94 | 健康 & 元数据 | `/healthz` / `/metrics` / `/v1/models` / 401 路径 |
| 02 | `tests/prod_e2e/02_single_vendor.sh` | 116 | 单供应商路由 | minimax / glm / deepseek / kimi / qwen / doubao / mimo / mistral / llama |
| 03 | `tests/prod_e2e/03_multi_cred.sh` | 102 | 多凭据路由 | glm-4.7 / kimi-k2.6 / minimax-m2.7 / session 独立 |
| 04 | `tests/prod_e2e/04_protocols.sh` | 203 | 协议转换 | Q1/Q2/Q3/Q4 + Responses + Legacy + Tool calls |
| 05 | `tests/prod_e2e/05_streaming.sh` | 225 | 流式响应 | SSE 完整性、首字节延迟、断路器 |
| 06 | `tests/prod_e2e/06_errors.sh` | 169 | 错误处理 | 4xx/5xx 路径、模型未找到、限流 |
| 07 | `tests/prod_e2e/07_auto_route.sh` | 115 | 自动路由 | multi-model fallback、auto-route-mode |
| 08 | `tests/prod_e2e/08_concurrency.sh` | 225 | 并发稳定性 | 100 并发、连接复用 |
| 09 | `tests/prod_e2e/09_edge_cases.sh` | 187 | 边界 | F2 missing_model / F3 messages=[] / 巨型 body |
| 10 | `tests/prod_e2e/10_data_correctness.sh` | 132 | 数据正确性 | request_logs / 凭据 / 限流计数 |

**辅助**：
- `tests/prod_e2e/common.sh` (253 行) — 公共函数（curl 包装、jsonl 输出、统计）
- `tests/prod_e2e/run_all.sh` (53 行) — 一键跑全部

### 1.2 测试结果（生产环境 `https://llm.kxpms.cn`）

| 阶段 | 时间 | 通过 | 失败 | 跳过 | 备注 |
|------|------|------|------|------|------|
| 9c614f44（修复后） | 06-29 02:57 | 91 | 14 | 12 | 14 失败全为上游挂起根因 |
| b1ba5be3（部署验证） | 06-29 05:07 | 90 | 14 | 12 | 失败原因为"数据层缺凭据"或测试编排 |
| a1417474 之后 | 06-29 11:34 | 92 | 12 | 12 | F2 missing_model 全通过 |
| **本目录生成时（HEAD `b6ea9ff6`）** | 06-29 13:15 | 92 | 12 | 12 | （沿用此前数据） |

### 1.3 关键发现 F2

> **9c6044 之前**：F2（missing_model）返回 503，**期望 400**。
> **a1417474 修复后**：F2 全 4 个子用例返回 400。
> 详见 [`03-P1-missing-model-400.md`](03-P1-missing-model-400.md)。

### 1.4 跨分支同步要点

- ✅ **强烈建议同步**：可在目标分支上**快速验证 P0 修复是否生效**
- ✅ 套件对环境要求低（仅需 `curl` + `bash` + 目标 endpoint + API key）
- ⚠️ `tests/prod_e2e/results/` 下的 `.jsonl` / `.summary` 文件**不需要 cherry-pick**（已被 `.gitignore` 排除）
- ⚠️ `b1ba5be3` 调整了超时到 150s（适配 `sync_retry` 窗口），目标分支同步前应阅读 `tests/prod_e2e/common.sh` 中的 `TIMEOUT_*` 变量

**最小重现**：

```bash
cd tests/prod_e2e
GATEWAY=https://gateway.example.com API_KEY=sk-xxx bash run_all.sh
# 期望：10 个套件全部退出码 0；可通过 jq 聚合 jsonl 统计
```

## 二、`.gitignore` 更新（`a5249500`）

**改动**（4 行新增）：

```gitignore
# 排除 prod_e2e 流式捕获临时文件
tests/prod_e2e/results/stream_tmp/
tests/prod_e2e/results/*.summary
```

**目的**：避免大批 SSE chunk 临时文件污染 git 状态。

**同步价值**：低。其他分支可手动加这两行即可。

## 三、部署脚本（`7576c021`）

### 3.1 `scripts/deploy-to-71.sh`（158 行）

| 阶段 | 内容 |
|------|------|
| 1. 本地编译 | `go build -o llm-gateway-$(git rev-parse --short HEAD)` |
| 2. 上传到 71 | `scp` 到 `root@<71>:${REMOTE_DIR}/` |
| 3. 远程部署 | ssh 远程执行 systemd 重启、health check |
| 4. dry-run | `--dry-run` 仅打印，不执行 |

**关键变量**：

```bash
SERVER_71="root@<71服务器IP>"   # 需替换为实际 IP
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway"
```

### 3.2 ⚠️ 本地未提交改动（`scripts/deploy-to-71.sh` 存在 dirty）

通过 `git diff scripts/deploy-to-71.sh` 可看到本地有**模式变更 + 增强**：

```diff
-SERVER_71="root@<71服务器IP>"
+SERVER_71="root@llm.kxpms.cn"
+SERVER_71_IP="14.103.174.71"
 REMOTE_DIR="/opt/llm-gateway-go"
 SERVICE_NAME="llm-gateway"
+
+# SSH 认证配置
+export SSHPASS="${SSHPASS:-Kaixuan2025&9900#}"
+SSH_CMD="sshpass -e ssh -o StrictHostKeyChecking=no"
+SCP_CMD="sshpass -e scp -o StrictHostKeyChecking=no"
```

**变更要点**：
- SERVER_71 改为 hostname
- 新增 SERVER_71_IP 备用
- 改用 sshpass 注入密码（**⚠️ 密码硬编码在脚本里，敏感信息泄漏**）
- scp/ssh 命令改为通过 $SSH_CMD/$SCP_CMD 变量

**跨分支同步建议**：
- ✅ 同步**原版** `scripts/deploy-to-71.sh`（7576c021 提交版本）
- ⚠️ **不要同步**本地未提交的密码改动（建议改用 `~/.ssh/config` + SSH 密钥，或在 CI 中注入 `SSHPASS` 环境变量）

### 3.3 `scripts/verify-deployment.sh`（198 行）

**内容**：5 项部署后自动验证
1. `/healthz` 返回 200
2. `/metrics` 暴露关键指标
3. 至少一个模型 smoke test 通过
4. 凭据状态查询正常
5. 日志无 ERROR 级别记录

**未追踪的辅助脚本**：
- `scripts/deploy-session-fix.sh`（仓库内未追踪，仅本地）

## 四、相关报告（根目录）

> 这些是部署/验证过程产物，**不属于审计代码点**，但可作为同步时的背景资料。

| 文件 | 用途 |
|------|------|
| `DEPLOYMENT_2026-06-29.md` | 7576c021 的完整部署指南 |
| `DEPLOYMENT_STATUS.md` | 部署进度跟踪 |
| `DEPLOYMENT_STATUS_REPORT.md` | 部署状态报告 |
| `DEPLOYMENT_SUCCESS_REPORT.md` | 部署成功报告 |
| `MANUAL_DEPLOY_GUIDE.md` | 手动部署指南 |
| `tests/prod_e2e/REPORT.md` | prod_e2e 测试报告（多版） |

**同步建议**：仅同步 `tests/prod_e2e/REPORT.md`（用于理解 P0 修复背景）；根目录的 `DEPLOYMENT_*.md` 是 71 服务器部署产物，目标分支不需要。

## 五、跨分支同步要点（综合）

### 5.1 必带文件

```
tests/prod_e2e/01_health.sh ... 10_*.sh        # 10 个测试套件
tests/prod_e2e/common.sh                       # 公共函数
tests/prod_e2e/run_all.sh                      # 一键运行
tests/prod_e2e/REPORT.md                       # 测试报告
.gitignore                                     # +4 行
scripts/deploy-to-71.sh                        # 原版（不含密码）
scripts/verify-deployment.sh                   # 部署后验证
```

### 5.2 可选同步

```
scripts/deploy-session-fix.sh                  # 本地辅助脚本（未追踪）
DEPLOYMENT_2026-06-29.md                       # 部署指南文档
```

### 5.3 不建议同步

- 根目录的 `DEPLOYMENT_*.md` 报告
- 本地未提交的 sshpass 密码改动
- `llm-gateway-*` 二进制文件

## 六、风险与回滚

| 维度 | 评估 |
|------|------|
| 同步风险 | 极低（不涉及核心代码） |
| 部署风险 | 中（修改 systemd 服务需谨慎） |
| 测试套件 | 完全独立，可随时删除 `tests/prod_e2e/` 不影响线上 |
| 部署脚本 | 建议先 dry-run：`bash scripts/deploy-to-71.sh --dry-run` |

## 七、未来优化

1. **`deploy-to-71.sh` 移除 sshpass**：应改用 SSH 密钥 + `~/.ssh/config`；密码写入 git 历史是安全风险。
2. **prod_e2e 增加并发基准**：当前 100 并发来自 08_concurrency.sh，可加压测曲线图。
3. **`common.sh` 抽公共 SDK**：10 个套件重复了大量 curl 包装，可考虑用 Go 重写以便 CI 集成。
4. **.gitignore 缺 `coverage.out` / `*.test`**：建议补全 Go 测试常见忽略。
