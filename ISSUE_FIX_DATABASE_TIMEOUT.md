# 问题修复总结 - 数据库迁移超时导致 API 404

## 问题描述

部署 v2.3.0-0a5a1e74-715 后，所有 API 端点返回 404 错误，但静态文件和健康检查正常。

## 根本原因分析

### 问题现象
- 所有 `/api/*` 路径返回 404
- 静态文件 (`/assets/*`, `/favicon.svg`) 和根路径正常（200）
- 日志显示：`postgres disabled, error: timeout: context deadline exceeded`

### 根本原因
1. **数据库迁移超时**：启动时数据库连接成功，但在执行 schema 迁移时超时
   - 初始连接：20:12:41.606 - postgres connected ✓
   - 1分钟后：20:13:41.610 - postgres disabled (超时) ✗

2. **大表导致索引创建慢**：
   - `request_logs_2026_06` 表有 **2.6GB** 数据
   - 使用 **heap** 存储（普通行存储），而不是 columnar（列存储）
   - 在 `ensureRequestLogSchema()` 中创建多个索引时超过 60 秒超时

3. **数据库禁用导致 API 路由未注册**：
   - 数据库被禁用后，路由执行器被禁用
   - API 认证被禁用
   - 所有依赖数据库的 `/api/*` 端点未注册

## 解决方案

### 代码修改
**文件**: `db/db.go` 第 52 行

```go
// 修改前
migCtx, migCancel := context.WithTimeout(ctx, 60*time.Second)

// 修改后
migCtx, migCancel := context.WithTimeout(ctx, 300*time.Second)
```

**说明**: 将数据库迁移超时从 60 秒增加到 300 秒（5 分钟），以处理大表的索引创建操作。

### 验证结果

**修复后的启动日志**：
```
{"time":"2026-06-29T20:40:28.672Z","level":"INFO","msg":"gateway starting"}
{"time":"2026-06-29T20:40:28.678Z","level":"INFO","msg":"postgres connected"}
[约 3 分钟后迁移完成]
{"time":"2026-06-29T20:43:26.239Z","level":"INFO","msg":"autoroute.Index.Refresh: query completed","total_candidates":735}
```

**API 验证**：
- ✅ `/healthz` - 返回 200，包含版本信息
- ✅ `/v1/models` - 返回 337 个模型列表
- ✅ `/api/system/version` - 返回认证错误（正常，说明路由已注册）
- ✅ 自动路由系统正常工作

## 性能数据

| 表名 | 大小 | 存储类型 | 索引创建耗时（估计） |
|------|------|----------|---------------------|
| request_logs_2026_06 | 2.6 GB | heap | ~120-180 秒 |
| request_logs_archive_2026_06 | 29 MB | columnar | <5 秒 |

## 建议改进

### 短期
- [x] 增加迁移超时到 300 秒（已完成）

### 长期
1. **使用列存储**：将活跃的 `request_logs_YYYY_MM` 表也使用 columnar 存储
2. **延迟索引创建**：在后台异步创建索引，不阻塞启动
3. **分离迁移**：将大表的索引创建移到独立的维护窗口
4. **添加进度日志**：在迁移过程中输出进度信息

## 部署信息

- **修复版本**: v2.3.0-0a5a1e74-715 (fixed)
- **部署时间**: 2026-06-30 04:40
- **服务器**: 71 ([PROD_SERVER_IP_71])
- **验证状态**: ✅ 完全正常

## 监控要点

1. **启动时间**：正常启动时间应在 3-5 分钟内
2. **数据库连接**：检查 `postgres connected` 后是否有 `postgres disabled`
3. **API 响应**：所有 `/api/*` 端点应正常响应（200 或认证错误）
4. **表大小增长**：监控 `request_logs_YYYY_MM` 表的大小，考虑归档策略

## 相关文件

- 修改文件：`db/db.go`
- 部署文档：`DEPLOYMENT_SUMMARY_v2.3.0.md`
- 测试脚本：`scripts/test_71_routing.sh`

---

**状态**: ✅ 问题已解决并验证
**修复时间**: 2026-06-30 04:40
**验证人**: ZCode AI Assistant
