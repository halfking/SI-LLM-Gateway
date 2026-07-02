package adapter

import (
	"encoding/json"

	"github.com/kaixuan/llm-gateway-go/internal/ir"
)

// This file contains the OpenAI-compatible provider adapters.
// Each embeds StandardOpenAI and overrides AdaptRequest + GetCapabilities
// with provider-specific parameter clamping and feature declarations.
//
// AdaptRequest guidelines:
//   - Clamp max_tokens to the provider's limit (reduce, never reject).
//   - Set TargetProvider so the IR serializer knows which quirks to apply.
//   - Never mutate the original *ir.InternalRequest; always work on a copy
//     (the caller may reuse the original for retries).

// clampMaxTokens returns a copy of req with MaxTokens capped at maxVal.
// When req.MaxTokens is already <= maxVal (or 0), the request is returned
// unchanged. This is a soft clamp — we reduce rather than reject so the
// request still succeeds with a shorter completion.
func clampMaxTokens(req *ir.InternalRequest, maxVal int) *ir.InternalRequest {
	if maxVal <= 0 || req.MaxTokens <= 0 || req.MaxTokens <= maxVal {
		return req
	}
	out := *req
	out.MaxTokens = maxVal
	return &out
}

// ─── DeepSeek ──────────────────────────────────────────────────────────────

// DeepSeek speaks standard OpenAI Chat Completions. Known quirks:
//   - max_tokens must be ≤ 8192 (DeepSeek-V3/R1)
//   - reasoning_content field (R1 series) is handled by IR's thinking support
type DeepSeek struct {
	StandardOpenAI
}

func NewDeepSeek() *DeepSeek { return &DeepSeek{} }

func (d *DeepSeek) Name() string           { return "deepseek" }
func (d *DeepSeek) CatalogCodes() []string { return []string{"deepseek"} }

func (d *DeepSeek) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
	adapted := clampMaxTokens(req, 8192)
	out := *adapted
	out.TargetProvider = "deepseek"
	return &out, nil
}

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

// Qwen speaks standard OpenAI Chat Completions via DashScope. Known quirks:
//   - max_tokens must be ≤ 8192 for most models (Qwen-Max); Qwen-Turbo allows 6K
//   - DashScope rejects requests that set BOTH temperature and top_p;
//     when both are present we drop top_p (temperature is more commonly used)
type Qwen struct {
	StandardOpenAI
}

func NewQwen() *Qwen { return &Qwen{} }

func (q *Qwen) Name() string           { return "qwen" }
func (q *Qwen) CatalogCodes() []string { return []string{"qwen", "qwen2", "qwen3", "qwq"} }

func (q *Qwen) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
	adapted := clampMaxTokens(req, 8192)
	out := *adapted
	out.TargetProvider = "qwen"
	// DashScope rejects requests that set BOTH temperature and top_p.
	// When both are present, prefer temperature and drop top_p.
	if out.Temperature != nil && out.TopP != nil {
		out.TopP = nil
	}
	return &out, nil
}

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
// Known quirks:
//   - max_tokens must be ≤ 4096 (Doubao-Pro-4K and Lite series)
//   - temperature range [0, 1] (outside this range is clamped, not rejected)
type Doubao struct {
	StandardOpenAI
}

func NewDoubao() *Doubao { return &Doubao{} }

func (d *Doubao) Name() string           { return "doubao" }
func (d *Doubao) CatalogCodes() []string { return []string{"doubao"} }

func (d *Doubao) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
	adapted := clampMaxTokens(req, 4096)
	out := *adapted
	out.TargetProvider = "doubao"
	// Volcano Engine clamps temperature to [0, 1]. Do the same client-side
	// so the request is not rejected with 400.
	if out.Temperature != nil {
		t := *out.Temperature
		if t < 0 {
			t = 0
		} else if t > 1 {
			t = 1
		}
		out.Temperature = &t
	}
	return &out, nil
}

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
// (Kimi supports up to 2M tokens on moonshot-v1-128k and newer).
// max_tokens is generous (8192) but varies per model.
type Moonshot struct {
	StandardOpenAI
}

func NewMoonshot() *Moonshot { return &Moonshot{} }

func (m *Moonshot) Name() string           { return "moonshot" }
func (m *Moonshot) CatalogCodes() []string { return []string{"moonshot", "kimi"} }

func (m *Moonshot) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
	adapted := clampMaxTokens(req, 8192)
	out := *adapted
	out.TargetProvider = "moonshot"
	return &out, nil
}

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

// Zhipu speaks standard OpenAI Chat Completions (GLM-4/5 series).
// Known quirks:
//   - max_tokens must be ≤ 8192 (GLM-4); GLM-5.2 supports up to 16K output
//   - Supports thinking blocks (GLM-5.2), compatible with IR thinking support
type Zhipu struct {
	StandardOpenAI
}

func NewZhipu() *Zhipu { return &Zhipu{} }

func (z *Zhipu) Name() string           { return "zhipu" }
func (z *Zhipu) CatalogCodes() []string { return []string{"zhipu", "glm"} }

func (z *Zhipu) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
	adapted := clampMaxTokens(req, 8192)
	out := *adapted
	out.TargetProvider = "zhipu"
	return &out, nil
}

func (z *Zhipu) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:  true,
		SupportsStreaming:    true,
		SupportsVision:       true, // GLM-4V / GLM-5.2
		SupportsThinking:     true, // GLM-5.2 thinking
		SupportsCacheControl: false,
		MaxTokens:            8192,
		ToolIDField:          "tool_call_id",
	}
}

// ─── Helper: JSON body rewrite ─────────────────────────────────────────────

// rewriteJSONField renames a top-level key in a JSON object body.
// This is a no-op when the field is absent or the body is not a JSON object.
func rewriteJSONField(body []byte, oldKey, newKey string) []byte {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(body, &obj); err != nil {
		return body
	}
	val, ok := obj[oldKey]
	if !ok {
		return body
	}
	obj[newKey] = val
	delete(obj, oldKey)
	out, err := json.Marshal(obj)
	if err != nil {
		return body
	}
	return out
}
