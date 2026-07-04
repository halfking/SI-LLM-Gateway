package adapter

import (
	"encoding/json"
	"fmt"

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

func (m *Minimax) Name() string           { return "minimax" }
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
	body = ensureToolCallID(body)

	// Validate tool call integrity on the serialized body before sending upstream.
	// This catches orphaned tool results (Bug #2) that weren't caught by the IR layer.
	if len(req.Messages) > 2 {
		if err := validateMinimaxToolCallIntegrity(body); err != nil {
			return nil, fmt.Errorf("tool_call validation failed: %w", err)
		}
	}

	return body, nil
}

func (m *Minimax) ParseResponse(body []byte) (*ir.InternalResponse, error) {
	// ir.ParseAnthropicResponse already handles tool_call_id fallback
	// (we added that in parse_anthropic.go). No extra work needed.
	return m.StandardAnthropic.ParseResponse(body)
}

func (m *Minimax) GetCapabilities() Capabilities {
	return Capabilities{
		SupportsToolCalling:  true,
		SupportsStreaming:    true,
		SupportsVision:       true,
		SupportsThinking:     false, // MiniMax packs reasoning in <think> tags, not native
		SupportsCacheControl: false,
		MaxTokens:            8192,
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

// validateMinimaxToolCallIntegrity checks all tool_result blocks have matching
// tool_use IDs. This operates on the final serialized JSON body (after ensureToolCallID).
// It handles both OpenAI format (tool_calls array at message level) and Anthropic format
// (tool_use blocks in content array).
func validateMinimaxToolCallIntegrity(body []byte) error {
	var raw map[string]any
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil // not JSON — skip validation
	}
	messages, ok := raw["messages"].([]any)
	if !ok || len(messages) <= 2 {
		return nil // not enough messages to validate
	}

	// Collect all tool_use IDs from assistant messages
	toolUseIDs := make(map[string]bool)
	for _, msg := range messages {
		msgMap, ok := msg.(map[string]any)
		if !ok {
			continue
		}
		role, _ := msgMap["role"].(string)
		if role != "assistant" {
			continue
		}

		// Check OpenAI format: tool_calls array at message level
		toolCalls, ok := msgMap["tool_calls"].([]any)
		if ok {
			for _, tc := range toolCalls {
				tcMap, ok := tc.(map[string]any)
				if !ok {
					continue
				}
				if id, ok := tcMap["id"].(string); ok && id != "" {
					toolUseIDs[id] = true
				}
			}
		}

		// Check Anthropic format: tool_use blocks in content array
		content, ok := msgMap["content"].([]any)
		if ok {
			for _, block := range content {
				blockMap, ok := block.(map[string]any)
				if !ok {
					continue
				}
				if blockMap["type"] == "tool_use" {
					if id, ok := blockMap["id"].(string); ok && id != "" {
						toolUseIDs[id] = true
					}
				}
			}
		}
	}

	// Check all tool_result blocks have matching tool_use ID
	var orphanedIDs []string
	for _, msg := range messages {
		msgMap, ok := msg.(map[string]any)
		if !ok {
			continue
		}
		role, _ := msgMap["role"].(string)

		// In Anthropic format, tool results can be in "user" role messages
		// (after ir.SerializeAnthropic converts tool role to user)
		if role != "tool" && role != "user" {
			continue
		}

		// Check message-level tool_call_id (OpenAI format, if present)
		if id, ok := msgMap["tool_call_id"].(string); ok && id != "" {
			if !toolUseIDs[id] {
				orphanedIDs = append(orphanedIDs, id)
			}
		}

		// Check content-level tool_result blocks (Anthropic format)
		content, ok := msgMap["content"].([]any)
		if ok {
			for _, block := range content {
				blockMap, ok := block.(map[string]any)
				if !ok {
					continue
				}
				if blockMap["type"] != "tool_result" {
					continue
				}
				// Check both tool_use_id (standard) and tool_call_id (after ensureToolCallID)
				id, _ := blockMap["tool_call_id"].(string)
				if id == "" {
					id, _ = blockMap["tool_use_id"].(string)
				}
				if id != "" && !toolUseIDs[id] {
					orphanedIDs = append(orphanedIDs, id)
				}
			}
		}
	}

	if len(orphanedIDs) > 0 {
		limit := 3
		if len(orphanedIDs) < limit {
			limit = len(orphanedIDs)
		}
		return fmt.Errorf("found %d orphaned tool result(s) without matching assistant tool_use: %v (likely client bug: assistant messages with tool_use were removed during context compression)",
			len(orphanedIDs), orphanedIDs[:limit])
	}

	return nil
}
