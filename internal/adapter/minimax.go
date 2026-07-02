package adapter

import (
	"encoding/json"

	"github.com/kaixuan/llm-gateway-go/internal/ir"
)

// Minimax handles MiniMax's Anthropic-compatible endpoint quirks.
//
// Key difference from standard Anthropic:
//   - tool_result blocks use "tool_call_id" instead of "tool_use_id"
//   - Without this, MiniMax returns error 2013:
//     "invalid params, tool result's tool id(...) not found"
//
// The fix is a post-serialization body rewrite: after ir.SerializeAnthropic
// produces the standard body, we rename tool_use_id → tool_call_id in every
// tool_result block.
type Minimax struct {
	StandardAnthropic
}

// NewMinimax creates a MiniMax adapter.
func NewMinimax() *Minimax {
	return &Minimax{}
}

func (m *Minimax) Name() string         { return "minimax" }
func (m *Minimax) CatalogCodes() []string { return []string{"minimax"} }

func (m *Minimax) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
	// Mark the IR so ir.SerializeAnthropic emits tool_call_id directly.
	// This is the cleanest path: the serializer checks TargetProvider and
	// writes the right field, so no post-processing is needed.
	adapted := *req
	adapted.TargetProvider = "minimax"
	return &adapted, nil
}

func (m *Minimax) SerializeRequest(req *ir.InternalRequest) ([]byte, error) {
	body, err := m.StandardAnthropic.SerializeRequest(req)
	if err != nil {
		return nil, err
	}
	// Defensive double-check: if TargetProvider wasn't set (e.g., a caller
	// bypassed AdaptRequest), rewrite the field names in the serialized body.
	// This makes the adapter robust to direct SerializeRequest calls.
	return ensureToolCallID(body), nil
}

func (m *Minimax) ParseResponse(body []byte) (*ir.InternalResponse, error) {
	// ir.ParseAnthropicResponse already handles tool_call_id fallback
	// (we added that in parse_anthropic.go). No extra work needed.
	return m.StandardAnthropic.ParseResponse(body)
}

func (m *Minimax) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:   true,
		SupportsStreaming:     true,
		SupportsVision:        true,
		SupportsThinking:      false, // MiniMax packs reasoning in <think> tags, not native
		SupportsCacheControl:  false,
		MaxTokens:             8192,
		ToolIDField:          "tool_call_id", // MiniMax-specific
	}
}

// ensureToolCallID is a defensive body rewrite that converts any
// "tool_use_id" field inside a tool_result block to "tool_call_id".
// It operates on the raw serialized JSON so it works even when the IR
// serializer wasn't given TargetProvider.
//
// This is a no-op when the body has no tool_result blocks.
func ensureToolCallID(body []byte) []byte {
	var raw map[string]any
	if err := json.Unmarshal(body, &raw); err != nil {
		return body // not JSON — return as-is
	}
	messages, ok := raw["messages"].([]any)
	if !ok {
		return body // no messages — nothing to rewrite
	}
	changed := false
	for _, msg := range messages {
		msgMap, ok := msg.(map[string]any)
		if !ok {
			continue
		}
		changed = rewriteToolUseIDInMessage(msgMap) || changed
	}
	if !changed {
		return body
	}
	out, err := json.Marshal(raw)
	if err != nil {
		return body
	}
	return out
}

// rewriteToolUseIDInMessage renames tool_use_id → tool_call_id inside a
// message's content blocks. Returns true if any change was made.
func rewriteToolUseIDInMessage(msg map[string]any) bool {
	content, ok := msg["content"].([]any)
	if !ok {
		return false
	}
	changed := false
	for _, block := range content {
		blockMap, ok := block.(map[string]any)
		if !ok {
			continue
		}
		if blockMap["type"] != "tool_result" {
			continue
		}
		if id, exists := blockMap["tool_use_id"]; exists {
			blockMap["tool_call_id"] = id
			delete(blockMap, "tool_use_id")
			changed = true
		}
	}
	return changed
}
