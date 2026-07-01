package settings

// spec_contentid.go — Attachment content identification settings.
// 2026-07-02: Added to support layered content identification for archived
// image attachments (description / OCR / classification / response-reuse /
// injection). Each source has an independent switch because every source
// carries a processing cost (LLM tokens, external HTTP call). The master
// switch short-circuits the entire subsystem.

func ContentIDSpecs() []*Spec {
	return []*Spec{
		// ── master switch ──────────────────────────────────────────────
		{
			Key:      "llmgw_contentid_enabled",
			EnvName:  "LLM_GATEWAY_CONTENT_IDENTIFICATION_ENABLED",
			Type:     TypeBool,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  false,
			Description: "附件内容识别总开关。关闭后所有分析路径短路，" +
				"归档的图片不会触发任何识别（描述/OCR/分类均不执行）。" +
				"默认关闭——每个识别来源都有成本，需按需开启。",
			DangerLevel:   Safe,
			HotReload:     true,
			Observability: "/api/admin/attachments/analysis-stats",
		},

		// ── per-source switches (independent, cost-aware) ─────────────

		// Source A: response reuse — ZERO cost (response already captured).
		{
			Key:      "llmgw_contentid_response_reuse_enabled",
			EnvName:  "LLM_GATEWAY_CONTENTID_RESPONSE_REUSE_ENABLED",
			Type:     TypeBool,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  true,
			Description: "复用上游 LLM 的响应文本作为图片描述来源。" +
				"零额外成本——网关已捕获完整助手响应文本（request_logs.response_body）。" +
				"仅当用户的问题涉及图片内容时有效。" +
				"默认开启，因为不消耗任何额外资源。",
			DangerLevel: Safe,
			HotReload:   true,
		},

		// Source C: vision LLM description — 1 LLM call per image.
		{
			Key:      "llmgw_contentid_vision_description_enabled",
			EnvName:  "LLM_GATEWAY_CONTENTID_VISION_DESCRIPTION_ENABLED",
			Type:     TypeBool,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  false,
			Description: "通过网关自回环调用视觉大模型生成图片描述。" +
				"每个图片消耗 1 次 LLM 调用（走自动路由，复用现有凭证/熔断）。" +
				"默认关闭——有 token 成本，按需开启。",
			DangerLevel: Safe,
			HotReload:   true,
		},

		// Source D: OCR — external HTTP call to PaddleOCR service.
		{
			Key:      "llmgw_contentid_ocr_enabled",
			EnvName:  "LLM_GATEWAY_CONTENTID_OCR_ENABLED",
			Type:     TypeBool,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  false,
			Description: "通过外部 OCR 服务（PaddleOCR / PaddleX serving）" +
				"提取图片中的文字。OCR 服务独立部署为公共服务，" +
				"网关作为 HTTP 客户端调用。默认关闭——需先配置 OCR 端点。",
			DangerLevel: Safe,
			HotReload:   true,
		},

		// Source E: classification — local, zero cost (derived from OCR/desc).
		{
			Key:      "llmgw_contentid_classification_enabled",
			EnvName:  "LLM_GATEWAY_CONTENTID_CLASSIFICATION_ENABLED",
			Type:     TypeBool,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  false,
			Description: "基于 OCR 文本和描述做本地规则分类" +
				"（截图/照片/图表/文档/头像/代码/UI）。本地零成本。" +
				"默认关闭，建议在描述或 OCR 开启后一起开。",
			DangerLevel: Safe,
			HotReload:   true,
		},

		// Feature #4: injection of cached description into forwarded request.
		{
			Key:      "llmgw_contentid_injection_enabled",
			EnvName:  "LLM_GATEWAY_CONTENTID_INJECTION_ENABLED",
			Type:     TypeBool,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  false,
			Description: "将缓存的图片描述注入转发的 LLM 请求（功能#4）。" +
				"首张图片原样转发+异步分析；相同图片（按 content_hash）再次出现时，" +
				"在对应消息追加一个 text 块 [image context: <description>]。" +
				"只增不删，安全。默认关闭——会修改转发请求体。",
			DangerLevel: Warning,
			HotReload:   true,
		},

		// ── configuration values ───────────────────────────────────────

		// OCR service endpoint (PaddleX serving: POST /ocr).
		{
			Key:      "llmgw_contentid_ocr_endpoint",
			EnvName:  "LLM_GATEWAY_CONTENTID_OCR_ENDPOINT",
			Type:     TypeURL,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  "",
			Description: "外部 OCR 服务的 base URL（PaddleX serving）。" +
				"例如 http://ocr-service:8080 。网关会向 {endpoint}/ocr POST base64 图片。" +
				"留空时 OCR 来源降级跳过（不报错）。" +
				"OCR 服务应独立部署为公共服务，供多个项目共用。",
			DangerLevel: Safe,
			HotReload:   true,
		},

		// Vision model (empty = auto-route).
		{
			Key:      "llmgw_contentid_vision_model",
			EnvName:  "LLM_GATEWAY_CONTENTID_VISION_MODEL",
			Type:     TypeString,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  "",
			Description: "视觉描述使用的模型。留空则走自动路由" +
				"（model=auto + X-Gw-Task-Hint: vision）。" +
				"指定模型名（如 gpt-4o）则绕过自动路由直接使用该模型。",
			DangerLevel: Safe,
			HotReload:   true,
		},

		// Vision loopback timeout.
		{
			Key:      "llmgw_contentid_vision_timeout",
			EnvName:  "LLM_GATEWAY_CONTENTID_VISION_TIMEOUT",
			Type:     TypeDuration,
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  30.0,
			Description: "视觉描述自回环调用的超时（秒）。" +
				"默认 30 秒。大图片或慢模型可适当调大。",
			DangerLevel: Safe,
			HotReload:   true,
		},
	}
}
