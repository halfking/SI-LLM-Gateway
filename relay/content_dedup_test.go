package relay

import (
	"context"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/kaixuan/llm-gateway-go/pending"
)

func TestComputeFingerprint_SameContent(t *testing.T) {
	cache := NewContentDedupCache(nil, 10*time.Minute, 3)

	messages := []Message{
		{Role: "user", Content: "Hello"},
		{Role: "assistant", Content: "Hi there!"},
		{Role: "user", Content: "How are you?"},
	}

	fp1 := cache.ComputeFingerprint(messages, "gpt-4", true)
	fp2 := cache.ComputeFingerprint(messages, "gpt-4", true)

	if fp1 != fp2 {
		t.Errorf("Expected same fingerprint for identical content, got %s != %s", fp1, fp2)
	}
}

func TestComputeFingerprint_DifferentModel(t *testing.T) {
	cache := NewContentDedupCache(nil, 10*time.Minute, 3)

	messages := []Message{
		{Role: "user", Content: "Hello"},
	}

	fp1 := cache.ComputeFingerprint(messages, "gpt-4", true)
	fp2 := cache.ComputeFingerprint(messages, "gpt-3.5", true)

	if fp1 == fp2 {
		t.Errorf("Expected different fingerprints for different models")
	}
}

func TestComputeFingerprint_DifferentStream(t *testing.T) {
	cache := NewContentDedupCache(nil, 10*time.Minute, 3)

	messages := []Message{
		{Role: "user", Content: "Hello"},
	}

	fp1 := cache.ComputeFingerprint(messages, "gpt-4", true)
	fp2 := cache.ComputeFingerprint(messages, "gpt-4", false)

	if fp1 == fp2 {
		t.Errorf("Expected different fingerprints for different stream flags")
	}
}

func TestComputeFingerprint_OnlyLastN(t *testing.T) {
	cache := NewContentDedupCache(nil, 10*time.Minute, 2) // Only last 2 messages

	messages1 := []Message{
		{Role: "user", Content: "First"},
		{Role: "assistant", Content: "Second"},
		{Role: "user", Content: "Third"},
	}

	messages2 := []Message{
		{Role: "user", Content: "Different"},
		{Role: "assistant", Content: "Second"},
		{Role: "user", Content: "Third"},
	}

	fp1 := cache.ComputeFingerprint(messages1, "gpt-4", true)
	fp2 := cache.ComputeFingerprint(messages2, "gpt-4", true)

	// Should be the same because we only look at last 2 messages
	if fp1 != fp2 {
		t.Errorf("Expected same fingerprint when only considering last 2 messages")
	}
}

func TestComputeFingerprint_TruncatesLongContent(t *testing.T) {
	cache := NewContentDedupCache(nil, 10*time.Minute, 3)

	longContent := string(make([]byte, 20000)) // 20KB
	messages := []Message{
		{Role: "user", Content: longContent},
	}

	fp := cache.ComputeFingerprint(messages, "gpt-4", true)
	if fp == "" {
		t.Errorf("Expected non-empty fingerprint even for very long content")
	}
}

func TestCheckAndReplay_CacheMiss(t *testing.T) {
	store := pending.NewStore(nil, 7*24*time.Hour) // Nil Redis = no-op store
	cache := NewContentDedupCache(store, 10*time.Minute, 3)

	w := httptest.NewRecorder()
	replayed, err := cache.CheckAndReplay(context.Background(), "sess-1", "hash-123", w)

	if err != nil {
		t.Errorf("Expected no error on cache miss, got %v", err)
	}
	if replayed {
		t.Errorf("Expected cache miss, got replay=true")
	}
}

func TestCheckAndReplay_NilCache(t *testing.T) {
	var cache *ContentDedupCache = nil

	w := httptest.NewRecorder()
	replayed, err := cache.CheckAndReplay(context.Background(), "sess-1", "hash-123", w)

	if err != nil {
		t.Errorf("Expected no error with nil cache, got %v", err)
	}
	if replayed {
		t.Errorf("Expected cache miss with nil cache, got replay=true")
	}
}

func TestParseMessagesForFingerprint(t *testing.T) {
	bodyBytes := []byte(`{
		"messages": [
			{"role": "user", "content": "Hello"},
			{"role": "assistant", "content": "Hi"}
		],
		"model": "gpt-4",
		"stream": true
	}`)

	messages, model, stream, err := ParseMessagesForFingerprint(bodyBytes)
	if err != nil {
		t.Fatalf("Parse failed: %v", err)
	}

	if len(messages) != 2 {
		t.Errorf("Expected 2 messages, got %d", len(messages))
	}
	if model != "gpt-4" {
		t.Errorf("Expected model=gpt-4, got %s", model)
	}
	if !stream {
		t.Errorf("Expected stream=true, got false")
	}
	if messages[0].Role != "user" || messages[0].Content != "Hello" {
		t.Errorf("Unexpected first message: %+v", messages[0])
	}
}

func TestParseMessagesForFingerprint_InvalidJSON(t *testing.T) {
	bodyBytes := []byte(`{invalid json}`)

	_, _, _, err := ParseMessagesForFingerprint(bodyBytes)
	if err == nil {
		t.Errorf("Expected error for invalid JSON")
	}
}

func TestNewContentDedupCache_Defaults(t *testing.T) {
	cache := NewContentDedupCache(nil, 0, 0)

	if cache.depth != 3 {
		t.Errorf("Expected default depth=3, got %d", cache.depth)
	}
	if cache.window != 10*time.Minute {
		t.Errorf("Expected default window=10m, got %v", cache.window)
	}
}

func TestContentDedupCache_EndToEnd(t *testing.T) {
	// This is a mock test since we don't have a real Redis in unit tests
	// In integration tests, we would verify the full Store → CheckAndReplay flow
	
	store := pending.NewStore(nil, 7*24*time.Hour)
	cache := NewContentDedupCache(store, 10*time.Minute, 3)

	messages := []Message{
		{Role: "user", Content: "Test message"},
	}

	fp := cache.ComputeFingerprint(messages, "gpt-4", true)
	if fp == "" {
		t.Errorf("Expected non-empty fingerprint")
	}

	// Note: actual Store/Replay would require Redis mock
	// See integration tests for full coverage
}
