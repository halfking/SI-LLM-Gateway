# 数据生命周期管理 - 存储管理功能实施报告

**实施日期**: 2026-07-02  
**版本**: 2.3.3 (build #718)  
**功能**: 存储管理 + 日志文件管理  

---

## ✅ 实施总结

成功在"数据生命周期管理"页面中集成了完整的存储管理功能，包括：
1. ✅ 磁盘空间监控
2. ✅ 数据库占用统计
3. ✅ 附件存储管理和清理
4. ✅ 日志文件统计和清理
5. ✅ 生命周期配置管理

---

## 🎯 功能特性

### 一、存储统计概览

#### 1. 磁盘空间监控
- **总容量/已用/可用空间** 显示
- **使用率百分比** 和进度条
- **挂载点路径** 显示
- 自动获取系统磁盘信息（使用 syscall.Statfs）

#### 2. 数据库占用统计
- **总数据库大小**
- **请求日志表大小** (request_logs)
- **附件元数据表大小** (attachments)
- **其他表大小** (计算得出)
- 使用 PostgreSQL 的 `pg_total_relation_size()` 函数

#### 3. 附件存储统计
- **总文件数和总大小**
- **按媒体类型分组** 统计（image/png, image/jpeg等）
- **孤立文件检测** (文件存在但数据库无记录)
- **存储路径** 显示

#### 4. 日志文件统计 (新增)
- **日志目录** 和**总文件数**
- **总占用空间**
- **活动日志文件** 状态
- **轮转日志列表** (最多显示10个)
- **轮转配置** 显示（大小限制、保留文件数、保留天数、压缩设置）
- 自动识别压缩文件（.gz）

### 二、生命周期配置

#### 1. 数据保留策略
- **数据保留期限**: 7-365天可配置
- **附件存储路径**: 显示当前路径
- **最大附件大小**: 1-100 MB可配置
- **自动清理开关**: UI已实现（后端功能待开发）

#### 2. 日志轮转配置
- **单文件大小限制**: 从环境变量读取（默认100MB）
- **保留文件数**: 默认10个
- **保留天数**: 默认30天
- **自动压缩**: 默认开启
- 注意：配置修改需要重启服务生效

### 三、清理功能

#### 1. 附件清理
**清理模式**:
- **清理过期附件**: 删除超过N天的附件（数据库记录+文件）
- **清理孤立文件**: 删除存储目录中无数据库记录的文件

**安全措施**:
- ✅ 预览功能（dry_run模式）
- ✅ 显示影响文件数和释放空间
- ✅ 确认对话框
- ✅ 最小保留期限限制（7天）
- ✅ 分批处理支持
- ✅ 事务保护

#### 2. 日志清理 (新增)
**清理选项**:
- **清理旧日志**: 删除超过N天的轮转日志
- **仅压缩文件**: 选项，只删除已压缩的日志文件

**特点**:
- ✅ 不会删除活动日志文件
- ✅ 预览功能
- ✅ 确认对话框
- ✅ 最小保留期限限制（7天）
- ✅ 自动识别日志文件格式

---

## 📊 UI/UX 设计

### 页面布局

```
┌─────────────────────────────────────────────────────┐
│ 💾 存储管理                                          │
├─────────────────────────────────────────────────────┤
│ [磁盘空间] [数据库占用] [附件存储]                    │
│ ━━━━━━━━━  ━━━━━━━━━  ━━━━━━━                      │
│ 50% 使用    10 GB       5 GB (1234个)               │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ⚙️ 生命周期配置                                      │
├─────────────────────────────────────────────────────┤
│ 数据保留期限: [90] 天                                │
│ 附件存储路径: /opt/llm-gateway-go/data/attachments │
│ 最大附件大小: [10] MB                               │
│ 自动清理: [⚪ 关]                                    │
│                                      [保存配置]      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ 🗑️ 附件清理                                         │
├─────────────────────────────────────────────────────┤
│ ○ 清理过期附件 (保留最近 [90] 天)                   │
│ ○ 清理孤立文件                                      │
│                                                      │
│ [预览清理] [执行清理]                                │
│                                                      │
│ 结果: 影响文件 123 个，释放空间 1 GB                │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ 📁 附件存储详情                                      │
├─────────────────────────────────────────────────────┤
│ image/png    [████████░░] 800 个 (4 GB) 80.0%      │
│ image/jpeg   [████░░░░░░] 400 个 (1 GB) 20.0%      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ 📋 日志文件管理                                      │
├─────────────────────────────────────────────────────┤
│ 日志目录: ./logs                                    │
│ 总文件数: 11 个                                     │
│ 总占用空间: 500 MB                                  │
│                                                      │
│ 轮转配置:                                           │
│ 单文件大小限制: 100 MB | 保留文件数: 10 个          │
│ 保留天数: 30 天 | 自动压缩: 是                      │
│                                                      │
│ 日志文件:                                           │
│ 📝 gateway.log [活动] - 45 MB                       │
│ 📦 gateway-2026-07-01.log.gz [已压缩] - 5 MB       │
│ 📦 gateway-2026-06-30.log.gz [已压缩] - 5 MB       │
│ ...                                                  │
│                                                      │
│ 日志清理:                                           │
│ ○ 清理旧日志 (删除 [30] 天前) ☑ 仅压缩文件         │
│ [预览清理] [执行清理]                                │
└─────────────────────────────────────────────────────┘
```

### 交互特点

1. **实时加载**: 页面加载时自动获取所有统计信息
2. **预览先行**: 所有清理操作都提供预览功能
3. **确认对话框**: 执行清理前弹出确认
4. **结果反馈**: 清理完成后显示详细结果
5. **自动刷新**: 清理后自动重新加载统计数据
6. **视觉反馈**: 
   - 活动日志文件：蓝色边框高亮
   - 压缩文件：绿色徽章标记
   - 警告信息：黄色警告框
   - 进度条：直观显示占用比例

---

## 🔧 技术实现

### 后端架构

#### 1. 新增文件

**admin/storage_stats.go** (~380 行)
- `handleStorageStats()` - 存储统计API入口
- `getDiskStats()` - 磁盘空间统计
- `getDatabaseStats()` - 数据库统计
- `getAttachmentStorageStats()` - 附件存储统计
- `getLogFilesStorageStats()` - 日志文件统计 (新增)
- `countOrphanedAttachments()` - 孤立附件检测
- `getLifecycleConfig()` - 配置获取

**admin/attachments_cleanup.go** (~230 行)
- `handleCleanupAttachments()` - 附件清理API
- `cleanupOldAttachments()` - 清理过期附件
- `cleanupOrphanedAttachments()` - 清理孤立文件
- `handleUpdateLifecycleConfig()` - 配置更新

**admin/logs_cleanup.go** (~220 行) (新增)
- `handleCleanupLogs()` - 日志清理API
- `cleanupOldLogFiles()` - 清理旧日志文件
- `handleUpdateLogConfig()` - 日志配置更新

#### 2. API端点

| 方法 | 端点 | 功能 |
|------|------|------|
| GET | `/api/admin/data-lifecycle/storage-stats` | 获取存储统计 |
| POST | `/api/admin/data-lifecycle/cleanup-attachments` | 清理附件 |
| POST | `/api/admin/data-lifecycle/cleanup-logs` | 清理日志 (新增) |
| POST | `/api/admin/data-lifecycle/config` | 更新生命周期配置 |
| POST | `/api/admin/data-lifecycle/log-config` | 更新日志配置 (新增) |

#### 3. 数据结构

**核心类型**:
```go
type StorageStatsResponse struct {
    Disk              *DiskStats
    Database          *DatabaseStats
    AttachmentsStorage *AttachmentStorageStats
    LogFilesStorage   *LogFilesStorageStats    // 新增
    LifecycleConfig   *LifecycleConfig
}

type LogFilesStorageStats struct {
    LogDirectory   string
    TotalFiles     int
    TotalSizeBytes int64
    TotalSizeHuman string
    ActiveLogFile  *LogFileInfo
    RotatedFiles   []LogFileInfo
    Config         *LogConfig
}

type LogFileInfo struct {
    Name         string
    Path         string
    SizeBytes    int64
    SizeHuman    string
    ModifiedAt   time.Time
    IsCompressed bool
    IsActive     bool
}
```

### 前端架构

#### 1. 修改文件

**web/src/api/tuning.ts**
- 新增 `LogFileInfo`, `LogConfig`, `LogFilesStorageStats` 类型
- 新增 `cleanupLogs()`, `updateLogConfig()` 函数
- 更新 `StorageStatsResponse` 类型

**web/src/views/DataLifecycleView.vue** (+200 行)
- 新增日志文件统计卡片
- 新增日志文件列表显示
- 新增日志清理功能UI
- 新增相关状态变量和函数
- 新增CSS样式（~150行）

#### 2. 状态管理

```typescript
// 附件清理
const cleanupType = ref<'old' | 'orphaned'>('old')
const cleanupOlderThanDays = ref(90)
const cleaningAttachments = ref(false)
const cleanupResult = ref<CleanupAttachmentsResponse | null>(null)

// 日志清理 (新增)
const logCleanupType = ref<'old'>('old')
const logCleanupOlderThanDays = ref(30)
const logCleanupCompressedOnly = ref(false)
const cleaningLogs = ref(false)
const logCleanupResult = ref<CleanupLogsResponse | null>(null)
```

---

## 🔍 实施细节

### 1. 磁盘空间获取

使用 `syscall.Statfs` 获取文件系统统计信息：

```go
func getDiskStats(path string) (*DiskStats, error) {
    var stat syscall.Statfs_t
    if err := syscall.Statfs(path, &stat); err != nil {
        return nil, err
    }
    
    totalBytes := stat.Blocks * uint64(stat.Bsize)
    availableBytes := stat.Bavail * uint64(stat.Bsize)
    usedBytes := totalBytes - availableBytes
    usagePercent := float64(usedBytes) / float64(totalBytes) * 100
    
    return &DiskStats{...}, nil
}
```

### 2. 日志文件识别

智能识别日志文件格式：
- **活动日志**: `gateway.log`
- **轮转日志**: `gateway-YYYY-MM-DD.log`
- **压缩日志**: `gateway-YYYY-MM-DD.log.gz`

```go
// 检查文件名模式
if name == baseName {
    isActive = true
} else if strings.HasPrefix(name, strings.TrimSuffix(baseName, ".log")) {
    if strings.HasSuffix(name, ".log.gz") || strings.HasSuffix(name, ".log") {
        isLogFile = true
        isCompressed = strings.HasSuffix(name, ".gz")
    }
}
```

### 3. 安全清理机制

**预览模式 (dry_run)**:
```go
if dryRun {
    resp.AffectedFiles = len(toDelete)
    resp.EstimatedFreedBytes = totalSize
    return nil // 不执行实际删除
}
```

**事务保护** (附件清理):
```go
tx, err := h.db.Begin(ctx)
if err != nil {
    return err
}
defer tx.Rollback(ctx)

// ... 执行清理 ...

if err := tx.Commit(ctx); err != nil {
    return err
}
```

### 4. 孤立文件检测

```go
func (h *Handler) countOrphanedAttachments(ctx context.Context, storagePath string) (int, error) {
    // 1. 从数据库获取所有附件ID
    rows, err := h.db.Query(ctx, `SELECT id FROM attachments`)
    // ...
    dbIDs := make(map[string]bool)
    
    // 2. 扫描存储目录
    filepath.WalkDir(storagePath, func(path string, d fs.DirEntry, err error) error {
        // 3. 检查文件是否在数据库中
        if !dbIDs[filename] {
            orphanedCount++
        }
    })
}
```

---

## 📈 行业最佳实践

### 1. 数据分层管理

| 数据层 | 时间范围 | 策略 |
|--------|----------|------|
| 热数据 | 0-7天 | 高频访问，保留在主存储 |
| 温数据 | 7-30天 | 中频访问，可考虑压缩 |
| 冷数据 | 30-90天 | 低频访问，可归档 |
| 过期数据 | >90天 | 待清理或长期归档 |

### 2. 日志轮转策略

**推荐配置**:
- **单文件大小**: 50-100 MB
- **保留文件数**: 7-14 个
- **保留天数**: 30-90 天
- **自动压缩**: 开启（节省70-90%空间）

### 3. 清理策略

**安全措施**:
- ✅ 始终提供预览功能
- ✅ 设置最小保留期限（7天）
- ✅ 分批处理大规模清理
- ✅ 保留审计日志
- ✅ 支持回滚（如果可能）

**执行时机**:
- 建议在业务低峰期执行（如凌晨2-4点）
- 使用定时任务自动化
- 监控磁盘空间，达到阈值时告警

### 4. 存储优化

**数据库**:
- 定期 VACUUM（PostgreSQL）
- 归档旧数据到冷存储
- 压缩 JSON/TEXT 字段

**文件系统**:
- 压缩旧文件（gzip）
- 使用对象存储（S3/OSS）存储冷数据
- 实施自动归档策略

---

## ⚠️ 注意事项和限制

### 1. 当前限制

**配置持久化**:
- ⚠️ 生命周期配置目前不持久化到数据库
- ⚠️ 配置更改重启后恢复默认值
- ⚠️ 建议通过环境变量设置

**日志配置**:
- ⚠️ 日志轮转配置需要重启服务生效
- ⚠️ 配置通过环境变量管理，UI只做展示和提醒

**自动清理**:
- ⚠️ 自动清理开关已实现UI，后端定时任务待开发
- ⚠️ 当前只支持手动触发清理

### 2. 平台兼容性

**磁盘统计**:
- ✅ Linux: 完全支持
- ⚠️ macOS: 支持，但文件系统类型信息有限
- ❌ Windows: 需要条件编译支持

### 3. 性能考虑

**大规模清理**:
- 超过1万个文件时显示警告
- 建议分批执行
- 可能短暂锁表（数据库清理）

**目录扫描**:
- 大目录扫描可能耗时
- 设置30秒超时限制
- 扫描失败不影响其他统计

---

## 🚀 部署指南

### 1. 环境变量配置

**附件存储**:
```bash
export ATTACHMENT_STORAGE_PATH="/opt/llm-gateway-go/data/attachments"
```

**日志轮转**:
```bash
export LLM_GATEWAY_LOG_FILE="./logs/gateway.log"
export LLM_GATEWAY_LOG_MAX_SIZE_MB=100
export LLM_GATEWAY_LOG_MAX_BACKUPS=10
export LLM_GATEWAY_LOG_MAX_AGE_DAYS=30
export LLM_GATEWAY_LOG_COMPRESS=true
```

### 2. 目录权限

确保服务进程有权限访问：
```bash
mkdir -p /opt/llm-gateway-go/data/attachments
mkdir -p /opt/llm-gateway-go/logs
chown -R llm-gateway:llm-gateway /opt/llm-gateway-go
```

### 3. 验证步骤

1. **登录管理后台**
2. **进入"数据生命周期"页面**
3. **检查存储统计**:
   - ✅ 磁盘空间显示正常
   - ✅ 数据库占用显示正常
   - ✅ 附件存储有数据（如果有附件）
   - ✅ 日志文件列表显示正常
4. **测试清理功能**:
   - ✅ 预览附件清理
   - ✅ 预览日志清理
   - ✅ 执行一次小规模清理验证

---

## 📊 功能对比

| 功能 | 之前 | 现在 |
|------|------|------|
| 磁盘监控 | ❌ 无 | ✅ 实时显示 |
| 数据库统计 | 部分 | ✅ 详细统计 |
| 附件管理 | ❌ 无 | ✅ 完整管理 |
| 附件清理 | ❌ 无 | ✅ 预览+执行 |
| 日志统计 | ❌ 无 | ✅ 完整统计 |
| 日志清理 | ❌ 手动删除 | ✅ UI化清理 |
| 配置管理 | 环境变量 | ✅ UI展示 |
| 预览功能 | ❌ 无 | ✅ 全面预览 |

---

## 🎓 关键技术点

### 1. pgx数据库驱动使用

正确的API调用方式：
```go
// ❌ 错误（database/sql风格）
h.db.QueryContext(ctx, ...)
h.db.QueryRowContext(ctx, ...)

// ✅ 正确（pgx风格）
h.db.Query(ctx, ...)
h.db.QueryRow(ctx, ...)
```

事务处理：
```go
// ✅ 正确
tx, err := h.db.Begin(ctx)
defer tx.Rollback(ctx)  // 需要传入context
err = tx.Commit(ctx)    // 需要传入context
```

### 2. 文件系统操作

**目录遍历**:
```go
filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
    if err != nil || d.IsDir() {
        return nil
    }
    // 处理文件
    return nil
})
```

**安全删除**:
```go
if err := os.Remove(path); err != nil {
    if !os.IsNotExist(err) {
        // 文件不存在不算错误
        slog.Warn("delete failed", "path", path, "error", err)
    }
}
```

### 3. Vue 3组合式API

**响应式引用**:
```typescript
const storageStats = ref<StorageStatsResponse | null>(null)
const loading = ref(false)
```

**异步操作**:
```typescript
async function loadStorageStats() {
  loading.value = true
  try {
    const data = await getStorageStats()
    storageStats.value = data
  } catch (error) {
    console.error('Failed:', error)
  } finally {
    loading.value = false
  }
}
```

---

## 📝 代码统计

### 后端
- **新增文件**: 3个
- **修改文件**: 2个
- **新增代码**: ~830行
- **新增API端点**: 4个

### 前端
- **修改文件**: 2个
- **新增代码**: ~350行
- **新增UI组件**: 8个区块

### 总计
- **总代码量**: ~1180行
- **编译后大小**: 
  - 后端: 43 MB (Linux binary)
  - 前端: 1.1 MB (JS bundle)

---

## 🎉 项目完成度

### 已完成 (10/12)
1. ✅ 创建后端存储统计API
2. ✅ 扩展data_lifecycle.go添加新端点
3. ✅ 实现附件清理API
4. ✅ 前端API类型定义
5. ✅ 扩展DataLifecycleView添加存储管理
6. ✅ 实现存储统计卡片UI
7. ✅ 实现配置管理表单
8. ✅ 实现清理功能UI
9. ✅ 测试和验证
10. ✅ 实现日志文件统计和管理

### 待完成 (1/12)
11. ⏳ 创建storage settings定义（可选，当前通过环境变量管理）

### 可选增强功能
- [ ] 归档到对象存储（S3/OSS）
- [ ] 数据压缩功能
- [ ] 定时任务集成
- [ ] 存储空间告警
- [ ] 数据导出功能
- [ ] 配置持久化到数据库

---

## 🔗 相关文档

1. **DEPLOYMENT_STANDARD.md** - 部署规范
2. **ATTACHMENTS_UI_IMPLEMENTATION_REPORT.md** - 附件UI实施报告
3. **observability/rotate/rotate.go** - 日志轮转实现
4. **admin/data_lifecycle.go** - 原有数据生命周期API

---

## 🎯 下一步建议

### 短期（1周内）
1. 在71服务器部署验证
2. 监控磁盘空间使用情况
3. 收集用户反馈

### 中期（2-4周）
1. 实现配置持久化到数据库
2. 开发自动清理定时任务
3. 添加存储空间告警功能

### 长期（1-3个月）
1. 集成对象存储支持
2. 实现数据归档功能
3. 开发数据压缩功能
4. 添加详细的操作审计日志

---

**报告生成**: 2026-07-02 00:30  
**报告人**: Kiro AI  
**版本**: 2.3.3-f689c1a5-20260701-718
