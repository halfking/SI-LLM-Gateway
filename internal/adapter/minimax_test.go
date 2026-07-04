package adapter

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/kaixuan/llm-gateway-go/internal/ir"
)

// TestMinimax_SerializeRequest_ToolCallID verifies that the MiniMax adapter
// produces tool_call_id (not tool_use_id) in serialized tool_result blocks.
func TestMinimax_SerializeRequest_ToolCallID(t *testing.T) {
	m := NewMinimax()

	req := &ir.InternalRequest{
		Model: "abab6.5s-chat",
		Messages: []ir.Message{
			{
				Role:       "tool",
				ToolCallID: "call_abc123",
				Content: []ir.ContentBlock{
					{Type: "text", Text: "sunny, 72°F"},
				},
			},
		},
	}

	body, err := m.SerializeRequest(req)
	if err != nil {
		t.Fatalf("SerializeRequest failed: %v", err)
	}

	var result map[string]any
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	msgs := result["messages"].([]any)
	msg := msgs[0].(map[string]any)
	content := msg["content"].([]any)
	toolResult := content[0].(map[string]any)

	if _, hasToolUseID := toolResult["tool_use_id"]; hasToolUseID {
		t.Error("expected no tool_use_id for MiniMax")
	}
	if id, ok := toolResult["tool_call_id"].(string); !ok || id != "call_abc123" {
		t.Errorf("expected tool_call_id 'call_abc123', got %v", toolResult["tool_call_id"])
	}
}

// TestMinimax_AdaptRequest_SetsTargetProvider verifies that AdaptRequest
// stamps TargetProvider so the IR serializer knows to use tool_call_id.
func TestMinimax_AdaptRequest_SetsTargetProvider(t *testing.T) {
	m := NewMinimax()

	req := &ir.InternalRequest{Model: "abab6.5s-chat"}
	adapted, err := m.AdaptRequest(req)
	if err != nil {
		t.Fatalf("AdaptRequest failed: %v", err)
	}

	if adapted.TargetProvider != "minimax" {
		t.Errorf("expected TargetProvider 'minimax', got %q", adapted.TargetProvider)
	}
}

// TestFactory_GetOrDefault verifies the factory selects the right adapter
// by catalog code, with protocol-based fallback.
func TestFactory_GetOrDefault(t *testing.T) {
	f := NewFactory()

	// MiniMax by catalog code
	a, err := f.Get("minimax")
	if err != nil {
		t.Fatalf("expected minimax adapter, got error: %v", err)
	}
	if a.Name() != "minimax" {
		t.Errorf("expected 'minimax', got %q", a.Name())
	}

	// Unknown catalog code → fallback by protocol
	a2 := f.GetOrDefault("unknown-vendor", "anthropic-messages")
	if a2.Name() != "anthropic" {
		t.Errorf("expected 'anthropic' fallback, got %q", a2.Name())
	}

	a3 := f.GetOrDefault("unknown-vendor", "openai-completions")
	if a3.Name() != "openai" {
		t.Errorf("expected 'openai' fallback, got %q", a3.Name())
	}

	// Known catalog code overrides protocol fallback
	a4 := f.GetOrDefault("deepseek", "anthropic-messages")
	if a4.Name() != "deepseek" {
		t.Errorf("expected 'deepseek' (catalog wins), got %q", a4.Name())
	}
}

// TestFactory_AllAdaptersRegistered verifies all 8 built-in adapters exist.
func TestFactory_AllAdaptersRegistered(t *testing.T) {
	f := NewFactory()

	expected := []string{
		"anthropic", "openai", "minimax",
		"deepseek", "qwen", "doubao", "moonshot", "zhipu",
	}
	for _, name := range expected {
		a, err := f.Get(name)
		if err != nil {
			t.Errorf("expected adapter %q to be registered: %v", name, err)
			continue
		}
		if a.Name() != name {
			t.Errorf("adapter for %q returned name %q", name, a.Name())
		}
	}
}

// TestFactory_CatalogCodeAliases verifies catalog code aliases work
// (e.g., "kimi" → Moonshot, "glm" → Zhipu).
func TestFactory_CatalogCodeAliases(t *testing.T) {
	f := NewFactory()

	cases := map[string]string{
		"kimi":  "moonshot",
		"glm":   "zhipu",
		"qwen3": "qwen",
		"qwq":   "qwen",
	}
	for catalogCode, expectedAdapter := range cases {
		a, err := f.Get(catalogCode)
		if err != nil {
			t.Errorf("catalog code %q: %v", catalogCode, err)
			continue
		}
		if a.Name() != expectedAdapter {
			t.Errorf("catalog %q: expected adapter %q, got %q",
				catalogCode, expectedAdapter, a.Name())
		}
	}
}

// TestCapabilities_VerifyAllAdaptersHaveSensibleDefaults is a sanity check
// that every adapter returns non-zero capabilities.
func TestCapabilities_VerifyAllAdaptersHaveSensibleDefaults(t *testing.T) {
	f := NewFactory()
	for _, name := range f.Names() {
		a, _ := f.Get(name)
		caps := a.GetCapabilities()
		if caps.MaxTokens <= 0 {
			t.Errorf("adapter %q has MaxTokens=%d (should be > 0)", name, caps.MaxTokens)
		}
		if caps.ToolIDField == "" {
			t.Errorf("adapter %q has empty ToolIDField", name)
		}
	}
}

// TestMinimax_ValidateOrphanedToolResults verifies that orphaned tool results
// (tool_result blocks without matching assistant tool_use) are detected and
// rejected in the Anthropic serialization path.
func TestMinimax_ValidateOrphanedToolResults(t *testing.T) {
	m := NewMinimax()
	req := &ir.InternalRequest{
		Model: "abab6.5s-chat",
		Messages: []ir.Message{
			{
				Role:    "user",
				Content: []ir.ContentBlock{{Type: "text", Text: "Run a command"}},
			},
			{
				Role:       "tool",
				ToolCallID: "call_orphaned_001",
				Content:    []ir.ContentBlock{{Type: "text", Text: "Result 1"}},
			},
			{
				Role:       "tool",
				ToolCallID: "call_orphaned_002",
				Content:    []ir.ContentBlock{{Type: "text", Text: "Result 2"}},
			},
		},
	}

	_, err := m.SerializeRequest(req)
	if err == nil {
		t.Fatal("Expected error for orphaned tool results in Anthropic path, got nil")
	}

	errMsg := err.Error()
	if !strings.Contains(errMsg, "orphaned tool result") {
		t.Errorf("Expected error to mention 'orphaned tool result', got: %s", errMsg)
	}
	if !strings.Contains(errMsg, "call_orphaned_001") {
		t.Errorf("Expected error to include orphaned ID, got: %s", errMsg)
	}
	t.Logf("✓ Correctly rejected orphaned tool results in Anthropic path: %s", errMsg)
}

// TestMinimax_ValidToolCalling passes through the Anthropic path.
func TestMinimax_ValidToolCalling(t *testing.T) {
	m := NewMinimax()
	req := &ir.InternalRequest{
		Model: "abab6.5s-chat",
		Messages: []ir.Message{
			{
				Role:    "user",
				Content: []ir.ContentBlock{{Type: "text", Text: "Check weather"}},
			},
			{
				Role:    "assistant",
				Content: []ir.ContentBlock{}, // empty content
				ToolCalls: []ir.ToolCall{
					{
						ID:   "call_valid_001",
						Type: "function",
						Function: struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						}{Name: "get_weather", Arguments: `{"city":"Beijing"}`},
					},
				},
			},
			{
				Role:       "tool",
				ToolCallID: "call_valid_001",
				Content:    []ir.ContentBlock{{Type: "text", Text: "sunny, 72°F"}},
			},
		},
	}

	body, err := m.SerializeRequest(req)
	if err != nil {
		t.Fatalf("Valid tool calling should not error: %v", err)
	}
	if len(body) == 0 {
		t.Fatal("Expected non-empty body")
	}
	t.Logf("✓ Valid tool calling passed Anthropic path validation")
}

// TestMinimax_ValidatePartialOrphans tests mixed case: some valid, some orphaned.
func TestMinimax_ValidatePartialOrphans(t *testing.T) {
	m := NewMinimax()
	req := &ir.InternalRequest{
		Model: "abab6.5s-chat",
		Messages: []ir.Message{
			{
				Role:    "user",
				Content: []ir.ContentBlock{{Type: "text", Text: "Task 1"}},
			},
			{
				Role:    "assistant",
				Content: []ir.ContentBlock{},
				ToolCalls: []ir.ToolCall{
					{
						ID:   "call_valid_001",
						Type: "function",
						Function: struct {
							Name      string `json:"name"`
							Arguments string `json:"arguments"`
						}{Name: "bash", Arguments: `{}`},
					},
				},
			},
			{
				Role:       "tool",
				ToolCallID: "call_valid_001",
				Content:    []ir.ContentBlock{{Type: "text", Text: "OK"}},
			},
			{
				Role:       "tool",
				ToolCallID: "call_orphaned_002",
				Content:    []ir.ContentBlock{{Type: "text", Text: "Orphaned"}},
			},
		},
	}

	_, err := m.SerializeRequest(req)
	if err == nil {
		t.Fatal("Expected error for partially orphaned tool results, got nil")
	}

	errMsg := err.Error()
	if !strings.Contains(errMsg, "call_orphaned_002") {
		t.Errorf("Expected error to mention orphaned ID 'call_orphaned_002', got: %s", errMsg)
	}
	t.Logf("✓ Correctly detected partial orphans: %s", errMsg)
}
