package adapter

import (
	"github.com/kaixuan/llm-gateway-go/internal/ir"
)

// StandardAnthropic is the baseline adapter for Anthropic Messages API and
// any provider that speaks the standard Anthropic wire format without quirks.
//
// Provider-specific adapters (MiniMax, etc.) embed this struct so they only
// override the methods that differ, inheriting correct behavior for the rest.
type StandardAnthropic struct{}

func (StandardAnthropic) Name() string         { return "anthropic" }
func (StandardAnthropic) CatalogCodes() []string { return []string{"anthropic"} }

func (s StandardAnthropic) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
	// Standard Anthropic needs no adaptation.
	return req, nil
}

func (StandardAnthropic) SerializeRequest(req *ir.InternalRequest) ([]byte, error) {
	return ir.SerializeAnthropic(req)
}

func (StandardAnthropic) ParseResponse(body []byte) (*ir.InternalResponse, error) {
	return ir.ParseAnthropicResponse(body)
}

func (StandardAnthropic) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:   true,
		SupportsStreaming:     true,
		SupportsVision:        true,
		SupportsThinking:      true,
		SupportsCacheControl:  true,
		MaxTokens:             200000, // Claude 3.5 Sonnet output limit context
		ToolIDField:          "tool_use_id",
	}
}

// StandardOpenAI is the baseline adapter for OpenAI Chat Completions API and
// any provider that speaks a standard OpenAI-compatible wire format.
type StandardOpenAI struct{}

func (StandardOpenAI) Name() string         { return "openai" }
func (StandardOpenAI) CatalogCodes() []string { return []string{"openai"} }

func (s StandardOpenAI) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
	// Standard OpenAI needs no adaptation.
	return req, nil
}

func (s StandardOpenAI) SerializeRequest(req *ir.InternalRequest) ([]byte, error) {
	return ir.SerializeOpenAI(req)
}

func (StandardOpenAI) ParseResponse(body []byte) (*ir.InternalResponse, error) {
	return ir.ParseOpenAIResponse(body)
}

func (StandardOpenAI) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:  true,
		SupportsStreaming:    true,
		SupportsVision:       true,
		SupportsThinking:     false,
		SupportsCacheControl: false,
		MaxTokens:            16384, // GPT-4o default; provider-specific adapters override
		ToolIDField:          "tool_call_id",
	}
}

// defaultAdapters returns the built-in set registered by NewFactory.
// Order doesn't matter (Factory uses map lookups), but we list them in
// priority order for readability.
func defaultAdapters() []ProviderAdapter {
	return []ProviderAdapter{
		StandardAnthropic{},
		StandardOpenAI{},
		NewMinimax(),
		NewDeepSeek(),
		NewQwen(),
		NewDoubao(),
		NewMoonshot(),
		NewZhipu(),
	}
}
