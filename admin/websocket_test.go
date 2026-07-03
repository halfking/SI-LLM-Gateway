package admin

import (
	"testing"
	"time"
)

func TestClassifyModelCategory(t *testing.T) {
	cases := []struct {
		model string
		want  string
	}{
		{"gpt-4o", "openai"},
		{"gpt-4o-mini", "openai"},
		{"o1-preview", "openai"},
		{"o3-mini", "openai"},
		{"o4-mini", "openai"},

		{"claude-3.5-sonnet", "anthropic"},
		{"claude-3-opus", "anthropic"},

		{"qwen-max", "domestic"},
		{"glm-4", "domestic"},
		{"ernie-4.0", "domestic"},
		{"doubao-pro", "domestic"},
		{"deepseek-v3", "domestic"},
		{"moonshot-v1", "domestic"},

		// Numeric-only Qwen suffix is the same keyword → domestic.
		{"qwen2-72b-instruct", "domestic"},

		// Open-source families with their own family prefix.
		{"llama-3.1-70b", "oss"},
		{"mistral-large", "oss"},
		{"mixtral-8x22b", "oss"},
		{"phi-3-medium", "oss"},
		{"gemma-2-27b", "oss"},

		{"", "other"},
		{"custom-finetune-v1", "other"},
	}
	for _, c := range cases {
		got := classifyModelCategory(c.model)
		if got != c.want {
			t.Errorf("classifyModelCategory(%q) = %q, want %q", c.model, got, c.want)
		}
	}
}

func TestLiveStreamConfigDefaults(t *testing.T) {
	var cfg LiveStreamConfig
	cfg.defaults()
	if cfg.BroadcastQueueSize != 1024 {
		t.Errorf("BroadcastQueueSize default = %d, want 1024", cfg.BroadcastQueueSize)
	}
	if cfg.InitialReplayLimit != 50 {
		t.Errorf("InitialReplayLimit default = %d, want 50", cfg.InitialReplayLimit)
	}
	if cfg.IdleThreshold != 60*time.Second {
		t.Errorf("IdleThreshold default = %v, want 60s", cfg.IdleThreshold)
	}
	if cfg.ReadTimeout != 90*time.Second {
		t.Errorf("ReadTimeout default = %v, want 90s", cfg.ReadTimeout)
	}
}

func TestShouldDeliver_TenantIsolation(t *testing.T) {
	hub := NewLiveStreamHub(nil, "test-secret", LiveStreamConfig{})

	superClient := &liveStreamClient{isSuper: true}
	tenantAClient := &liveStreamClient{tenantID: "tenant-a", isSuper: false}
	tenantBClient := &liveStreamClient{tenantID: "tenant-b", isSuper: false}

	envelopeA := LiveStreamEnvelope{
		Type:    "request",
		Request: &LiveRequest{TenantID: "tenant-a"},
	}
	envelopeB := LiveStreamEnvelope{
		Type:    "request",
		Request: &LiveRequest{TenantID: "tenant-b"},
	}

	if !hub.shouldDeliver(superClient, envelopeA) {
		t.Error("super_admin should see tenant-a traffic")
	}
	if !hub.shouldDeliver(superClient, envelopeB) {
		t.Error("super_admin should see tenant-b traffic")
	}
	if !hub.shouldDeliver(tenantAClient, envelopeA) {
		t.Error("tenant-a client should see tenant-a traffic")
	}
	if hub.shouldDeliver(tenantAClient, envelopeB) {
		t.Error("tenant-a client must NOT see tenant-b traffic")
	}
	if hub.shouldDeliver(tenantBClient, envelopeA) {
		t.Error("tenant-b client must NOT see tenant-a traffic")
	}

	// idle_marker and initial_data have Request == nil → always deliver.
	idle := LiveStreamEnvelope{Type: "idle_marker"}
	if !hub.shouldDeliver(tenantAClient, idle) {
		t.Error("tenant client should still see idle_marker")
	}
	if !hub.shouldDeliver(tenantBClient, idle) {
		t.Error("tenant client should still see idle_marker")
	}
}

func TestPublish_DoesNotBlock(t *testing.T) {
	hub := NewLiveStreamHub(nil, "test-secret", LiveStreamConfig{BroadcastQueueSize: 2})
	// Fill the queue.
	for i := 0; i < 2; i++ {
		hub.Publish(LiveRequest{RequestID: "fill"})
	}
	// The third publish MUST drop, not block.
	done := make(chan struct{})
	go func() {
		hub.Publish(LiveRequest{RequestID: "overflow"})
		close(done)
	}()
	select {
	case <-done:
		// good
	case <-time.After(100 * time.Millisecond):
		t.Fatal("Publish blocked when queue was full")
	}
}
