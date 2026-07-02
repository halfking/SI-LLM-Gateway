package adapter

import (
	"encoding/json"
	"testing"

	"github.com/kaixuan/llm-gateway-go/internal/ir"
)

// End-to-end tests that verify the full pipeline:
//   Client Request (JSON)
//     → IR.ParseOpenAI
//     → Adapter.AdaptRequest
//     → IR.SerializeAnthropic / SerializeOpenAI
//     → Provider Wire Format (JSON)
//
// These tests simulate the exact flow that routing/executor_anthropic.go
// and routing/executor_chat.go perform at runtime, ensuring the adapter
// framework correctly transforms requests for each provider.

// ─── Helper: simulate the Q3 path (OpenAI client → Anthropic upstream) ────

// simulateQ3Path mirrors what executor_anthropic.go does:
//  1. ParseOpenAI (client body → IR)
//  2. AdapterFactory.GetOrDefault → adapter
//  3. adapter.AdaptRequest (IR → adapted IR)
//  4. IR.SerializeAnthropic (adapted IR → Anthropic body)
func simulateQ3Path(t *testing.T, factory *Factory, catalogCode, protocol string, clientBody []byte) []byte {
	t.Helper()

	// Step 1: Parse client request (OpenAI format)
	irReq, err := ir.ParseOpenAI(clientBody)
	if err != nil {
		t.Fatalf("ParseOpenAI failed: %v", err)
	}

	// Step 2: Get adapter
	pa := factory.GetOrDefault(catalogCode, protocol)

	// Step 3: Adapt request
	irReq, err = pa.AdaptRequest(irReq)
	if err != nil {
		t.Fatalf("AdaptRequest failed: %v", err)
	}

	// Step 4: Serialize to Anthropic format
	body, err := ir.SerializeAnthropic(irReq)
	if err != nil {
		t.Fatalf("SerializeAnthropic failed: %v", err)
	}

	return body
}

// ─── Helper: simulate the Q2 path (Anthropic client → OpenAI upstream) ────

func simulateQ2Path(t *testing.T, factory *Factory, catalogCode, protocol string, clientBody []byte) []byte {
	t.Helper()

	irReq, err := ir.ParseAnthropic(clientBody)
	if err != nil {
		t.Fatalf("ParseAnthropic failed: %v", err)
	}

	pa := factory.GetOrDefault(catalogCode, protocol)
	irReq, err = pa.AdaptRequest(irReq)
	if err != nil {
		t.Fatalf("AdaptRequest failed: %v", err)
	}

	body, err := ir.SerializeOpenAI(irReq)
	if err != nil {
		t.Fatalf("SerializeOpenAI failed: %v", err)
	}

	return body
}

// ─── Q3: MiniMax full pipeline ─────────────────────────────────────────────

// TestE2E_MiniMax_Q3_ToolCalling verifies the complete MiniMax tool calling
// pipeline: OpenAI client sends a tool result, the adapter + IR convert it
// to Anthropic format with tool_call_id (not tool_use_id).
func TestE2E_MiniMax_Q3_ToolCalling(t *testing.T) {
	factory := NewFactory()

	// Simulate an OpenAI-format request with a tool result
	clientBody := []byte(`{
		"model": "abab6.5s-chat",
		"max_tokens": 1024,
		"messages": [
			{"role": "user", "content": "What's the weather?"},
			{"role": "assistant", "tool_calls": [{"id": "call_abc123", "type": "function", "function": {"name": "get_weather", "arguments": "{\"city\":\"Tokyo\"}"}}]},
			{"role": "tool", "tool_call_id": "call_abc123", "content": "Sunny, 72°F"}
		]
	}`)

	result := simulateQ3Path(t, factory, "minimax", "anthropic-messages", clientBody)

	// Verify the serialized Anthropic body uses tool_call_id for MiniMax
	var body map[string]any
	if err := json.Unmarshal(result, &body); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}

	messages := body["messages"].([]any)
	if len(messages) < 3 {
		t.Fatalf("expected at least 3 messages, got %d", len(messages))
	}

	// The tool result message (role "tool" in OpenAI → "user"+tool_result in Anthropic)
	// Find the message with tool_result content
	var foundToolResult bool
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
				// MiniMax must use tool_call_id, not tool_use_id
				if _, hasOld := blockMap["tool_use_id"]; hasOld {
					t.Error("found tool_use_id — MiniMax should use tool_call_id")
				}
				if id, ok := blockMap["tool_call_id"].(string); !ok || id != "call_abc123" {
					t.Errorf("tool_call_id = %v, want 'call_abc123'", blockMap["tool_call_id"])
				}
			}
		}
	}
	if !foundToolResult {
		t.Error("no tool_result block found in serialized output")
	}
}

// TestE2E_MiniMax_Q3_NoToolCalling verifies that non-tool requests pass through
// the MiniMax adapter unchanged (no false positives).
func TestE2E_MiniMax_Q3_NoToolCalling(t *testing.T) {
	factory := NewFactory()

	clientBody := []byte(`{
		"model": "abab6.5s-chat",
		"max_tokens": 256,
		"messages": [
			{"role": "user", "content": "Hello, world!"}
		]
	}`)

	result := simulateQ3Path(t, factory, "minimax", "anthropic-messages", clientBody)

	var body map[string]any
	json.Unmarshal(result, &body)

	// Should be a valid Anthropic body
	if body["model"] != "abab6.5s-chat" {
		t.Errorf("model = %v, want 'abab6.5s-chat'", body["model"])
	}
	if body["max_tokens"] != float64(256) {
		t.Errorf("max_tokens = %v, want 256", body["max_tokens"])
	}
}

// ─── Q3: DeepSeek full pipeline ────────────────────────────────────────────

func TestE2E_DeepSeek_Q3_MaxTokensClamp(t *testing.T) {
	factory := NewFactory()

	// DeepSeek uses OpenAI protocol (not anthropic-messages), so the Q3 path
	// wouldn't normally apply. But we test the adapter directly here.
	pa := factory.GetOrDefault("deepseek", "openai-completions")

	clientBody := []byte(`{
		"model": "deepseek-chat",
		"max_tokens": 50000,
		"messages": [{"role": "user", "content": "hi"}]
	}`)

	irReq, err := ir.ParseOpenAI(clientBody)
	if err != nil {
		t.Fatalf("ParseOpenAI: %v", err)
	}

	adapted, err := pa.AdaptRequest(irReq)
	if err != nil {
		t.Fatalf("AdaptRequest: %v", err)
	}

	if adapted.MaxTokens != 8192 {
		t.Errorf("MaxTokens = %d, want 8192 (DeepSeek limit)", adapted.MaxTokens)
	}
}

// ─── Q2: Anthropic client → OpenAI upstream (Doubao) ──────────────────────

func TestE2E_Doubao_Q2_TemperatureClamp(t *testing.T) {
	factory := NewFactory()

	// Anthropic-format client request targeting Doubao (OpenAI upstream)
	clientBody := []byte(`{
		"model": "doubao-pro-4k",
		"max_tokens": 2000,
		"temperature": 1.5,
		"messages": [{"role": "user", "content": "hi"}]
	}`)

	result := simulateQ2Path(t, factory, "doubao", "openai-completions", clientBody)

	var body map[string]any
	json.Unmarshal(result, &body)

	// Temperature should be clamped to 1.0
	temp, ok := body["temperature"].(float64)
	if !ok {
		t.Fatal("expected temperature field in output")
	}
	if temp != 1.0 {
		t.Errorf("temperature = %f, want 1.0 (clamped from 1.5)", temp)
	}

	// max_tokens should be clamped to 4096
	if mt, ok := body["max_tokens"].(float64); !ok || mt != 2000 {
		// 2000 < 4096, so it should NOT be clamped
		if mt != 2000 {
			t.Errorf("max_tokens = %v, want 2000 (within Doubao limit)", body["max_tokens"])
		}
	}
}

// ─── Factory fallback: unknown provider ────────────────────────────────────

func TestE2E_UnknownProvider_FallsBackToStandard(t *testing.T) {
	factory := NewFactory()

	// An unknown provider should fall back to standard Anthropic
	pa := factory.GetOrDefault("some-new-vendor", "anthropic-messages")
	if pa.Name() != "anthropic" {
		t.Errorf("expected 'anthropic' fallback, got %q", pa.Name())
	}

	// And for OpenAI protocol, it should fall back to standard OpenAI
	pa2 := factory.GetOrDefault("some-new-vendor", "openai-completions")
	if pa2.Name() != "openai" {
		t.Errorf("expected 'openai' fallback, got %q", pa2.Name())
	}
}

// ─── Multi-turn tool calling pipeline (MiniMax) ───────────────────────────

// TestE2E_MiniMax_MultiTurnToolCalling simulates a 3-message conversation
// with tool calls to ensure the adapter handles multi-round tool use.
func TestE2E_MiniMax_MultiTurnToolCalling(t *testing.T) {
	factory := NewFactory()

	clientBody := []byte(`{
		"model": "abab6.5s-chat",
		"max_tokens": 1024,
		"messages": [
			{"role": "user", "content": "What's the weather in Tokyo and Paris?"},
			{"role": "assistant", "tool_calls": [
				{"id": "call_001", "type": "function", "function": {"name": "get_weather", "arguments": "{\"city\":\"Tokyo\"}"}},
				{"id": "call_002", "type": "function", "function": {"name": "get_weather", "arguments": "{\"city\":\"Paris\"}"}}
			]},
			{"role": "tool", "tool_call_id": "call_001", "content": "Tokyo: Sunny, 25°C"},
			{"role": "tool", "tool_call_id": "call_002", "content": "Paris: Cloudy, 15°C"}
		]
	}`)

	result := simulateQ3Path(t, factory, "minimax", "anthropic-messages", clientBody)

	var body map[string]any
	json.Unmarshal(result, &body)

	messages := body["messages"].([]any)

	// Count tool_call_id occurrences (should be 2 — one per tool result)
	toolCallIDCount := 0
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
				if _, ok := blockMap["tool_call_id"]; ok {
					toolCallIDCount++
				}
			}
		}
	}

	if toolCallIDCount != 2 {
		t.Errorf("expected 2 tool_call_id occurrences, got %d", toolCallIDCount)
	}
}
