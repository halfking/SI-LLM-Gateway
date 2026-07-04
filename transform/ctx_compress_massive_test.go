package transform

import (
	"encoding/json"
	"fmt"
	"testing"
)

// TestTrimOldestPairs_MassiveToolRounds tests trimming with many tool rounds
// similar to the production case (177 messages -> 50 messages).
func TestTrimOldestPairs_MassiveToolRounds(t *testing.T) {
	// Simulate a conversation similar to production:
	// 1 system + 82 assistant (81 with tool_calls) + 91 tool + 3 user = 177 messages
	messages := []json.RawMessage{
		json.RawMessage(`{"role":"system","content":"You are helpful"}`),
	}

	// Add 40 tool rounds (each: user -> assistant with tool_call -> tool result)
	for i := 1; i <= 40; i++ {
		messages = append(messages,
			json.RawMessage(fmt.Sprintf(`{"role":"user","content":"Task %d"}`, i)),
			json.RawMessage(fmt.Sprintf(`{"role":"assistant","content":"","tool_calls":[{"id":"call_%03d","type":"function","function":{"name":"bash","arguments":"{}"}}]}`, i)),
			json.RawMessage(fmt.Sprintf(`{"role":"tool","tool_call_id":"call_%03d","content":"Result %d"}`, i, i)),
		)
	}

	// Add final user message
	messages = append(messages,
		json.RawMessage(`{"role":"user","content":"Summarize everything"}`),
	)

	fmt.Printf("=== Original: %d messages ===\n", len(messages))
	fmt.Printf("Structure: 1 system + 40 tool rounds + 1 final user\n\n")

	// Trim aggressively to simulate 177 -> 50 compression
	softLimit := 200 // Will force dropping ~80% of messages

	trimmed := trimOldestPairs(messages, softLimit)

	fmt.Printf("=== Trimmed: %d messages (target ~50) ===\n\n", len(trimmed))

	// Print first few and last few messages
	fmt.Println("First 5 messages:")
	for i := 0; i < min(5, len(trimmed)); i++ {
		var probe struct {
			Role       string `json:"role"`
			ToolCallID string `json:"tool_call_id,omitempty"`
		}
		json.Unmarshal(trimmed[i], &probe)
		preview := string(trimmed[i])
		if len(preview) > 80 {
			preview = preview[:80] + "..."
		}
		fmt.Printf("  [%d] role=%s %s\n", i, probe.Role, preview)
	}

	fmt.Println("\nLast 5 messages:")
	start := max(0, len(trimmed)-5)
	for i := start; i < len(trimmed); i++ {
		var probe struct {
			Role       string `json:"role"`
			ToolCallID string `json:"tool_call_id,omitempty"`
		}
		json.Unmarshal(trimmed[i], &probe)
		preview := string(trimmed[i])
		if len(preview) > 80 {
			preview = preview[:80] + "..."
		}
		fmt.Printf("  [%d] role=%s %s\n", i, probe.Role, preview)
	}

	// Validate: no orphaned tool results
	fmt.Printf("\n=== Validation ===\n")
	toolCallIDs := make(map[string]bool)

	// First pass: collect all tool_call IDs from assistant messages
	for _, msg := range trimmed {
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
				}
			}
		}
	}

	fmt.Printf("Found %d assistant tool_call IDs\n", len(toolCallIDs))

	// Second pass: check all tool results have matching tool_calls
	orphanCount := 0
	toolResultCount := 0
	for i, msg := range trimmed {
		var probe struct {
			Role       string `json:"role"`
			ToolCallID string `json:"tool_call_id"`
		}
		if err := json.Unmarshal(msg, &probe); err == nil && probe.Role == "tool" {
			toolResultCount++
			if probe.ToolCallID == "" {
				fmt.Printf("  [%d] ERROR - tool message without tool_call_id\n", i)
				orphanCount++
			} else if !toolCallIDs[probe.ToolCallID] {
				fmt.Printf("  [%d] ERROR - Orphaned tool result: tool_call_id=%s (no matching assistant)\n", i, probe.ToolCallID)
				orphanCount++
				t.Errorf("Orphaned tool result at index %d with tool_call_id=%s", i, probe.ToolCallID)
			}
		}
	}

	fmt.Printf("Found %d tool result messages\n", toolResultCount)

	if orphanCount > 0 {
		t.Errorf("❌ Found %d orphaned tool results", orphanCount)
	} else {
		fmt.Printf("✓ No orphaned tool results\n")
	}

	// Check that we kept roughly equal numbers of tool_calls and tool results
	if toolResultCount > 0 && len(toolCallIDs) != toolResultCount {
		t.Errorf("❌ Mismatch: %d assistant tool_calls but %d tool results", len(toolCallIDs), toolResultCount)
	}
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
