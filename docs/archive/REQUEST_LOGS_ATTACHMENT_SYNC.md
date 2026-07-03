# request-logs 附件展示 — 功能与特性总结

> **同步来源**: `github` 分支 `76257380` 之后的状态(2026-07-02)
> **目的**: 让其他分支/会话能快速理解并复刻 `llm.kxpms.cn/request-logs` 的列表附件列 + 详情附件 Tab + 大图预览的实现
> **前置文档**: `ATTACHMENT_FEATURE_SUMMARY.md`(后端存储), `ATTACHMENTS_UI_IMPLEMENTATION_REPORT.md`(初版 UI), `REQUEST_LOGS_FIX_REPORT_2026-07-02.md`(本轮修复)

---

## 1. 系统全景

```
用户请求(含 base64 图片)
        │
        ▼
  relay/handler.go          ← 拦截,提取附件,替换为 attachment_ref
        │
        ├─► attachments.Manager ─► 文件系统 ./data/attachments/2026/07/01/<uuid>.png
        │                         + attachments 表(id, hash, path, …)
        │
        └─► telemetry ─► request_logs 表(带 has_attachments / attachment_count 字段)
                                  │
Admin 请求 /v1/messages ──────────┘
                                  │
                                  ▼
Admin 前端 /request-logs
   ├─ 列表行 📎 N 徽标
   └─ 详情抽屉
         ├─ 「📎 附件 (N)」Tab ─► GET /api/admin/attachments?request_id=…
         │                          后端为每条记录附上 HMAC 签名 download_url
         │                          前端 <img src=download_url> 80×80 缩略图
         │                          点击缩略图 → 全屏 lightbox
         └─ 其他 Tab(request / outbound / response)
```

---

## 2. 数据层

### 2.1 附件表 `attachments`

```sql
CREATE TABLE attachments (
    id              TEXT PRIMARY KEY,           -- UUID
    tenant_id       TEXT NOT NULL,             -- 租户隔离
    request_id      TEXT NOT NULL,             -- 关联 request_logs
    attachment_type TEXT NOT NULL,             -- 'image' | 'file' | 'audio' | 'video'
    media_type      TEXT NOT NULL,             -- 'image/png', 'image/jpeg'
    file_size       BIGINT NOT NULL,
    file_path       TEXT NOT NULL,             -- 相对路径
    original_data_type TEXT NOT NULL,          -- 'base64' | 'url'
    original_url    TEXT,                      -- URL 类型时
    content_hash    TEXT NOT NULL,             -- SHA256, 用于去重
    created_at      TIMESTAMP NOT NULL,
    metadata        JSONB
);
CREATE INDEX idx_attachments_request            ON attachments (request_id);
CREATE INDEX idx_attachments_tenant_created    ON attachments (tenant_id, created_at DESC);
CREATE INDEX idx_attachments_hash              ON attachments (content_hash, tenant_id);
```

`Attachment` 结构体(Go)见 `attachments/attachment.go`,**额外字段** `DownloadURL string` 不入库,仅在 list 接口返回时由后端注入签名 URL。

### 2.2 `request_logs` 增量字段

```sql
ALTER TABLE request_logs
    ADD COLUMN has_attachments BOOLEAN DEFAULT FALSE,
    ADD COLUMN attachment_count INTEGER DEFAULT 0;

CREATE INDEX idx_request_logs_has_attachments
    ON request_logs (has_attachments, ts DESC)
    WHERE has_attachments = TRUE;
```

### 2.3 关键不变量

- `has_attachments=true` 时 `attachment_count > 0`(列表行 📎 徽标据此展示)
- 列表查询不返回附件详情(惰性加载),只在打开详情抽屉时拉一次
- 删除 `request_logs` 时必须同步删附件文件 + 行(cron 任务 `attachments_cleanup.go`)

---

## 3. 后端 API

### 3.1 端点清单

| 方法 | 路径 | 鉴权 | 返回 |
|------|------|------|------|
| `GET` | `/api/admin/attachments?request_id={rid}` | Admin Bearer | `Attachment[]`, 每条带 `download_url` |
| `GET` | `/api/admin/attachments/{id}` | Admin Bearer **或** HMAC 签名 | 原始文件流(image inline / 其他 attachment) |
| `GET` | `/api/admin/attachments/{id}/info` | Admin Bearer | JSON 元数据(不返回磁盘绝对路径) |

### 3.2 HMAC 签名下载 URL

**为什么需要**: `<img>`、`<a download>` 等浏览器原生元素无法附加 `Authorization` header,必须用可嵌入 URL 的凭证。

**签名格式**(`admin/signurl.go`):

```
exp=<unix_ts>&tenant=<id>&sig=<hex_hmac_sha256>
```

- `sig = HMAC_SHA256(secretKey, "<id>|<exp>|<tenant>")`
- TTL = **30 分钟**(`attachmentSigTTL` 常量)
- `tenant` 写入签名,防止跨租户重放
- 校验失败或过期 → `401 invalid or expired attachment link`

**生成路径**: `SignAttachmentURL(id, tenantID, secretKey) → "exp=…&tenant=…&sig=…"`
**校验路径**: `VerifyAttachmentURL(id, secretKey, q url.Values) → (tenantID, ok)`

**接口组装**: `attachments_handler.go:107-108`

```go
a.DownloadURL = "/api/admin/attachments/" + a.ID +
    "?" + SignAttachmentURL(a.ID, a.TenantID, h.secretKey)
```

### 3.3 鉴权分流(`AttachmentsWithAuth`)

```go
if q.Get("sig") != "" && !strings.Contains(path, "/info") {
    h.ServeHTTP(w, r)            // 走签名校验,不查 Bearer
    return
}
AdminMiddleware(h.ServeHTTP, pool, secretKey)(w, r)   // 其他走 Bearer
```

**关键约束**: `/info` 端点强制走 Bearer,签名不能绕过元数据查询。

### 3.4 路由注册

`cmd/gateway/main.go` 中(参考 `ATTACHMENT_FEATURE_SUMMARY.md:118-121`):

```go
attachmentMgr, err := attachments.NewManager(dbConn.Pool(), storagePath, enabled, maxSizeMB)
chatHandler.SetAttachmentManager(attachmentMgr)
// …
http.Handle("/api/admin/attachments",
    admin.AttachmentsWithAuth(attachmentsHandler, dbConn.Pool(), secretKey))
```

---

## 4. 前端实现

### 4.1 类型定义 (`web/src/api/logs.ts`)

```ts
export interface Attachment {
  id: string
  request_id: string
  tenant_id: string                    // 2026-07-02 改:string(原来是 number)
  attachment_type: string
  media_type: string
  file_size: number
  file_path: string
  original_data_type: string
  content_hash: string
  created_at: string
  download_url?: string                // 签名 URL,仅列表返回时存在
}

export function getAttachments(requestId: string): Promise<Attachment[]>
export function getAttachmentUrl(id: string): string
export function getAttachmentInfo(id: string): Promise<Attachment>

// RequestLogRow 扩展
has_attachments: boolean | null
attachment_count: number | null
```

### 4.2 列表行附件徽标 (`RequestLogsView.vue:1162, 1251-1260`)

```html
<th class="col-attachments" :title="t('requests.list.table.attachmentsTitle')">📎</th>
…
<td class="col-attachments" style="text-align:center">
  <span v-if="r.has_attachments && r.attachment_count > 0"
        class="attachment-badge"
        :title="t('requests.list.table.attachmentCountTitle', { n: r.attachment_count })">
    📎 {{ r.attachment_count }}
  </span>
  <span v-else style="color:var(--muted)">—</span>
</td>
```

样式:

```css
.col-attachments   { width: 3.5rem; text-align: center; }
.attachment-badge  { font-size: 11px; color: var(--accent, #3b82f6);
                     padding: 2px 4px; border-radius: 3px;
                     background: rgba(59, 130, 246, 0.1); cursor: pointer; }
.attachment-badge:hover { background: rgba(59, 130, 246, 0.2); }
```

### 4.3 详情抽屉附件 Tab(`RequestLogsView.vue:1362-1369, 1416-1462`)

Tab 仅在 `detail.has_attachments && detail.attachment_count > 0` 时显示,标签文字:

```html
{{ t('requests.detail_extra.attachmentsTab') }} ({{ detail.attachment_count }})
```

Tab 内容:每个附件一项,行布局 `[缩略图|元信息|下载按钮]`。

```html
<div v-for="attachment in attachments" :key="attachment.id" class="attachment-item">
  <img v-if="attachment.media_type.startsWith('image/')"
       :src="attachment.download_url" :alt="attachment.id"
       style="width:80px;height:80px;object-fit:cover;border-radius:4px;border:1px solid var(--border);cursor:zoom-in"
       @click="openImagePreview(attachment)"
       @error="(e) => ((e.currentTarget as HTMLImageElement).style.display = 'none')" />
  <div>
    <div>{{ attachment.id }}</div>
    <div>类型 {{ attachment.media_type }} · 大小 {{ formatBytes(attachment.file_size) }} · 哈希 {{ attachment.content_hash.substring(0, 12) }}…</div>
    <div>创建于 {{ fmtTs(attachment.created_at) }}</div>
  </div>
  <a :href="attachment.download_url" target="_blank" class="btn btn-sm" :download="attachment.id">下载</a>
</div>
```

样式:

```css
.attachment-item        { padding:12px; border:1px solid var(--border); border-radius:6px;
                          background:var(--surface-primary); }
.attachment-item:hover  { background:var(--surface-secondary); }
```

### 4.4 大图预览 lightbox (`RequestLogsView.vue:119-132, 1494-1536`)

```ts
const previewAttachment = ref<Attachment | null>(null)

function openImagePreview(att: Attachment) {
  if (!att.media_type.startsWith('image/')) return
  previewAttachment.value = att
}
function closeImagePreview() {
  previewAttachment.value = null
}
```

模板用 `<Teleport to="body">` 渲染到根,确保 z-index 不被父抽屉裁剪:

```html
<Teleport to="body">
  <div v-if="previewAttachment" class="image-preview-backdrop"
       @click="closeImagePreview"
       style="position:fixed;inset:0;background:rgba(0,0,0,0.85);
              display:flex;align-items:center;justify-content:center;
              z-index:9999;backdrop-filter:blur(4px)">
    <div class="image-preview-modal" @click.stop
         style="max-width:92vw;max-height:92vh;background:var(--card);
                padding:16px;border-radius:8px;box-shadow:0 8px 32px rgba(0,0,0,0.6)">
      <img :src="previewAttachment.download_url"
           :style="{ maxWidth:'90vw', maxHeight:'80vh', objectFit:'contain',
                     borderRadius:'4px', background:'#000' }" />
      <div>…ID / 类型 / 大小 / 哈希… · <a :href="previewAttachment.download_url"
           target="_blank" :download="previewAttachment.id">下载原图</a>
        <button class="btn btn-sm" @click="closeImagePreview">关闭</button></div>
    </div>
  </div>
</Teleport>
```

### 4.5 关键交互细节

| 行为 | 实现 | 位置 |
|------|------|------|
| ESC 关闭 lightbox(全局) | `window.addEventListener('keydown', handleKeydown)` 注册在 `onMounted`,清理在 `onBeforeUnmount` | `RequestLogsView.vue:86-90, 920` |
| 缩略图 hover 缩放 | 内联 `@mouseover/@mouseleave` 修改 `transform: scale(1.03)` | `RequestLogsView.vue:1433-1434` |
| 缩略图加载失败隐藏 | `@error` 置 `display:none`,避免破图标 | `RequestLogsView.vue:1435` |
| 关闭详情清附件 | `closeDetail()` 调 `attachments.value = []; closeImagePreview()` | `RequestLogsView.vue:726-731` |
| `getAttachments` 返回 `null` 防炸 | `Array.isArray(result) ? result : []` | `RequestLogsView.vue:708-724` |

---

## 5. 本轮(2026-07-02)修复与增强

### 5.1 修复:`getAttachments` 返回 `null` 导致整页白屏

**根因**: Go `ListByRequestID` 没找到行时返回 `nil []*Attachment`,`encoding/json` 序列化为 `null`,Vue 模板读 `attachments.length` 抛 `Cannot read properties of null`,整个详情面板渲染被中断。

**修复**(`RequestLogsView.vue:711-718`):

```ts
const result = await getAttachments(requestId)
attachments.value = Array.isArray(result) ? result : []
```

**跨分支同步要点**: 即使后端将来改为返回 `[]`,这段防御性 fallback 也无害,可保留。

### 5.2 增强:lightbox 全局 ESC 关闭

**问题**: 原 ESC 监听绑在抽屉根节点,操作员点开 lightbox 后焦点可能不在抽屉内,ESC 不响应。

**修复**(`RequestLogsView.vue:83-90, 917-920`):

```ts
function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape' && previewAttachment.value) {
    closeImagePreview()
  }
}
…
onMounted(async () => {
  window.addEventListener('keydown', handleKeydown)
  await loadKeys(); await load()
})
```

清理逻辑已在原 `onBeforeUnmount` 钩子中(`stopAutoRefresh` 旁),无需新增。

### 5.3 类型修正:`Attachment.tenant_id` 由 `number` 改 `string`

`web/src/api/logs.ts:233`,与后端实际 JSON 一致。其他分支若 `tsc` 报错,搜 `tenant_id: number` 一并替换。

---

## 6. i18n 文案

### 中文(`web/src/i18n/locales/zh-CN/requests.ts`)

```ts
list.table.attachmentsTitle:       '附件'
list.table.attachmentCountTitle:   '{n} 个附件'
detail_extra.attachmentsTab:       '📎 附件'
detail_extra.attachmentsLoading:   '加载附件中…'
detail_extra.noAttachments:        '无附件'
detail_extra.clickToPreviewTitle:  '点击查看大图'
detail_extra.download:             '下载'
detail_extra.downloadOriginal:     '下载原图'
detail_extra.closePreview:         '关闭'
common.typeLabel:                  '类型'
common.sizeLabel:                  '大小'
common.hashLabel:                  '哈希'
common.createdAtLabel:             '创建于'
```

英文 locale(`en-US/requests.ts`)必须保持键一致,值另译。

---

## 7. 配置项(后端环境变量)

```bash
ATTACHMENT_STORAGE_PATH=./data/attachments   # 文件存储根
ATTACHMENT_ENABLED=true                      # 总开关
ATTACHMENT_MAX_SIZE_MB=10                    # 单附件上限
ATTACHMENT_RETENTION_DAYS=0                  # 0=永久,>0=清理阈值
# secretKey 与 JWT 共用,从 ADMIN_JWT_SECRET / LLM_GATEWAY_SECRET 取
```

读取位置:`cmd/gateway/main.go:229-247`。

---

## 8. 同步到其他分支的最小补丁

按以下顺序 cherry-pick / 手抄,即可在另一分支复刻同等行为:

### 8.1 后端(必选)

1. `attachments/attachment.go` — 结构体 + `DownloadURL` 字段
2. `attachments/manager.go` — Manager + `ListByRequestID` / `GetByID` / `OpenFile`
3. `admin/signurl.go` — `SignAttachmentURL` / `VerifyAttachmentURL` / `hmacSig` / `attachmentSigTTL = 30min`
4. `admin/attachments_handler.go` — `AttachmentsHandler` + `AttachmentsWithAuth`(签名分流)
5. `cmd/gateway/main.go` — 初始化 Manager + 注册路由
6. `db/attachments_schema.go` — 创建表 + 加列 + 加索引
7. `relay/handler.go` — `ExtractAndSaveAttachments` 集成点

### 8.2 前端(必选)

1. `web/src/api/logs.ts` — `Attachment` 接口 + `getAttachments` / `getAttachmentUrl` / `getAttachmentInfo` + `RequestLogRow` 加 2 字段
2. `web/src/views/RequestLogsView.vue`:
   - import 上述 API/类型
   - 加 `attachments` / `attachmentsLoading` / `previewAttachment` ref
   - 加 `openImagePreview` / `closeImagePreview` / `formatBytes` / `loadAttachments` 函数
   - 列表 `<th class="col-attachments">📎</th>` + `<td class="col-attachments">…</td>`
   - 详情抽屉加 Tab 按钮(只在 `has_attachments && attachment_count > 0` 时显示)
   - 详情抽屉加 `detailTab === 'attachments'` 模板分支(缩略图 + 元信息 + 下载按钮)
   - `<Teleport to="body">` lightbox
   - `onMounted` 注册 `window.keydown`
   - CSS: `.col-attachments`, `.attachment-badge`, `.attachment-item`

### 8.3 前端 i18n(必选)

- `web/src/i18n/locales/zh-CN/requests.ts` — 见 §6 键
- `web/src/i18n/locales/en-US/requests.ts` — 同步键

### 8.4 本轮修复补丁(强烈建议)

| 文件 | 改动 |
|------|------|
| `RequestLogsView.vue:711-718` | `Array.isArray(result) ? result : []` 防 `null` |
| `RequestLogsView.vue:83-90, 917-920` | 全局 ESC 关闭 lightbox |
| `web/src/api/logs.ts:233` | `tenant_id: string` |

---

## 9. 已知限制与扩展点

| 项 | 当前状态 | 建议扩展 |
|----|---------|---------|
| 图片大图预览 | 已有 lightbox | 缩放 / 旋转 / 键盘 ←→ 翻页 |
| 批量下载 | 无 | 复选 + 服务端 zip |
| 缩略图 | 浏览器直接缩放原图 | 服务端预生成 `thumb_*.jpg` |
| 非图片附件 | 仅显示元信息 + 下载按钮 | 加 PDF 内嵌预览 / 音频 `<audio>` |
| 签名 TTL | 固定 30 min | 抽 env 可配 `ATTACHMENT_SIG_TTL` |
| 列表过滤 "只看有附件" | 无 | 在 filter bar 加 `has_attachments=true` 复选框 |

---

## 10. 验收清单

- [ ] 列表:有附件行显示 `📎 N`,无则显示 `—`
- [ ] 列表 hover `📎 N` 出现蓝色高亮背景
- [ ] 详情 Tab:有附件时显示 `📎 附件 (N)`,数量与徽标一致
- [ ] 详情 Tab:点击加载附件,显示 80×80 缩略图 + ID + 类型 + 大小 + 哈希前 12 位 + 创建时间
- [ ] 详情 Tab:点击缩略图弹出 lightbox,显示原图 + 元信息 + 下载/关闭按钮
- [ ] lightbox:ESC 关闭(全局生效,不需先点回抽屉)
- [ ] lightbox:点击遮罩关闭,点击内容不关
- [ ] 下载按钮:浏览器下载原文件,文件名 = `attachment.id`
- [ ] 缩略图加载失败时静默隐藏,不破布局
- [ ] 后端 `attachments` 表为空时,详情 Tab 显示「无附件」而非白屏(本轮修复)
- [ ] 跨租户签名 URL 不能下载其他租户附件(后端签名绑定 tenant,前端无感)

---

**文档维护者**: 半 king
**版本**: 1.0(2026-07-02)
**适用代码**: `github` 分支 `76257380` 之后