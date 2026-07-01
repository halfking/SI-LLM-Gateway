# 附件内容识别 (Content Identification) — 实现报告 V723

> 2026-07-02. 分层、成本感知的归档图片内容识别子系统。异步、旁路
> 观察者——不阻塞请求路径，不修改上游语义（功能#4 注入除外，且
> 默认关闭）。

## 架构概览

```
relay handler (chat / messages)
  │
  ├─ archiveAndEnqueueAnalysis ──→ Attachments 表 (base64→文件)
  │                                  │
  │                                  └─→ AnalysisSink.Enqueue (非阻塞)
  │                                          │
  │                                          ▼
  │                                  [worker] Analyzer.Analyze
  │                                    │
  │                                    ├─ B. hash_cache (零成本, 按 content_hash 复用)
  │                                    ├─ A. response_reuse (零成本, 复用上游响应文本)
  │                                    ├─ C. vision_loopback (1 次 LLM, 自回环)
  │                                    ├─ D. ocr (外部 HTTP, PaddleX serving)
  │                                    └─ E. classifier (本地规则, 零成本)
  │                                          │
  │                                          ▼
  │                                  metadata JSONB (content_identification)
  │
  └─ descriptionInjector (功能#4) ──→ 命中缓存则追加 [image context: ...] 文本块
```

## 五个识别来源（按成本排序）

| 来源 | 开关 | 成本 | 实现 |
|------|------|------|------|
| **B. hash_cache** | (隐式) | 零 | 按 content_hash 复用已完成的分析结果 |
| **A. response_reuse** | `llmgw_contentid_response_reuse_enabled` (默认开) | 零 | 复用 request_logs 已捕获的响应文本 |
| **E. classification** | `llmgw_contentid_classification_enabled` | 零 | 本地规则分类 (code/document/chart/ui/screenshot/photo/avatar) |
| **C. vision_loopback** | `llmgw_contentid_vision_description_enabled` | 1 次 LLM | 自回环 `/v1/chat/completions` + `X-Gw-Task-Hint: vision` |
| **D. ocr** | `llmgw_contentid_ocr_enabled` | 外部 HTTP | PaddleX serving `POST /ocr` (`{file:base64, fileType:1}`) |

主开关 `llmgw_contentid_enabled` 默认**关闭**——每个来源都有成本，需按需开启。

## 功能#4: 描述注入

`llmgw_contentid_injection_enabled` (默认关闭, DangerLevel=Warning)。
当相同图片（按 content_hash）再次出现时，在对应消息追加一个
`[image context: <description> | OCR: ... | tags: ...]` 文本块。

安全属性：
- **只增不删**——永不修改/删除原始 image 块
- **幂等**——已注入的 hash 不重复注入
- **可选**——默认关闭，需显式开启

## 关键文件

### 新建文件
| 文件 | 用途 |
|------|------|
| `settings/spec_contentid.go` | 10 个设置 spec（主开关 + 5 来源 + 端点/模型/超时） |
| `attachmentanalysis/types.go` | ContentIdentification 结构 + status 常量 |
| `attachmentanalysis/config.go` | AtomicConfig（热重载线程安全快照） |
| `attachmentanalysis/store.go` | DB 辅助：metadata JSONB `||` 合并、hash 查找、pending 扫描 |
| `attachmentanalysis/analyzer.go` | 编排器：5 来源分发 + ForceReanalyze + ScanPending |
| `attachmentanalysis/sink.go` | 有界异步队列（仿 memora.Sink），满则丢弃+计数 |
| `attachmentanalysis/response_reuse.go` | 响应文本缓存（source A） |
| `attachmentanalysis/vision_client.go` | 视觉自回环客户端（OpenAI 多模态格式） |
| `attachmentanalysis/ocr_client.go` | PaddleX OCR HTTP 客户端 |
| `attachmentanalysis/classifier.go` | 本地规则分类器 |
| `attachmentanalysis/injection.go` | 功能#4 注入逻辑（OpenAI + Anthropic 格式） |
| `attachmentanalysis/attachmentanalysis_test.go` | 11 个单元测试 |
| `bg/attachment_analysis_sweeper.go` | 崩溃恢复扫描器（5min，热重载配置） |
| `admin/attachments_analysis_api.go` | admin API: reanalyze / reanalyze-pending / stats |

### 修改文件
| 文件 | 改动 |
|------|------|
| `db/attachments_schema.go` | 新增 `idx_attachments_analysis_pending` 部分索引 |
| `settings/specs.go` | 注册 `ContentIDSpecs()` |
| `attachments/manager.go` | 新增 `ArchiveAttachmentsDetailed` + `ArchivedAttachmentInfo` |
| `relay/handler.go` | 归档后入队分析 + emitTelemetry 喂响应文本 + 注入调用点 |
| `relay/messages.go` | Anthropic 路径同样入队分析 |
| `cmd/gateway/main.go` | 装配 analyzer/sink/providers/sweeper + 热重载 + shutdown |
| `web/src/api/logs.ts` | Attachment 类型增加 metadata 字段 |
| `web/src/views/RequestLogsView.vue` | 附件预览增加内容识别面板 |

## 安全设计

1. **旁路观察者**：分析是 side-channel，永不阻塞/失败用户请求
2. **非阻塞入队**：sink 满则丢弃（计数），bg sweeper 5min 后恢复
3. **租户隔离**：所有 DB 查询带 tenant_id 范围；响应缓存有租户校验
4. **只增注入**：功能#4 只追加文本块，幂等，默认关闭
5. **热重载**：所有开关通过 settings 读取，sweeper 每 tick 刷新

## Admin API

| 端点 | 方法 | 用途 |
|------|------|------|
| `/api/admin/attachments/analysis/reanalyze/{id}` | POST | 手动重新分析单个附件 |
| `/api/admin/attachments/analysis/reanalyze-pending` | POST | 扫描+重新入队所有 pending |
| `/api/admin/attachments/analysis/stats` | GET | 队列计数 + 最近错误 |

## 验证

- ✅ `go build ./...` 全量编译通过
- ✅ `go test ./attachmentanalysis/...` 11 个测试全部通过
- ✅ `vue-tsc --noEmit` 前端类型检查通过
- ⚠️ `relay/relay_test.go` 有预存编译错误（与本改动无关）

## 部署步骤

1. 部署二进制（schema 自动迁移：新增部分索引）
2. 设置 `LLM_GATEWAY_CONTENT_IDENTIFICATION_ENABLED=true` 开启主开关
3. （可选）设置 `LLM_GATEWAY_CONTENTID_VISION_DESCRIPTION_ENABLED=true` + 配置 AdminAPIKey
4. （可选）设置 `LLM_GATEWAY_CONTENTID_OCR_ENABLED=true` + `LLM_GATEWAY_CONTENTID_OCR_ENDPOINT=http://ocr:8080`
5. （可选）设置 `LLM_GATEWAY_CONTENTID_INJECTION_ENABLED=true` 开启功能#4
