# 已弃用的脚本

本目录包含已被新的统一脚本替代的旧脚本，仅作为历史参考保留。共 **50+ 个脚本**。

**请使用新的统一脚本：**
- `../deploy.sh` - 统一部署脚本
- `../test.sh` - 统一测试脚本
- `../diagnose.sh` - 统一诊断脚本
- `../utils.sh` - 通用工具函数库

## 📋 脚本分类

### 第一批迁移（根目录整理）

#### 部署类 → `../deploy.sh`
- `deploy_to_71_final.sh` → `../deploy.sh --target=71 --mode=binary`
- `deploy_to_71_docker.sh` → `../deploy.sh --target=71 --mode=docker`
- `deploy_new_version.sh` → `../deploy.sh --target=71 --mode=binary`
- `deploy_v3.sh`, `deploy_v4.sh`, `deploy-now.sh`, `deploy_docker_image.sh`

#### 测试类 → `../test.sh`
- `test_routing.sh` → `../test.sh routing`
- `test_routing_v2_local.sh` → `../test.sh routing-v2`
- `verify_routing_fixes.sh` → `../test.sh routing-fixes`

#### 诊断类 → `../diagnose.sh`
- `diagnose_and_fix.sh` → `../diagnose.sh routing --auto-fix`
- `diagnose_credential_check.sh` → `../diagnose.sh credential`
- `diag_71_logs.sh` → `../diagnose.sh logs-71`
- `check_redis_route_node.sh` → `../diagnose.sh redis`
- `verify_repair.sh` → `../diagnose.sh repair`

### 第二批迁移（scripts/ 目录整理）

#### 特定修复部署脚本（已完成的一次性修复）
- `deploy_adapter_to_71.sh` - 适配器部署
- `deploy_attachments_71.sh` - 附件部署
- `deploy_fix_to_71.sh` - 通用修复部署
- `deploy_request_logs_unique_id.sh` - unique_id 修复
- `deploy_routing_fix.sh` - 路由修复
- `deploy-fpslot-fix.sh` - fpslot 修复
- `deploy-session-fix.sh` - session 修复
- `deploy-to-71-fpslot-fix.sh` - fpslot 修复（重复）
- `deploy-to-71.sh` - 71部署（重复）
- `deploy-v316-circuit-fix.sh` - v3.16 circuit 修复

#### 特定场景测试脚本
- `test_71_routing.sh` - 71路由测试
- `test_analytics_fix.sh` - 分析修复测试
- `test_minimax_api_only.sh` - MiniMax API 测试
- `test_minimax_comprehensive.sh` - MiniMax 综合测试
- `test_minimax_routing.sh` - MiniMax 路由测试
- `test_routing_fix.sh` - 路由修复测试
- `test_version_api.sh` - 版本 API 测试
- `test-sliding-window.sh` - 滑动窗口测试

#### 特定问题诊断脚本
- `diagnose_and_fix_credentials.sh` - 凭据诊断
- `diagnose_nvidia_nim_empty_response.sh` - Nvidia NIM 问题
- `diagnose_request_logs_71.sh` - 请求日志诊断
- `diagnose_routing_issue.sh` - 路由问题诊断
- `diagnose-fpslot-issue.sh` - fpslot 问题诊断

#### 数据修复脚本（一次性）
- `fix_71_routing_complete.sh` - 完整路由修复
- `fix_credentials_sequence.sh` - 凭据序列修复

#### 验证脚本（特定版本/功能）
- `verify_attachments.sh` - 附件验证
- `verify_partition_implementation.sh` - 分区实现验证
- `verify_slot_inflight_fix.sh` - slot inflight 修复验证
- `verify_version_display.sh` - 版本显示验证
- `verify-deployment.sh` - 部署验证
- `verify-v321-circuit-fix.sh` - v3.21 circuit 修复验证

#### 审计脚本（特定问题）
- `audit_empty_response_fix.sh` - 空响应审计
- `audit-partition-writes.sh` - 分区写入审计

#### 其他工具脚本
- `probe_credentials.sh` - 凭据探测
- `auto_commit_watcher.sh` - 自动提交监控

## 📊 统计信息

- **总计**: 50+ 个已弃用脚本
- **第一批**: 15 个（根目录清理）
- **第二批**: 35+ 个（scripts/ 二次整理）
- **部署类**: 17 个
- **测试类**: 11 个
- **诊断类**: 6 个
- **修复类**: 2 个
- **验证类**: 6 个
- **审计类**: 2 个
- **其他**: 6+ 个

## ⚠️ 重要提示

1. **停止维护**: 所有脚本已停止维护，不保证功能正常
2. **快速迁移**: 请尽快迁移到新的统一脚本
3. **问题反馈**: 如发现新脚本有问题，请反馈并修复新脚本，而非使用旧脚本
4. **未来删除**: 本目录中的脚本可能在未来版本中被完全删除
5. **历史参考**: 仅作为历史实现参考，不建议在生产环境使用

## 🔄 迁移建议

如果您需要旧脚本的特定功能：
1. 查看新的统一脚本是否已支持
2. 如未支持，考虑扩展统一脚本
3. 将功能集成到核心脚本，而非继续使用旧脚本

## 📖 详细文档

- 完整重构说明：`../../SCRIPTS_REFACTOR.md`
- 脚本使用指南：`../README.md`
