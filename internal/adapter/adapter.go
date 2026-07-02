// Package adapter provides provider-specific protocol adaptations.
//
// Architecture:
//
//	Inbound Layer (Parser)          IR Layer              Provider Adapter Layer
//	┌─────────────────────┐       ┌─────────────┐       ┌──────────────────────┐
//	│ OpenAI Parser        │──────▶│             │──────▶│ StandardAnthropic    │
//	│ Anthropic Parser     │──────▶│ InternalReq │       │ StandardOpenAI       │
//	└─────────────────────┘       │ InternalResp│       │ MiniMax              │
//	                              └─────────────┘       │ DeepSeek             │
//	                                                    │ Qwen                 │
//	                                                    │ Doubao               │
//	                                                    │ Moonshot             │
//	                                                    │ Zhipu                │
//	                                                    └──────────────────────┘
//
// Each adapter handles the provider-specific wire-format quirks (tool_call_id
// vs tool_use_id, default parameters, error formats, etc.) so the IR layer
// stays clean and adding a new provider is a single file.
package adapter

import (
	"github.com/kaixuan/llm-gateway-go/internal/ir"
)

// ProviderAdapter handles provider-specific protocol adaptations.
//
// The interface is split into two halves:
//   - Request half:  AdaptRequest + SerializeRequest  (IR → provider wire format)
//   - Response half: ParseResponse + AdaptResponse    (provider wire format → IR)
//
// Adapters that only need to tweak the serialized body (e.g., MiniMax's
// tool_call_id) can embed StandardAnthropic or StandardOpenAI and override
// only the methods that differ.
type ProviderAdapter interface {
	// Name returns the provider identifier (e.g., "minimax", "anthropic",
	// "deepseek"). This is used for logging, metrics, and adapter selection.
	Name() string

	// CatalogCodes returns the catalog_code values this adapter handles.
	// Used by the Factory to route requests to the correct adapter based on
	// the candidate's CatalogCode. Example: MiniMax returns ["minimax"].
	CatalogCodes() []string

	// AdaptRequest mutates the IR before serialization to apply provider-specific
	// adjustments (e.g., clamping max_tokens, adding default params). The
	// returned IR is what SerializeRequest receives.
	AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error)

	// SerializeRequest serializes the (possibly adapted) IR into the provider's
	// wire format. For Anthropic-protocol providers this calls
	// ir.SerializeAnthropic; for OpenAI-protocol providers it calls
	// ir.SerializeOpenAI. Providers with non-standard fields (e.g., MiniMax's
	// tool_call_id) post-process the serialized body here.
	SerializeRequest(req *ir.InternalRequest) ([]byte, error)

	// ParseResponse parses the provider's response body into IR. Most providers
	// can delegate to ir.ParseAnthropicResponse or ir.ParseOpenAIResponse;
	// providers with response-format quirks pre-normalize the body here.
	ParseResponse(body []byte) (*ir.InternalResponse, error)

	// GetCapabilities returns the feature set this provider supports.
	// Used for validation (reject unsupported features early) and for the
	// admin UI's provider-detail view.
	GetCapabilities() Capabilities
}

// Capabilities describes what a provider supports.
//
// Fields are intentionally simple bools / ints so the validation logic in
// AdaptRequest can check them without importing provider-specific types.
type Capabilities struct {
	// SupportsToolCalling is true when the provider accepts structured
	// tools[] and returns structured tool_calls / tool_use blocks.
	SupportsToolCalling bool

	// SupportsStreaming is true when the provider supports SSE streaming.
	SupportsStreaming bool

	// SupportsVision is true when the provider can process image inputs.
	SupportsVision bool

	// SupportsThinking is true when the provider emits thinking / reasoning
	// blocks (Claude extended thinking, DeepSeek-R1 reasoning_content, etc.).
	SupportsThinking bool

	// SupportsCacheControl is true when the provider supports Anthropic-style
	// prompt caching (cache_control: {type: "ephemeral"}).
	SupportsCacheControl bool

	// MaxTokens is the provider's max_tokens limit. 0 means unknown / uncapped.
	MaxTokens int

	// ToolIDField is the field name this provider uses for tool results.
	// "tool_use_id" (standard Anthropic) or "tool_call_id" (MiniMax).
	// Empty defaults to the standard value for the wire protocol.
	ToolIDField string
}
