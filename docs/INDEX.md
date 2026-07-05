# llm-gateway-go-2 文档索引

> 自动维护 — 修改后请更新本索引

## 顶层文档

| 文件 | 说明 |
|------|------|
| `README.md` | 项目总览（英文） |
| `README.zh-CN.md` | 项目总览（中文） |

## docs/

| 文件 | 类别 | 说明 |
|------|------|------|
| `README.md` | guide | 文档目录说明 |
| `ARCHITECTURE.md` | architecture | 项目架构总览 |
| `AUDIT_REPORT.md` | audit | 项目审计报告 |
| `ccr-metrics.md` | metrics | CCR 指标说明 |
| `headroom-integration-complete.md` | report | Headroom 集成完成报告 |
| `lessons-learned-2026-07-03.md` | lessons | 7月3日经验教训 |
| `lessons-learned-2026-07-03-partitioned-tables.md` | lessons | 分区表经验教训 |
| `minimax-integration-complete.md` | report | Minimax 集成完成报告 |
| `minimax-tool-calling-fix.md` | guide | Minimax Tool Calling 修复 |
| `partition-audit-report.md` | audit | 分区审计报告 |
| `partition-guide.md` | guide | 分区指南 |
| `partition-test-cases.md` | test-doc | 分区测试用例 |
| `provider-adapter.md` | guide | Provider 适配器说明 |
| `v739_dbpool_refactor.md` | refactor | v739 连接池重构 |
| `2026-06-30-routing-error-transparency.md` | fix | 路由错误透明化 |
| `2026-07-04-stream-chunks-sent-tracking-fix.md` | fix | Stream Chunks 追踪修复 |

### docs/deployment/ — 部署相关

| 文件 | 说明 |
|------|------|
| `DEPLOYMENT_STANDARD.md` | 部署标准流程（活跃） |
| `DEPLOY_CHECKLIST.md` | 部署执行清单（活跃） |
| `DEPLOYMENT_CHECKLIST.md` | 部署检查清单（活跃） |
| `DEPLOYMENT_FINAL_SUMMARY.md` | 生产部署最终总结 |
| `DEPLOYMENT_FINAL_REPORT_2026-07-01.md` | 附件归档功能部署报告 |
| `DEPLOYMENT_REPORT_ATTACHMENT_FEATURE.md` | 附件功能部署详情 |
| `DEPLOYMENT_READY_REPORT.md` | 部署就绪报告 |
| `DEPLOYMENT.md` | 部署总览 |
| `DEPLOYMENT_AUDIT_REPORT_2026-07-01.md` → `archive/` | 7月1日部署审计报告 |
| `DEPLOYMENT_AUDIT_REPORT_2026-07-01_attachments.md` → `archive/` | 附件部署审计报告 |
| `DEPLOYMENT_GUIDE_attachments.md` → `archive/` | 附件部署指南 |
| `DEPLOYMENT_PACKAGE.md` → `archive/` | 部署打包指南 |
| `DEPLOYMENT_REPORT_v733_candcache.md` → `archive/` | v733 缓存部署报告 |
| `DEPLOYMENT_REPORT_v734_billing_mode.md` → `archive/` | v734 计费模式部署 |
| `DEPLOYMENT_REPORT_v735_plan_type_ui.md` → `archive/` | v735 套餐UI部署 |
| `DEPLOYMENT_REPORT_v737_audit_fixes.md` → `archive/` | v737 审计修复部署 |
| `DEPLOYMENT_REPORT_v737_final_audit.md` → `archive/` | v737 最终审计 |
| `DEPLOYMENT_REPORT_v740_audit_fixes.md` → `archive/` | v740 审计修复部署 |
| `DEPLOYMENT_SUMMARY_v2.3.0.md` → `archive/` | v2.3.0 部署总结 |
| `DEPLOYMENT_VERIFICATION_REPORT_2026-07-01.md` → `archive/` | 7月1日部署验证 |

### docs/fixes/ — 问题修复报告

| 文件 | 说明 |
|------|------|
| `CREDENTIALS_SEQUENCE_FIX.md` | 凭据序列修复 |
| `ISSUE_FIX_DATABASE_TIMEOUT.md` | 数据库超时修复 |
| `MINIMAX_CIRCUIT_FIX_DELIVERY_REPORT.md` | MiniMax 熔断修复交付 |
| `MINIMAX_CIRCUIT_OPEN_FIX_2026-07-01.md` | MiniMax 熔断开启修复 |
| `MINIMAX_M3_TOOL_ERROR_FIX_GUIDE.md` | MiniMax M3 Tool 错误修复指南 |
| `MINIMAX_TOOL_CALL_FINAL_REPORT.md` | MiniMax Tool Call 修复最终报告 |
| `MINIMAX_UNKNOWN_KIND_FIX_2026-07-01.md` | MiniMax unknown kind 修复 |
| `PARTITION_WRITE_FIX_FINAL_REPORT.md` | 分区写入修复最终报告 |
| `PROBLEM_ANALYSIS_AND_FIX.md` | 问题分析与修复 |
| `REQUEST_LOGS_FIX_REPORT_2026-07-02.md` | 请求日志修复 |
| `ROUTING_AUDIT_P0_FIXES_VERIFICATION.md` | 路由审计 P0 修复验证 |
| `SLOT_INFLIGHT_FIX_V3.2.2.md` | Slot Inflight 修复 v3.2.2 |
| `VERSION_DISPLAY_FIX_REPORT_2026-07-01.md` | 版本显示修复 |
| `VERSION_DISPLAY_SIMPLIFY_FIX.md` | 版本显示简化修复 |
| `VERSION_FIX_REPORT_2026-07-01.md` | 版本修复报告 |

### docs/reports/ — 分析与测试报告

| 文件 | 说明 |
|------|------|
| `ATTACHMENT_FEATURE_SUMMARY.md` | 附件功能总结 |
| `ATTACHMENTS_UI_IMPLEMENTATION_REPORT.md` | 附件UI实现报告 |
| `AUDIT_ROUND2_probe_retry_2026-06-29.md` | 第二轮审计探针重试 |
| `CONTENT_IDENTIFICATION_REPORT_V723.md` | v723 内容识别 |
| `FINAL_COMPLETE_REPORT_2026-07-01.md` | 最终完整报告 |
| `PARTITION_ANALYSIS_REPORT.md` | 分区分析报告 |
| `PARTITION_IMPLEMENTATION_SUMMARY.md` | 分区实现总结 |
| `ROUTING_AUDIT_FINAL_REPORT.md` | 路由审计最终报告 |
| `ROUTING_NO_CANDIDATE_INCIDENT_REPORT.md` | 无候选路由事件 |
| `STORAGE_MANAGEMENT_IMPLEMENTATION_REPORT.md` | 存储管理实现 |
| `TEST_EXECUTION_SUMMARY.md` | 测试执行总结 |
| `TEST_WEBSOCKET.md` | WebSocket 测试指南 |
| `TESTING_CHEATSHEET.txt` | 测试快捷参考 |
| `VERIFICATION_REPORT.md` | 验证报告 |

### docs/refactor/ — 重构文档

| 文件 | 说明 |
|------|------|
| `ROUTING_CORE_ARCHITECTURE.md` | 路由核心架构 |
| `STATE_MANAGER_IMPLEMENTATION.md` | StateManager 实现 |
| `SCRIPTS_REFACTOR.md` | 脚本整理说明 |
| `FINAL_SUMMARY.md` | 重构交付总结 |
| `PHASE1_TASK_CHECKLIST.md` | 阶段一任务清单 |
| `DEPLOYMENT_MIGRATION_GUIDE.md` | 部署迁移指南 |

## scripts/ — 脚本说明

> 所有脚本均需通过环境变量注入敏感信息（密码、API Key），不硬编码。

| 脚本 | 用途 | 依赖环境变量 |
|------|------|-------------|
| `deploy-71.sh` | 部署到 71 服务器 | `SSHPASS` |
| `deploy-71-data-bindmounts.sh` | 71 数据绑定挂载 | `LLM_GATEWAY_DB_PASSWORD`, `LLM_GATEWAY_SECRET_KEY` |
| `deploy-to-71.sh` | 通用 71 部署 | `SSHPASS` |
| `deploy-to-71-fpslot-fix.sh` | FPSlot 修复部署 | `PROJECT_ROOT`, `SSHPASS` |
| `deploy-fpslot-fix.sh` | FPSlot 修复脚本 | `SSHPASS` |
| `deploy_attachments_71.sh` | 附件功能部署 | `SSHPASS` |
| `auto_commit_watcher.sh` | 自动提交监控 | `API_KEY` |
| `test_71_complete.sh` | 71 完整测试 | `API_KEY`, `GATEWAY_URL` |
| `test_minimax_api_only.sh` | MiniMax API 测试 | `API_KEY`, `GATEWAY_URL` |
| `test_minimax_comprehensive.sh` | MiniMax 全面测试 | `API_KEY` |
| `test_local_routing.sh` | 本地路由测试 | `PGPASSWORD` |
| `test_local_concurrency.sh` | 本地并发测试 | `PGPASSWORD` |
| `archive-request-logs.sh` | 归档请求日志 | `DB_PASSWORD` |
| `delete-old-request-logs.sh` | 删除旧日志 | `DB_PASSWORD` |
| `analyze-request-logs-size.sh` | 分析日志大小 | `DB_PASSWORD` |
| `audit-partition-writes.sh` | 审计分区写入 | `DB_PASSWORD` |
| `audit_empty_response_fix.sh` | 审计空响应修复 | `PGPASSWORD` |
| `probe_credentials.sh` | 凭据探测 | `DB_PASSWORD` |

## 设计原则

1. **所有文档已脱敏**：生产密码、API Key、内部 IP 已替换为 `<placeholder>` 或环境变量引用
2. **文档版本化**：修复报告按日期命名（`YYYY-MM-DD`），部署报告按版本命名（`vX.Y.Z`）
3. **Git 提交说明**：所有敏感信息清理通过独立 commit 记录，便于审计
