package transform

import (
	"encoding/json"
	"fmt"
	"testing"
)

// TestTrimOldestPairs_ToolCallOrphaning tests the bug where tool results
// are left orphaned after trimming removes their matching assistant tool_calls.
func TestTrimOldestPairs_ToolCallOrphaning(t *testing.T) {
	// Simulate a long conversation with multiple tool rounds
	messages := []json.RawMessage{
		// System message (always preserved)
		json.RawMessage(`{"role":"system","content":"You are helpful"}`),

		// User message 1
		json.RawMessage(`{"role":"user","content":"Do task 1"}`),
		// Assistant with tool_call
		json.RawMessage(`{"role":"assistant","content":"","tool_calls":[{"id":"call_001","type":"function","function":{"name":"bash","arguments":"{}"}}]}`),
		// Tool result
		json.RawMessage(`{"role":"tool","tool_call_id":"call_001","content":"Result 1"}`),

		// User message 2
		json.RawMessage(`{"role":"user","content":"Do task 2"}`),
		// Assistant with tool_call
		json.RawMessage(`{"role":"assistant","content":"","tool_calls":[{"id":"call_002","type":"function","function":{"name":"bash","arguments":"{}"}}]}`),
		// Tool result
		json.RawMessage(`{"role":"tool","tool_call_id":"call_002","content":"Result 2"}`),

		// User message 3
		json.RawMessage(`{"role":"user","content":"Do task 3"}`),
		// Assistant with tool_call
		json.RawMessage(`{"role":"assistant","content":"","tool_calls":[{"id":"call_003","type":"function","function":{"name":"bash","arguments":"{}"}}]}`),
		// Tool result
		json.RawMessage(`{"role":"tool","tool_call_id":"call_003","content":"Result 3"}`),

		// Final user message (should be kept)
		json.RawMessage(`{"role":"user","content":"Summarize everything"}`),
	}

	// Set a very low soft limit to force aggressive trimming
	softLimit := 50 // Very low to trigger multiple rounds of dropping

	trimmed := trimOldestPairs(messages, softLimit)

	fmt.Printf("=== Original messages: %d ===\n", len(messages))
	for i, msg := range messages {
		fmt.Printf("%d: %s\n", i, string(msg[:min(80, len(msg))]))
	}

	fmt.Printf("\n=== Trimmed messages: %d ===\n", len(trimmed))
	for i, msg := range trimmed {
		fmt.Printf("%d: %s\n", i, string(msg[:min(80, len(msg))]))
	}

	// Validate: no orphaned tool results
	fmt.Printf("\n=== Validation ===\n")
	toolCallIDs := make(map[string]bool)

	// First pass: collect all tool_call IDs from assistant messages
	for i, msg := range trimmed {
		var probe struct {
			Role      string `json:"role"`
			ToolCalls []struct {
				ID string `json:"id"`
			} `json:"tool_calls"`
		}
		if err := json.Unmarshal(msg, &probe); err == nil && probe.Role == "assistant" {
			for _, tc := range probe.ToolCalls {
				if tc.ID != "" {
					toolCallIDs[tc.ID] = true
					fmt.Printf("Message %d: Found tool_call ID: %s\n", i, tc.ID)
				}
			}
		}
	}

	// Second pass: check all tool results have matching tool_calls
	orphanCount := 0
	for i, msg := range trimmed {
		var probe struct {
			Role       string `json:"role"`
			ToolCallID string `json:"tool_call_id"`
		}
		if err := json.Unmarshal(msg, &probe); err == nil && probe.Role == "tool" {
			if probe.ToolCallID == "" {
				fmt.Printf("Message %d: ERROR - tool message without tool_call_id\n", i)
				orphanCount++
			} else if !toolCallIDs[probe.ToolCallID] {
				fmt.Printf("Message %d: ERROR - Orphaned tool result with ID: %s (no matching assistant tool_call)\n", i, probe.ToolCallID)
				orphanCount++
				t.Errorf("Orphaned tool result at index %d with tool_call_id=%s", i, probe.ToolCallID)
			} else {
				fmt.Printf("Message %d: OK - tool_call_id %s has matching assistant\n", i, probe.ToolCallID)
			}
		}
	}

	if orphanCount > 0 {
		t.Errorf("Found %d orphaned tool results", orphanCount)
	} else {
		fmt.Printf("\n✓ No orphaned tool results found\n")
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
