# 数据库维护脚本

本目录包含数据库维护相关脚本，主要用于日志清理、归档、回填等运维任务。

## 📋 脚本说明

### 日志管理
- `analyze-request-logs-size.sh` - 分析请求日志大小
- `delete-old-request-logs.sh` - 删除旧的请求日志
- `install-cleanup-cron.sh` - 安装日志清理定时任务

### 数据维护
- `backfill_request_logs_provider_model.sh` - 回填请求日志的 provider/model 字段
- `update-db-fpslot-limit.sh` - 更新数据库 fpslot 限制
- `rollback_request_logs_unique_id.sh` - 回滚请求日志 unique_id 字段

## 🚀 使用方法

```bash
# 分析日志大小
./scripts/maintenance/analyze-request-logs-size.sh

# 删除旧日志（保留最近30天）
./scripts/maintenance/delete-old-request-logs.sh

# 安装定时清理任务
./scripts/maintenance/install-cleanup-cron.sh

# 回填数据
./scripts/maintenance/backfill_request_logs_provider_model.sh
```

## ⚠️ 注意事项

1. **生产环境使用前请备份数据库**
2. 删除和回填操作不可逆，请谨慎执行
3. 建议在低峰期执行维护任务
4. 定时任务会自动运行，注意监控执行情况

## 📖 相关文档

- 主脚本目录：`../README.md`
- 数据库清理策略：查看项目文档
