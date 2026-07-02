package adapter

// This file contains the OpenAI-compatible provider adapters.
// Each is a thin wrapper over StandardOpenAI that overrides Capabilities
// and (where needed) AdaptRequest for provider-specific parameter clamping.

// ─── DeepSeek ──────────────────────────────────────────────────────────────

// DeepSeek speaks standard OpenAI Chat Completions. Known quirks:
//   - reasoning_content field (R1 series) is handled by IR's thinking support
//   - No native tool calling on the free tier (but supports on paid)
type DeepSeek struct {
	StandardOpenAI
}

func NewDeepSeek() *DeepSeek { return &DeepSeek{} }

func (d *DeepSeek) Name() string         { return "deepseek" }
func (d *DeepSeek) CatalogCodes() []string { return []string{"deepseek"} }

func (d *DeepSeek) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:  true,
		SupportsStreaming:    true,
		SupportsVision:       false,
		SupportsThinking:     true, // DeepSeek-R1 reasoning_content
		SupportsCacheControl: false,
		MaxTokens:            8192,
		ToolIDField:          "tool_call_id",
	}
}

// ─── Qwen (Alibaba 通义千问) ────────────────────────────────────────────────

// Qwen speaks standard OpenAI Chat Completions via DashScope.
type Qwen struct {
	StandardOpenAI
}

func NewQwen() *Qwen { return &Qwen{} }

func (q *Qwen) Name() string         { return "qwen" }
func (q *Qwen) CatalogCodes() []string { return []string{"qwen", "qwen2", "qwen3", "qwq"} }

func (q *Qwen) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:  true,
		SupportsStreaming:    true,
		SupportsVision:       true, // Qwen-VL series
		SupportsThinking:     true, // QwQ series
		SupportsCacheControl: false,
		MaxTokens:            8192,
		ToolIDField:          "tool_call_id",
	}
}

// ─── Doubao (ByteDance 豆包) ────────────────────────────────────────────────

// Doubao speaks standard OpenAI Chat Completions via Volcano Engine.
type Doubao struct {
	StandardOpenAI
}

func NewDoubao() *Doubao { return &Doubao{} }

func (d *Doubao) Name() string         { return "doubao" }
func (d *Doubao) CatalogCodes() []string { return []string{"doubao"} }

func (d *Doubao) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:  true,
		SupportsStreaming:    true,
		SupportsVision:       true, // Doubao-Vision
		SupportsThinking:     false,
		SupportsCacheControl: false,
		MaxTokens:            4096,
		ToolIDField:          "tool_call_id",
	}
}

// ─── Moonshot (Kimi) ────────────────────────────────────────────────────────

// Moonshot speaks standard OpenAI Chat Completions. Known for long context
// (Kimi supports up to 2M tokens on some models).
type Moonshot struct {
	StandardOpenAI
}

func NewMoonshot() *Moonshot { return &Moonshot{} }

func (m *Moonshot) Name() string         { return "moonshot" }
func (m *Moonshot) CatalogCodes() []string { return []string{"moonshot", "kimi"} }

func (m *Moonshot) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:  true,
		SupportsStreaming:    true,
		SupportsVision:       false,
		SupportsThinking:     false,
		SupportsCacheControl: false,
		MaxTokens:            8192,
		ToolIDField:          "tool_call_id",
	}
}

// ─── Zhipu (智谱 AI) ────────────────────────────────────────────────────────

// Zhipu speaks standard OpenAI Chat Completions (GLM-4 series) and also
// supports an Anthropic-compatible endpoint. Tool calling is supported.
type Zhipu struct {
	StandardOpenAI
}

func NewZhipu() *Zhipu { return &Zhipu{} }

func (z *Zhipu) Name() string         { return "zhipu" }
func (z *Zhipu) CatalogCodes() []string { return []string{"zhipu", "glm"} }

func (z *Zhipu) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:  true,
		SupportsStreaming:    true,
		SupportsVision:       true, // GLM-4V
		SupportsThinking:     true, // GLM-5.2 thinking
		SupportsCacheControl: false,
		MaxTokens:            8192,
		ToolIDField:          "tool_call_id",
	}
}
