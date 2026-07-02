package ir

import (
	"encoding/json"
	"testing"
)

// TestParseAnthropic_MinimaxToolCallID tests that we correctly parse MiniMax's
// tool_call_id field (instead of standard tool_use_id) in tool_result blocks.
func TestParseAnthropic_MinimaxToolCallID(t *testing.T) {
	body := `{
		"model": "abab6.5s-chat",
		"max_tokens": 1024,
		"messages": [
			{
				"role": "user",
				"content": [
					{
						"type": "tool_result",
						"tool_call_id": "call_abc123",
						"content": "The weather is sunny"
					}
				]
			}
		]
	}`

	ir, err := ParseAnthropic([]byte(body))
	if err != nil {
		t.Fatalf("ParseAnthropic failed: %v", err)
	}

	if len(ir.Messages) != 1 {
		t.Fatalf("expected 1 message, got %d", len(ir.Messages))
	}

	msg := ir.Messages[0]
	if msg.Role != "user" {
		t.Errorf("expected role 'user', got %q", msg.Role)
	}

	if len(msg.Content) != 1 {
		t.Fatalf("expected 1 content block, got %d", len(msg.Content))
	}

	block := msg.Content[0]
	if block.Type != "tool_result" {
		t.Errorf("expected type 'tool_result', got %q", block.Type)
	}

	if block.ToolResult == nil {
		t.Fatal("expected ToolResult to be non-nil")
	}

	// The key test: tool_call_id should be parsed into ToolUseID
	if block.ToolResult.ToolUseID != "call_abc123" {
		t.Errorf("expected ToolUseID 'call_abc123', got %q", block.ToolResult.ToolUseID)
	}

	if len(block.ToolResult.Content) != 1 {
		t.Fatalf("expected 1 content block in tool_result, got %d", len(block.ToolResult.Content))
	}

	if block.ToolResult.Content[0].Type != "text" {
		t.Errorf("expected text content, got %q", block.ToolResult.Content[0].Type)
	}

	if block.ToolResult.Content[0].Text != "The weather is sunny" {
		t.Errorf("expected text 'The weather is sunny', got %q", block.ToolResult.Content[0].Text)
	}
}

// TestParseAnthropic_StandardToolUseID tests that we still correctly parse
// standard tool_use_id (for non-MiniMax providers).
func TestParseAnthropic_StandardToolUseID(t *testing.T) {
	body := `{
		"model": "claude-3-5-sonnet-20241022",
		"max_tokens": 1024,
		"messages": [
			{
				"role": "user",
				"content": [
					{
						"type": "tool_result",
						"tool_use_id": "toolu_xyz789",
						"content": "The weather is rainy"
					}
				]
			}
		]
	}`

	ir, err := ParseAnthropic([]byte(body))
	if err != nil {
		t.Fatalf("ParseAnthropic failed: %v", err)
	}

	if len(ir.Messages) != 1 {
		t.Fatalf("expected 1 message, got %d", len(ir.Messages))
	}

	msg := ir.Messages[0]
	if len(msg.Content) != 1 {
		t.Fatalf("expected 1 content block, got %d", len(msg.Content))
	}

	block := msg.Content[0]
	if block.ToolResult == nil {
		t.Fatal("expected ToolResult to be non-nil")
	}

	// Standard tool_use_id should still work
	if block.ToolResult.ToolUseID != "toolu_xyz789" {
		t.Errorf("expected ToolUseID 'toolu_xyz789', got %q", block.ToolResult.ToolUseID)
	}
}

// TestSerializeAnthropic_MinimaxToolCallID tests that we correctly serialize
// tool_call_id for MiniMax (instead of tool_use_id).
func TestSerializeAnthropic_MinimaxToolCallID(t *testing.T) {
	req := &InternalRequest{
		Model:          "abab6.5s-chat",
		MaxTokens:      1024,
		TargetProvider: "minimax",
		Messages: []Message{
			{
				Role:       "tool",
				ToolCallID: "call_abc123",
				Content: []ContentBlock{
					{
						Type: "text",
						Text: "The weather is sunny",
					},
				},
			},
		},
	}

	body, err := SerializeAnthropic(req)
	if err != nil {
		t.Fatalf("SerializeAnthropic failed: %v", err)
	}

	var result map[string]any
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("failed to unmarshal result: %v", err)
	}

	messages, ok := result["messages"].([]any)
	if !ok || len(messages) != 1 {
		t.Fatalf("expected 1 message in result")
	}

	msg := messages[0].(map[string]any)
	if msg["role"] != "user" {
		t.Errorf("expected role 'user', got %v", msg["role"])
	}

	content := msg["content"].([]any)
	if len(content) != 1 {
		t.Fatalf("expected 1 content block, got %d", len(content))
	}

	toolResult := content[0].(map[string]any)
	if toolResult["type"] != "tool_result" {
		t.Errorf("expected type 'tool_result', got %v", toolResult["type"])
	}

	// Key test: MiniMax should get tool_call_id, not tool_use_id
	if _, hasToolUseID := toolResult["tool_use_id"]; hasToolUseID {
		t.Error("expected no tool_use_id for MiniMax")
	}

	toolCallID, ok := toolResult["tool_call_id"].(string)
	if !ok {
		t.Fatal("expected tool_call_id for MiniMax")
	}

	if toolCallID != "call_abc123" {
		t.Errorf("expected tool_call_id 'call_abc123', got %q", toolCallID)
	}
}

// TestSerializeAnthropic_StandardToolUseID tests that we correctly serialize
// tool_use_id for standard Anthropic providers.
func TestSerializeAnthropic_StandardToolUseID(t *testing.T) {
	req := &InternalRequest{
		Model:          "claude-3-5-sonnet-20241022",
		MaxTokens:      1024,
		TargetProvider: "", // empty = standard Anthropic
		Messages: []Message{
			{
				Role:       "tool",
				ToolCallID: "toolu_xyz789",
				Content: []ContentBlock{
					{
						Type: "text",
						Text: "The weather is rainy",
					},
				},
			},
		},
	}

	body, err := SerializeAnthropic(req)
	if err != nil {
		t.Fatalf("SerializeAnthropic failed: %v", err)
	}

	var result map[string]any
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("failed to unmarshal result: %v", err)
	}

	messages := result["messages"].([]any)
	msg := messages[0].(map[string]any)
	content := msg["content"].([]any)
	toolResult := content[0].(map[string]any)

	// Standard Anthropic should get tool_use_id, not tool_call_id
	if _, hasToolCallID := toolResult["tool_call_id"]; hasToolCallID {
		t.Error("expected no tool_call_id for standard Anthropic")
	}

	toolUseID, ok := toolResult["tool_use_id"].(string)
	if !ok {
		t.Fatal("expected tool_use_id for standard Anthropic")
	}

	if toolUseID != "toolu_xyz789" {
		t.Errorf("expected tool_use_id 'toolu_xyz789', got %q", toolUseID)
	}
}
