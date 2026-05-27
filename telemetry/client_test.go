package telemetry

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestClient_Disabled(t *testing.T) {
	c := NewClient("", "")
	if c.Enabled() {
		t.Fatal("empty endpoint should be disabled")
	}
	c.EmitDecisionLog(&DecisionLogEntry{RequestID: "test"})
	c.EmitRequestLog(&RequestLogEntry{RequestID: "test"})
	c.Stop()
}

func TestClient_DecisionLogEmission(t *testing.T) {
	var received atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/telemetry/decision-log" {
			received.Add(1)
			var entry DecisionLogEntry
			json.NewDecoder(r.Body).Decode(&entry)
			if entry.RequestID != "req-123" {
				t.Errorf("expected request_id=req-123, got %s", entry.RequestID)
			}
			if entry.Model != "gpt-4" {
				t.Errorf("expected model=gpt-4, got %s", entry.Model)
			}
			if !entry.Success {
				t.Error("expected success=true")
			}
		}
		w.WriteHeader(200)
		w.Write([]byte(`{"status":"ok"}`))
	}))
	defer server.Close()

	c := NewClient(server.URL, "test-admin-key")
	c.httpClient = server.Client()

	c.EmitDecisionLog(&DecisionLogEntry{
		RequestID: "req-123",
		Model:     "gpt-4",
		Success:   true,
		LatencyMs: 150,
	})

	time.Sleep(500 * time.Millisecond)
	c.Stop()

	if received.Load() != 1 {
		t.Errorf("expected 1 decision log received, got %d", received.Load())
	}
}

func TestClient_RequestLogEmission(t *testing.T) {
	var received atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/telemetry/request-log" {
			received.Add(1)
			var entry RequestLogEntry
			json.NewDecoder(r.Body).Decode(&entry)
			if entry.RequestID != "req-456" {
				t.Errorf("expected request_id=req-456, got %s", entry.RequestID)
			}
			pt := 100
			ct := 50
			if entry.PromptTokens == nil || *entry.PromptTokens != pt {
				t.Errorf("expected prompt_tokens=100")
			}
			if entry.CompletionTokens == nil || *entry.CompletionTokens != ct {
				t.Errorf("expected completion_tokens=50")
			}
		}
		w.WriteHeader(200)
		w.Write([]byte(`{"status":"queued"}`))
	}))
	defer server.Close()

	c := NewClient(server.URL, "test-admin-key")
	c.httpClient = server.Client()

	pt := 100
	ct := 50
	c.EmitRequestLog(&RequestLogEntry{
		RequestID:        "req-456",
		PromptTokens:     &pt,
		CompletionTokens: &ct,
		Success:          true,
	})

	time.Sleep(500 * time.Millisecond)
	c.Stop()

	if received.Load() != 1 {
		t.Errorf("expected 1 request log received, got %d", received.Load())
	}
}

func TestClient_BatchFlush(t *testing.T) {
	var received atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received.Add(1)
		w.WriteHeader(200)
		w.Write([]byte(`{"status":"ok"}`))
	}))
	defer server.Close()

	c := NewClient(server.URL, "test-admin-key")
	c.httpClient = server.Client()

	for i := 0; i < 10; i++ {
		c.EmitDecisionLog(&DecisionLogEntry{
			RequestID: "batch-" + string(rune('0'+i)),
			Model:     "test",
			Success:   true,
		})
	}

	time.Sleep(500 * time.Millisecond)
	c.Stop()

	if received.Load() != 10 {
		t.Errorf("expected 10 received, got %d", received.Load())
	}
}

func TestClient_ServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(500)
	}))
	defer server.Close()

	c := NewClient(server.URL, "test-admin-key")
	c.httpClient = server.Client()

	c.EmitDecisionLog(&DecisionLogEntry{
		RequestID: "err-test",
		Model:     "test",
		Success:   false,
	})

	time.Sleep(300 * time.Millisecond)
	c.Stop()
}

func TestClient_QueueFull(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(100 * time.Millisecond)
		w.WriteHeader(200)
	}))
	defer server.Close()

	c := NewClient(server.URL, "test-admin-key")
	c.httpClient = server.Client()
	c.queue = make(chan any, 2)

	for i := 0; i < 10; i++ {
		c.EmitDecisionLog(&DecisionLogEntry{
			RequestID: "overflow",
			Model:     "test",
			Success:   true,
		})
	}

	c.Stop()
}
