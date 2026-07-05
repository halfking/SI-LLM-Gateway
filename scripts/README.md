# 脚本目录

本目录包含项目的所有管理脚本，已进行统一整理和优化。

## 🚀 核心脚本（推荐使用）

### 1. `deploy.sh` - 统一部署脚本
支持多目标、多模式的部署。

**使用示例：**
```bash
# 部署到71服务器 (二进制方式)
./scripts/deploy.sh --target=71 --mode=binary

# 部署到71服务器 (Docker方式)
./scripts/deploy.sh --target=71 --mode=docker

# 部署到184服务器 (K8s方式)
./scripts/deploy.sh --target=184 --mode=k8s --build-num=720

# 模拟运行（不实际部署）
./scripts/deploy.sh --target=71 --mode=binary --dry-run

# 查看帮助
./scripts/deploy.sh --help
```

**支持的选项：**
- `--target=71|184` - 部署目标服务器
- `--mode=binary|docker|k8s` - 部署模式
- `--build-num=NUM` - 编译号（K8s部署必需）
- `--version=VER` - 版本号
- `--skip-backup` - 跳过备份
- `--skip-test` - 跳过部署后测试
- `--dry-run` - 模拟运行

### 2. `test.sh` - 统一测试脚本
整合所有测试功能。

**使用示例：**
```bash
# 测试路由功能
./scripts/test.sh routing

# 测试routing-v2统计
./scripts/test.sh routing-v2

# 验证路由修复
./scripts/test.sh routing-fixes

# 运行所有测试
./scripts/test.sh all

# 查看帮助
./scripts/test.sh --help
```

**支持的测试类型：**
- `routing` - 路由功能测试
- `routing-v2` - routing-v2统计功能测试
- `routing-fixes` - 验证路由修复
- `all` - 运行所有测试

### 3. `diagnose.sh` - 统一诊断脚本
整合所有诊断和修复功能。

**使用示例：**
```bash
# 诊断路由问题
./scripts/diagnose.sh routing

# 诊断路由问题并自动修复
./scripts/diagnose.sh routing --auto-fix

# 诊断凭据问题
./scripts/diagnose.sh credential

# 诊断71服务器日志
./scripts/diagnose.sh logs-71

# 检查Redis状态
./scripts/diagnose.sh redis

# 完整修复验证
./scripts/diagnose.sh repair

# 运行所有诊断
./scripts/diagnose.sh all

# 查看帮助
./scripts/diagnose.sh --help
```

**支持的诊断类型：**
- `routing` - 路由问题诊断和自动修复
- `credential` - 凭据检查诊断
- `logs-71` - 71服务器日志诊断
- `redis` - Redis路由节点状态检查
- `repair` - 完整修复验证
- `all` - 运行所有诊断

### 4. `utils.sh` - 通用工具函数库
提供所有脚本共用的函数，不直接运行，由其他脚本通过 `source` 加载。

**主要功能：**
- 日志函数：`log_info`, `log_error`, `log_success`, `log_warn`, `log_step`
- 连接测试：`test_ssh_connection`, `test_db_connection`, `test_redis_connection`
- 服务管理：`check_service_status`, `wait_for_service`
- 备份函数：`backup_file`, `remote_backup_file`
- UI工具：`print_header`, `print_separator`, `confirm`

## 📂 其他脚本

本目录还包含其他特定功能的脚本，用于数据库维护、版本管理等特殊任务。

### 部署相关
- `deploy-71.sh` - 71服务器部署（使用 deploy-71 skill）
- `bump-version.sh` - 版本号管理
- `verify-deployment.sh` - 部署验证

### 测试相关
- `test_71_complete.sh` - 71服务器完整测试
- `test_local_routing.sh` - 本地路由测试
- `quick_test.sh` - 快速测试

### 数据库维护
- `cleanup-request-logs.sh` - 清理请求日志
- `archive-request-logs.sh` - 归档请求日志
- `delete-old-request-logs.sh` - 删除旧日志

### Git 相关
- `pre-commit-check.sh` - 提交前检查
- `pre-commit-install.sh` - 安装 Git hooks

## 🗑️ 已弃用脚本

旧脚本已移动到 `deprecated/` 目录，仅作为历史参考保留。详见 `deprecated/README.md`。

## 📖 完整文档

查看项目根目录的 `docs/refactor/SCRIPTS_REFACTOR.md` 了解完整的脚本整理说明和迁移指南。

## 🎯 最佳实践

1. **优先使用统一脚本**：`deploy.sh`, `test.sh`, `diagnose.sh`
2. **查看帮助**：所有统一脚本都支持 `--help` 参数
3. **测试先行**：生产部署前先用 `--dry-run` 模拟
4. **保持更新**：旧脚本已停止维护，请迁移到新脚本

## 🤝 贡献指南

如需添加新功能：
1. 优先考虑扩展统一脚本
2. 新增通用函数添加到 `utils.sh`
3. 保持一致的代码风格和参数格式
4. 添加 `--help` 帮助信息
