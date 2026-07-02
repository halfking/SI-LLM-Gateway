package adapter

import (
	"encoding/json"
	"testing"

	"github.com/kaixuan/llm-gateway-go/internal/ir"
)

// TestMiniMax_FullToolCallingRoundTrip simulates a complete tool calling
// conversation with MiniMax:
//   1. User asks question requiring a tool
//   2. MiniMax responds with tool_use
//   3. Client executes tool and sends tool result
//   4. MiniMax receives tool_call_id and generates final response
//
// This test verifies the COMPLETE bidirectional flow.
func TestMiniMax_FullToolCallingRoundTrip(t *testing.T) {
	factory := NewFactory()

	// ─── Step 1: User request ───────────────────────────────────────────────
	// OpenAI client sends: "What's the weather in Tokyo?"
	userRequest := []byte(`{
		"model": "abab6.5s-chat",
		"max_tokens": 1024,
		"messages": [
			{"role": "user", "content": "What's the weather in Tokyo?"}
		],
		"tools": [
			{
				"type": "function",
				"function": {
					"name": "get_weather",
					"description": "Get current weather for a city",
					"parameters": {
						"type": "object",
						"properties": {
							"city": {"type": "string"}
						},
						"required": ["city"]
					}
				}
			}
		]
	}`)

	// Parse and adapt
	irReq, err := ir.ParseOpenAI(userRequest)
	if err != nil {
		t.Fatalf("ParseOpenAI: %v", err)
	}

	pa := factory.GetOrDefault("minimax", "anthropic-messages")
	irReq, err = pa.AdaptRequest(irReq)
	if err != nil {
		t.Fatalf("AdaptRequest: %v", err)
	}

	// Serialize to MiniMax (Anthropic format with tool_call_id support)
	upstreamBody, err := ir.SerializeAnthropic(irReq)
	if err != nil {
		t.Fatalf("SerializeAnthropic: %v", err)
	}

	// Verify the request going to MiniMax has tools
	var upstreamReq map[string]any
	json.Unmarshal(upstreamBody, &upstreamReq)
	if upstreamReq["tools"] == nil {
		t.Error("tools field missing in upstream request")
	}

	// ─── Step 2: MiniMax responds with tool_use ────────────────────────────
	// Simulate MiniMax response (Anthropic format)
	minimaxResponse := []byte(`{
		"id": "msg_123",
		"type": "message",
		"role": "assistant",
		"content": [
			{
				"type": "tool_use",
				"id": "toolu_abc123",
				"name": "get_weather",
				"input": {"city": "Tokyo"}
			}
		],
		"model": "abab6.5s-chat",
		"stop_reason": "tool_use",
		"usage": {"input_tokens": 100, "output_tokens": 50}
	}`)

	// Parse MiniMax response
	irResp, err := ir.ParseAnthropicResponse(minimaxResponse)
	if err != nil {
		t.Fatalf("ParseAnthropicResponse: %v", err)
	}

	// Verify tool_use was parsed
	if len(irResp.ToolCalls) == 0 {
		t.Fatal("no tool calls in parsed response")
	}
	if irResp.ToolCalls[0].ID != "toolu_abc123" {
		t.Errorf("tool call ID = %q, want 'toolu_abc123'", irResp.ToolCalls[0].ID)
	}

	// ─── Step 3: Client executes tool and sends result ─────────────────────
	// OpenAI client sends tool result
	toolResultRequest := []byte(`{
		"model": "abab6.5s-chat",
		"max_tokens": 1024,
		"messages": [
			{"role": "user", "content": "What's the weather in Tokyo?"},
			{
				"role": "assistant",
				"tool_calls": [
					{
						"id": "toolu_abc123",
						"type": "function",
						"function": {
							"name": "get_weather",
							"arguments": "{\"city\":\"Tokyo\"}"
						}
					}
				]
			},
			{
				"role": "tool",
				"tool_call_id": "toolu_abc123",
				"content": "Sunny, 25°C"
			}
		]
	}`)

	// Parse and adapt
	irReq2, err := ir.ParseOpenAI(toolResultRequest)
	if err != nil {
		t.Fatalf("ParseOpenAI (tool result): %v", err)
	}

	irReq2, err = pa.AdaptRequest(irReq2)
	if err != nil {
		t.Fatalf("AdaptRequest (tool result): %v", err)
	}

	// Serialize to MiniMax
	upstreamBody2, err := ir.SerializeAnthropic(irReq2)
	if err != nil {
		t.Fatalf("SerializeAnthropic (tool result): %v", err)
	}

	// ─── Step 4: Verify tool_call_id is sent to MiniMax ────────────────────
	var upstreamReq2 map[string]any
	json.Unmarshal(upstreamBody2, &upstreamReq2)

	messages := upstreamReq2["messages"].([]any)
	foundToolResult := false
	for _, msg := range messages {
		msgMap := msg.(map[string]any)
		content, ok := msgMap["content"].([]any)
		if !ok {
			continue
		}
		for _, block := range content {
			blockMap, ok := block.(map[string]any)
			if !ok {
				continue
			}
			if blockMap["type"] == "tool_result" {
				foundToolResult = true

				// CRITICAL: MiniMax MUST receive tool_call_id, not tool_use_id
				if _, hasOld := blockMap["tool_use_id"]; hasOld {
					t.Error("FAIL: found tool_use_id (MiniMax will reject this)")
				}
				if id, ok := blockMap["tool_call_id"].(string); !ok || id != "toolu_abc123" {
					t.Errorf("FAIL: tool_call_id = %v, want 'toolu_abc123'", blockMap["tool_call_id"])
				} else {
					t.Logf("✓ SUCCESS: tool_call_id correctly set to %q", id)
				}

				// Verify content is present
				if blockMap["content"] == nil {
					t.Error("FAIL: tool_result missing content")
				}
			}
		}
	}

	if !foundToolResult {
		t.Fatal("FAIL: no tool_result block found in serialized output")
	}

	t.Log("✓ Full tool calling round-trip validated successfully")
}

// TestMiniMax_VerifyTargetProviderIsSet ensures that the Minimax adapter
// sets TargetProvider correctly, which is what triggers tool_call_id output.
func TestMiniMax_VerifyTargetProviderIsSet(t *testing.T) {
	m := NewMinimax()

	req := &ir.InternalRequest{Model: "abab6.5s-chat"}
	adapted, err := m.AdaptRequest(req)
	if err != nil {
		t.Fatalf("AdaptRequest: %v", err)
	}

	if adapted.TargetProvider != "minimax" {
		t.Errorf("TargetProvider = %q, want 'minimax'", adapted.TargetProvider)
	}

	// When TargetProvider="minimax", SerializeAnthropic should output tool_call_id
	adapted.Messages = []ir.Message{
		{Role: "tool", ToolCallID: "call_xyz", Content: []ir.ContentBlock{{Type: "text", Text: "result"}}},
	}

	body, err := ir.SerializeAnthropic(adapted)
	if err != nil {
		t.Fatalf("SerializeAnthropic: %v", err)
	}

	// Verify tool_call_id is in the output
	if !contains(body, []byte("tool_call_id")) {
		t.Error("SerializeAnthropic output missing 'tool_call_id' for MiniMax")
	}
	if contains(body, []byte("tool_use_id")) {
		t.Error("SerializeAnthropic output incorrectly contains 'tool_use_id' for MiniMax")
	}
}

// contains checks if haystack contains needle (simple byte search)
func contains(haystack, needle []byte) bool {
	for i := 0; i <= len(haystack)-len(needle); i++ {
		match := true
		for j := 0; j < len(needle); j++ {
			if haystack[i+j] != needle[j] {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}
