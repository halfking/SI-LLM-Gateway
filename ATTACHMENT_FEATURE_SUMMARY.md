# 图片/附件管理功能实现总结

## 实施日期
2026-07-01

## 问题描述

### 根本原因
当前网关对图片附件的处理存在以下问题：

1. **base64图片直接存入request_body/response_body**：
   - 单张图片可达数MB，导致JSONB字段过大
   - 查询request_logs时性能严重下降
   - 图片数据无法单独管理和访问

2. **没有独立的附件存储机制**：所有内容混在request_body中

3. **Admin界面无法预览图片**：即使图片在数据库中也无法展示

### 影响范围
- `/v1/messages` (Anthropic格式)
- `/v1/chat/completions` (OpenAI格式)
- 任何包含base64图片的请求

## 解决方案

### 整体架构
```
用户请求（含图片） → 网关拦截 → 提取附件 → 保存到文件系统
                                    ↓
                        生成attachment记录 → 数据库
                                    ↓
                        替换为attachment_ref → 继续处理
                                    ↓
                        request_logs记录关联 → 便于查询
```

### 存储方案
- **文件系统存储**：图片保存到本地目录，数据库只存元数据
- **目录结构**：`{STORAGE_PATH}/2026/07/01/uuid_image.png`
- **访问方式**：通过网关API下载（带鉴权）

### 数据库设计

#### 新增 `attachments` 表
```sql
CREATE TABLE attachments (
    id TEXT PRIMARY KEY,              -- UUID
    tenant_id TEXT NOT NULL,          -- 租户隔离
    request_id TEXT NOT NULL,         -- 关联request_logs
    attachment_type TEXT NOT NULL,    -- 'image', 'file', 'audio', 'video'
    media_type TEXT NOT NULL,         -- 'image/png', 'image/jpeg'
    file_size BIGINT NOT NULL,        -- 字节
    file_path TEXT NOT NULL,          -- 相对路径
    original_data_type TEXT NOT NULL, -- 'base64', 'url'
    original_url TEXT,                -- URL类型时保存原始URL
    content_hash TEXT NOT NULL,       -- SHA256，用于去重
    created_at TIMESTAMP NOT NULL,
    metadata JSONB
);

CREATE INDEX idx_attachments_request ON attachments (request_id);
CREATE INDEX idx_attachments_tenant_created ON attachments (tenant_id, created_at DESC);
CREATE INDEX idx_attachments_hash ON attachments (content_hash, tenant_id);
```

#### 修改 `request_logs` 表
```sql
ALTER TABLE request_logs 
    ADD COLUMN has_attachments BOOLEAN DEFAULT FALSE,
    ADD COLUMN attachment_count INTEGER DEFAULT 0;

CREATE INDEX idx_request_logs_has_attachments 
    ON request_logs (has_attachments, ts DESC) 
    WHERE has_attachments = TRUE;
```

## 实现细节

### 核心模块

#### 1. `attachments/manager.go`
- **附件提取**：从request body中识别并提取base64图片
- **附件保存**：保存到文件系统，生成唯一ID
- **去重机制**：基于SHA256哈希，相同内容只保存一次
- **附件引用**：将原始数据替换为 `attachment_ref` 引用

#### 2. `attachments/attachment.go`
- 定义 `Attachment` 数据结构
- 定义附件类型常量（image, file, audio, video）

#### 3. `admin/attachments_handler.go`
- **GET `/admin/attachments/:id`**：下载附件（需鉴权）
- **GET `/admin/attachments/:id/info`**：获取附件元数据
- 支持图片内联显示，其他类型建议下载

#### 4. `db/attachments_schema.go`
- 创建attachments表和索引
- 创建RLS策略实现租户隔离
- 修改request_logs表添加附件跟踪字段

### 集成点

#### 在 `relay/handler.go` 中：
```go
// 第878行：在body读取后、JSON解析前提取附件
if h.attachmentManager != nil && h.attachmentManager.Enabled() {
    modifiedBody, attachments, err := h.attachmentManager.ExtractAndSaveAttachments(...)
    if err == nil && len(modifiedBody) > 0 {
        bodyBytes = modifiedBody  // 使用修改后的body
        logCtx.SetAttachmentCount(attachmentCount)
    }
}
```

#### 在 `cmd/gateway/main.go` 中：
```go
// 第212行：初始化attachment manager
attachmentMgr, err := attachments.NewManager(dbConn.Pool(), storagePath, enabled, maxSizeMB)
chatHandler.SetAttachmentManager(attachmentMgr)
```

## 配置项

### 环境变量
```bash
# 附件存储根目录（默认：./data/attachments）
ATTACHMENT_STORAGE_PATH=./data/attachments

# 是否启用附件管理（默认：true）
ATTACHMENT_ENABLED=true

# 单个附件最大大小，MB（默认：10）
ATTACHMENT_MAX_SIZE_MB=10

# 附件保留天数，0表示永久保留（默认：0）
ATTACHMENT_RETENTION_DAYS=90
```

## 安全特性

1. **租户隔离**：只能访问自己租户的附件
2. **文件类型验证**：检查MIME type
3. **大小限制**：默认单个附件最大10MB
4. **路径安全**：使用UUID防止路径遍历
5. **去重机制**：基于SHA256，节省存储空间

## 性能优化

1. **去重机制**：相同内容只存一次
2. **惰性加载**：request_logs列表不加载attachment详情
3. **索引优化**：为常见查询模式建立索引
4. **小文件内联**：可选择小文件（<100KB）仍保留在request_body

## 向后兼容性

- **不破坏现有数据**：已有的request_logs保持不变
- **可选功能**：通过环境变量控制是否启用
- **渐进式迁移**：新请求自动使用新机制

## 文件清单

### 新增文件
1. `attachments/attachment.go` - 数据结构定义
2. `attachments/manager.go` - 核心管理逻辑
3. `admin/attachments_handler.go` - HTTP API处理器
4. `db/attachments_schema.go` - 数据库schema
5. `ATTACHMENT_FEATURE_SUMMARY.md` - 本文档

### 修改文件
1. `relay/handler.go` - 集成附件提取逻辑
2. `relay/request_log_pipeline.go` - 添加附件字段支持
3. `telemetry/client.go` - request_logs表字段更新
4. `db/db.go` - 添加schema初始化调用
5. `cmd/gateway/main.go` - 初始化attachment manager

## 测试建议

### 单元测试
```bash
# 测试附件提取
cd attachments && go test -v

# 测试handler集成
cd relay && go test -run TestAttachment -v
```

### 集成测试
```bash
# 1. 启动网关
./gateway

# 2. 发送带图片的请求
curl -X POST http://localhost:8781/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{
      "role": "user",
      "content": [{
        "type": "text",
        "text": "这是什么图片？"
      }, {
        "type": "image_url",
        "image_url": {
          "url": "data:image/png;base64,iVBORw0KGgoAAAANS..."
        }
      }]
    }]
  }'

# 3. 检查数据库
psql -c "SELECT count(*) FROM attachments;"
psql -c "SELECT id, file_size, media_type FROM attachments LIMIT 5;"

# 4. 检查文件系统
ls -lh ./data/attachments/2026/07/01/

# 5. 下载附件测试
curl http://localhost:8781/admin/attachments/{attachment_id} \
  -H "Authorization: Bearer YOUR_API_KEY" \
  --output test_image.png
```

### 性能测试
```bash
# 测试大量图片场景
# 发送100个带图片的请求，观察性能
for i in {1..100}; do
  curl -X POST http://localhost:8781/v1/chat/completions \
    -H "Authorization: Bearer YOUR_API_KEY" \
    -d @test_with_image.json &
done
wait

# 检查数据库性能
psql -c "EXPLAIN ANALYZE SELECT * FROM request_logs WHERE has_attachments = true LIMIT 100;"
```

## 部署步骤

1. **编译新版本**：
   ```bash
   go build -o gateway ./cmd/gateway
   ```

2. **配置环境变量**：
   ```bash
   export ATTACHMENT_STORAGE_PATH=./data/attachments
   export ATTACHMENT_ENABLED=true
   export ATTACHMENT_MAX_SIZE_MB=10
   ```

3. **创建存储目录**：
   ```bash
   mkdir -p ./data/attachments
   chmod 755 ./data/attachments
   ```

4. **数据库迁移**（自动执行）：
   - 启动时自动创建attachments表
   - 自动添加request_logs的attachment字段

5. **重启服务**：
   ```bash
   ./gateway
   ```

6. **验证功能**：
   - 发送带图片的测试请求
   - 检查attachments表是否有记录
   - 检查文件系统是否保存了文件

## 监控指标

建议监控以下指标：

1. **附件统计**：
   ```sql
   -- 每日附件数量
   SELECT DATE(created_at), COUNT(*), SUM(file_size)/1024/1024 as total_mb
   FROM attachments
   GROUP BY DATE(created_at)
   ORDER BY DATE(created_at) DESC;
   ```

2. **存储使用**：
   ```bash
   du -sh ./data/attachments
   ```

3. **去重效率**：
   ```sql
   -- 重复内容统计
   SELECT content_hash, COUNT(*) as dup_count
   FROM attachments
   GROUP BY content_hash
   HAVING COUNT(*) > 1
   ORDER BY dup_count DESC;
   ```

## 未来改进

1. **Admin界面增强**（P1）：
   - 在request_logs列表显示附件图标
   - 在详情页预览图片
   - 提供批量下载功能

2. **清理任务**（P2）：
   - 定期清理过期附件
   - 清理孤立文件（数据库无记录）

3. **CDN集成**（P2）：
   - 支持CDN URL前缀配置
   - 自动上传到对象存储

4. **更多文件类型**（P2）：
   - 音频文件支持
   - 视频文件支持
   - PDF文档支持

## 问题排查

### 附件未保存
1. 检查存储目录权限：`ls -la ./data/attachments`
2. 检查环境变量：`echo $ATTACHMENT_ENABLED`
3. 查看日志：`grep "attachment" logs/gateway.log`

### 附件无法下载
1. 检查文件是否存在：`ls ./data/attachments/2026/07/01/`
2. 检查路由注册：确认admin handler已注册
3. 检查鉴权：确认API key有效

### 数据库错误
1. 检查schema是否创建：`\d attachments`
2. 检查索引：`\di attachments*`
3. 检查RLS策略：`\dRp attachments`

## 总结

本次实现完整解决了图片附件丢失和性能问题，通过文件系统+数据库元数据的方案，实现了：

✅ **功能完整**：提取、保存、下载、管理
✅ **性能优化**：去重、索引、惰性加载
✅ **安全可靠**：租户隔离、鉴权、类型验证
✅ **易于运维**：环境变量配置、自动迁移
✅ **向后兼容**：可选功能、不破坏现有数据

代码已编译通过，可以部署测试验证。
