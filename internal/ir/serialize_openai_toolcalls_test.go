package ir

import (
	"encoding/json"
	"testing"
)

// TestSerializeOpenAI_EmptyContentWithToolCalls tests the bug fix where
// assistant messages with empty Content but non-empty ToolCalls were not
// serializing the tool_calls field.
func TestSerializeOpenAI_EmptyContentWithToolCalls(t *testing.T) {
	req := &InternalRequest{
		Model: "gpt-4",
		Messages: []Message{
			{
				Role:    "user",
				Content: []ContentBlock{{Type: "text", Text: "Run a command"}},
			},
			{
				Role:    "assistant",
				Content: []ContentBlock{}, // Empty content
				ToolCalls: []ToolCall{
					{
						ID:   "call_abc123",
						Type: "function",
						Function: struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						}{
							Name:      "bash",
							Arguments: `{"command":"ls"}`,
						},
					},
				},
			},
			{
				Role:       "tool",
				ToolCallID: "call_abc123",
				Content:    []ContentBlock{{Type: "text", Text: "file1.txt\nfile2.txt"}},
			},
		},
	}

	body, err := SerializeOpenAI(req)
	if err != nil {
		t.Fatalf("SerializeOpenAI failed: %v", err)
	}

	// Parse the output
	var output struct {
		Messages []map[string]any `json:"messages"`
	}
	if err := json.Unmarshal(body, &output); err != nil {
		t.Fatalf("Failed to unmarshal output: %v", err)
	}

	if len(output.Messages) != 3 {
		t.Fatalf("Expected 3 messages, got %d", len(output.Messages))
	}

	// Check the assistant message (index 1)
	assistantMsg := output.Messages[1]

	// Debug: print the full message
	t.Logf("Assistant message: %+v", assistantMsg)

	// Verify role
	if role, ok := assistantMsg["role"].(string); !ok || role != "assistant" {
		t.Errorf("Expected role=assistant, got %v", assistantMsg["role"])
	}

	// Verify content exists (should be empty string)
	if _, ok := assistantMsg["content"]; !ok {
		t.Errorf("Missing content field in assistant message")
	}

	// Verify tool_calls exists and is not empty
	toolCalls, ok := assistantMsg["tool_calls"]
	if !ok {
		t.Fatalf("❌ BUG: Missing tool_calls field in assistant message with empty content")
	}

	t.Logf("tool_calls value: %+v (type: %T)", toolCalls, toolCalls)

	toolCallsArray, ok := toolCalls.([]any)
	if !ok {
		// Try as []map[string]any
		toolCallsMap, ok2 := toolCalls.([]map[string]any)
		if !ok2 {
			t.Fatalf("❌ BUG: tool_calls is not a valid array (type: %T)", toolCalls)
		}
		if len(toolCallsMap) == 0 {
			t.Fatalf("❌ BUG: tool_calls array is empty")
		}
		// Convert to []any for uniform handling
		toolCallsArray = make([]any, len(toolCallsMap))
		for i, v := range toolCallsMap {
			toolCallsArray[i] = v
		}
	}

	if len(toolCallsArray) == 0 {
		t.Fatalf("❌ BUG: tool_calls array is empty")
	}

	// Verify the tool_call ID
	firstCall, ok := toolCallsArray[0].(map[string]any)
	if !ok {
		t.Fatalf("First tool_call is not a map: %T", toolCallsArray[0])
	}

	if firstCall["id"] != "call_abc123" {
		t.Errorf("Expected tool_call id=call_abc123, got %v", firstCall["id"])
	}

	// Check the tool message (index 2)
	toolMsg := output.Messages[2]

	if role, ok := toolMsg["role"].(string); !ok || role != "tool" {
		t.Errorf("Expected role=tool, got %v", toolMsg["role"])
	}

	if toolCallID, ok := toolMsg["tool_call_id"].(string); !ok || toolCallID != "call_abc123" {
		t.Errorf("Expected tool_call_id=call_abc123, got %v", toolMsg["tool_call_id"])
	}

	t.Logf("✓ Assistant message correctly includes tool_calls even with empty content")
	t.Logf("✓ Tool message references the correct tool_call_id")
}

// TestSerializeOpenAI_MultipleToolCallsWithEmptyContent tests multiple tool calls
func TestSerializeOpenAI_MultipleToolCallsWithEmptyContent(t *testing.T) {
	req := &InternalRequest{
		Model: "gpt-4",
		Messages: []Message{
			{
				Role:    "user",
				Content: []ContentBlock{{Type: "text", Text: "Run multiple commands"}},
			},
			{
				Role:    "assistant",
				Content: []ContentBlock{}, // Empty content
				ToolCalls: []ToolCall{
					{
						ID:   "call_001",
						Type: "function",
						Function: struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						}{
							Name:      "bash",
							Arguments: `{"command":"ls"}`,
						},
					},
					{
						ID:   "call_002",
						Type: "function",
						Function: struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						}{
							Name:      "bash",
							Arguments: `{"command":"pwd"}`,
						},
					},
				},
			},
			{
				Role:       "tool",
				ToolCallID: "call_001",
				Content:    []ContentBlock{{Type: "text", Text: "file1.txt"}},
			},
			{
				Role:       "tool",
				ToolCallID: "call_002",
				Content:    []ContentBlock{{Type: "text", Text: "/home/user"}},
			},
		},
	}

	body, err := SerializeOpenAI(req)
	if err != nil {
		t.Fatalf("SerializeOpenAI failed: %v", err)
	}

	var output struct {
		Messages []map[string]any `json:"messages"`
	}
	if err := json.Unmarshal(body, &output); err != nil {
		t.Fatalf("Failed to unmarshal output: %v", err)
	}

	// Check assistant message has 2 tool_calls
	assistantMsg := output.Messages[1]

	t.Logf("Assistant message: %+v", assistantMsg)

	toolCalls, ok := assistantMsg["tool_calls"]
	if !ok {
		t.Fatalf("Missing tool_calls in assistant message")
	}

	toolCallsArray, ok := toolCalls.([]any)
	if !ok {
		t.Fatalf("tool_calls is not []any, got type %T", toolCalls)
	}

	if len(toolCallsArray) != 2 {
		t.Fatalf("Expected 2 tool_calls, got %d: %v", len(toolCallsArray), toolCallsArray)
	}

	// Verify tool_call IDs
	firstCall, _ := toolCallsArray[0].(map[string]any)
	secondCall, _ := toolCallsArray[1].(map[string]any)

	if firstCall["id"] != "call_001" {
		t.Errorf("Expected first tool_call id=call_001, got %v", firstCall["id"])
	}
	if secondCall["id"] != "call_002" {
		t.Errorf("Expected second tool_call id=call_002, got %v", secondCall["id"])
	}

	t.Logf("✓ Multiple tool_calls correctly serialized with empty content")
}
