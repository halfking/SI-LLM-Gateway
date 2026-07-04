package ir

import (
	"strings"
	"testing"
)

// TestSerializeOpenAI_OrphanedToolResults tests that orphaned tool results
// (tool messages without matching assistant tool_calls) are detected and rejected.
func TestSerializeOpenAI_OrphanedToolResults(t *testing.T) {
	req := &InternalRequest{
		Model: "gpt-4",
		Messages: []Message{
			{
				Role:    "user",
				Content: []ContentBlock{{Type: "text", Text: "Run commands"}},
			},
			// Missing: assistant message with tool_calls
			// This simulates client bug where assistant tool_calls were removed
			{
				Role:       "tool",
				ToolCallID: "call_orphaned_001",
				Content:    []ContentBlock{{Type: "text", Text: "Result 1"}},
			},
			{
				Role:       "tool",
				ToolCallID: "call_orphaned_002",
				Content:    []ContentBlock{{Type: "text", Text: "Result 2"}},
			},
		},
	}

	_, err := SerializeOpenAI(req)

	if err == nil {
		t.Fatal("Expected error for orphaned tool results, got nil")
	}

	errMsg := err.Error()
	if !strings.Contains(errMsg, "orphaned tool result") {
		t.Errorf("Expected error message to mention 'orphaned tool result', got: %s", errMsg)
	}

	if !strings.Contains(errMsg, "call_orphaned_001") {
		t.Errorf("Expected error message to include orphaned ID, got: %s", errMsg)
	}

	t.Logf("✓ Correctly rejected orphaned tool results: %s", errMsg)
}

// TestSerializeOpenAI_ValidToolCalls tests that valid tool calls pass validation.
func TestSerializeOpenAI_ValidToolCalls(t *testing.T) {
	req := &InternalRequest{
		Model: "gpt-4",
		Messages: []Message{
			{
				Role:    "user",
				Content: []ContentBlock{{Type: "text", Text: "Run a command"}},
			},
			{
				Role:    "assistant",
				Content: []ContentBlock{},
				ToolCalls: []ToolCall{
					{
						ID:   "call_valid_001",
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
				ToolCallID: "call_valid_001",
				Content:    []ContentBlock{{Type: "text", Text: "file1.txt"}},
			},
		},
	}

	body, err := SerializeOpenAI(req)
	if err != nil {
		t.Fatalf("Valid tool calls should not error: %v", err)
	}

	if len(body) == 0 {
		t.Fatal("Expected non-empty body")
	}

	t.Logf("✓ Valid tool calls passed validation")
}

// TestSerializeOpenAI_PartialOrphans tests mixed case: some valid, some orphaned.
func TestSerializeOpenAI_PartialOrphans(t *testing.T) {
	req := &InternalRequest{
		Model: "gpt-4",
		Messages: []Message{
			{
				Role:    "user",
				Content: []ContentBlock{{Type: "text", Text: "Task 1"}},
			},
			{
				Role:    "assistant",
				Content: []ContentBlock{},
				ToolCalls: []ToolCall{
					{
						ID:   "call_valid_001",
						Type: "function",
						Function: struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						}{
							Name:      "bash",
							Arguments: `{}`,
						},
					},
				},
			},
			{
				Role:       "tool",
				ToolCallID: "call_valid_001",
				Content:    []ContentBlock{{Type: "text", Text: "OK"}},
			},
			// This one is orphaned (assistant was removed by client)
			{
				Role:       "tool",
				ToolCallID: "call_orphaned_002",
				Content:    []ContentBlock{{Type: "text", Text: "Orphaned"}},
			},
		},
	}

	_, err := SerializeOpenAI(req)

	if err == nil {
		t.Fatal("Expected error for partially orphaned tool results, got nil")
	}

	errMsg := err.Error()
	if !strings.Contains(errMsg, "call_orphaned_002") {
		t.Errorf("Expected error to mention orphaned ID call_orphaned_002, got: %s", errMsg)
	}

	t.Logf("✓ Correctly detected partial orphans: %s", errMsg)
}
