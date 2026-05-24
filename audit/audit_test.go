package audit

import (
	"context"
	"encoding/json"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestEventBuilder_Basic(t *testing.T) {
	e := NewEvent().
		ClientModel("gpt-4o").
		OutboundModel("gpt-4o-2024-08-06").
		Provider(1).
		Credential(5).
		Success(true).
		Latency(150 * time.Millisecond).
		Tokens(100, 50).
		Build()

	if e.ClientModel != "gpt-4o" {
		t.Fatalf("expected gpt-4o, got %s", e.ClientModel)
	}
	if !e.Success {
		t.Fatal("expected success")
	}
	if e.LatencyMs != 150 {
		t.Fatalf("expected 150ms, got %d", e.LatencyMs)
	}
	if e.PromptTokens != 100 || e.CompletionToken != 50 {
		t.Fatalf("expected 100/50, got %d/%d", e.PromptTokens, e.CompletionToken)
	}
	if e.RequestID == "" {
		t.Fatal("expected non-empty request_id")
	}
}

func TestEventBuilder_Failure(t *testing.T) {
	e := NewEvent().
		ClientModel("test").
		Success(false).
		ErrorKind("upstream_down").
		FailureStage("upstream_call").
		Build()

	if e.Success {
		t.Fatal("expected failure")
	}
	if e.ErrorKind != "upstream_down" {
		t.Fatalf("expected upstream_down, got %s", e.ErrorKind)
	}
	if e.FailureStage != "upstream_call" {
		t.Fatalf("expected upstream_call, got %s", e.FailureStage)
	}
}

func TestStreamCapture(t *testing.T) {
	sc := NewStreamCapture()
	sc.RecordChunk([]byte("hello"))
	sc.RecordChunk([]byte("world"))
	sc.RecordDone()

	count, ttfb, done, interrupted, checksum := sc.Snapshot()
	if count != 2 {
		t.Fatalf("expected 2 chunks, got %d", count)
	}
	if ttfb < 0 {
		t.Fatal("expected non-negative ttfb")
	}
	if !done {
		t.Fatal("expected done")
	}
	if interrupted {
		t.Fatal("expected not interrupted")
	}
	if len(checksum) != 64 {
		t.Fatalf("expected 64-char checksum, got %d", len(checksum))
	}
}

func TestStreamCapture_Interrupted(t *testing.T) {
	sc := NewStreamCapture()
	sc.RecordChunk([]byte("data"))
	sc.MarkInterrupted()

	_, _, _, interrupted, _ := sc.Snapshot()
	if !interrupted {
		t.Fatal("expected interrupted")
	}
}

func TestEventBuilder_StreamMetrics(t *testing.T) {
	sc := NewStreamCapture()
	sc.RecordChunk([]byte("chunk1"))
	sc.RecordChunk([]byte("chunk2"))
	sc.RecordDone()

	e := NewEvent().
		ClientModel("test").
		Stream(true).
		StreamMetrics(sc).
		Build()

	if e.StreamChunkCount != 2 {
		t.Fatalf("expected 2 chunks, got %d", e.StreamChunkCount)
	}
	if !e.StreamDone {
		t.Fatal("expected stream_done")
	}
}

func TestEventBuilder_StreamMetricsNil(t *testing.T) {
	e := NewEvent().StreamMetrics(nil).Build()
	if e.StreamChunkCount != 0 {
		t.Fatal("expected 0 chunks for nil capture")
	}
}

func TestLogSink(t *testing.T) {
	sink := &LogSink{}
	e := NewEvent().ClientModel("test").Success(true).Build()
	sink.Emit(context.Background(), e)
}

func TestJSONSink(t *testing.T) {
	sink := NewJSONSink(5)

	for i := 0; i < 10; i++ {
		sink.Emit(context.Background(), NewEvent().ClientModel("test").Build())
	}

	if sink.Count() != 5 {
		t.Fatalf("expected 5 (capped), got %d", sink.Count())
	}

	recent := sink.Recent(3)
	if len(recent) != 3 {
		t.Fatalf("expected 3 recent, got %d", len(recent))
	}

	data := sink.RecentJSON(2)
	if !strings.HasPrefix(string(data), "[") {
		t.Fatalf("expected JSON array, got %s", string(data[:20]))
	}

	var parsed []Event
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("failed to parse JSON: %v", err)
	}
	if len(parsed) != 2 {
		t.Fatalf("expected 2 parsed events, got %d", len(parsed))
	}
}

func TestMultiSink(t *testing.T) {
	s1 := NewJSONSink(100)
	s2 := NewJSONSink(100)
	multi := NewMultiSink(s1, s2)

	e := NewEvent().ClientModel("multi-test").Success(true).Build()
	multi.Emit(context.Background(), e)

	if s1.Count() != 1 || s2.Count() != 1 {
		t.Fatalf("expected 1/1, got %d/%d", s1.Count(), s2.Count())
	}
}

func TestMultiSink_Concurrent(t *testing.T) {
	sink := NewJSONSink(10000)
	multi := NewMultiSink(sink)

	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			multi.Emit(context.Background(), NewEvent().ClientModel("concurrent").Build())
		}()
	}
	wg.Wait()

	if sink.Count() != 100 {
		t.Fatalf("expected 100, got %d", sink.Count())
	}
}

func TestComputeRequestChecksum(t *testing.T) {
	cs1 := ComputeRequestChecksum("gpt-4o", []byte(`{"messages":[]}`))
	cs2 := ComputeRequestChecksum("gpt-4o", []byte(`{"messages":[]}`))
	cs3 := ComputeRequestChecksum("gpt-4o", []byte(`{"messages":[{"role":"user","content":"hi"}]}`))

	if cs1 != cs2 {
		t.Fatal("same input should produce same checksum")
	}
	if cs1 == cs3 {
		t.Fatal("different input should produce different checksum")
	}
	if len(cs1) != 64 {
		t.Fatalf("expected 64-char hex, got %d", len(cs1))
	}
}

func TestEventBuilder_RequestChecksum(t *testing.T) {
	e := NewEvent().RequestChecksum([]byte("test body")).Build()
	if len(e.RequestChecksum) != 64 {
		t.Fatalf("expected 64-char checksum, got %d chars", len(e.RequestChecksum))
	}
}

func TestEventBuilder_AllFields(t *testing.T) {
	e := NewEvent().
		RequestID("req-123").
		TenantID("tenant-1").
		ApplicationID(2).
		APIKeyID(5).
		ClientModel("claude-3.5").
		OutboundModel("claude-3-5-sonnet").
		ResolutionPath("canonical").
		CanonicalName("claude-3.5").
		IdentityHash("abc123").
		ClientProfile("cursor").
		Stream(true).
		Provider(3).
		Credential(7).
		Success(true).
		Latency(200*time.Millisecond).
		Tokens(50, 25).
		Cost(0.003).
		TransformRule("rule_1").
		Build()

	if e.RequestID != "req-123" {
		t.Fatal("request_id mismatch")
	}
	if e.TenantID != "tenant-1" {
		t.Fatal("tenant_id mismatch")
	}
	if e.ApplicationID != 2 {
		t.Fatal("application_id mismatch")
	}
	if e.APIKeyID != 5 {
		t.Fatal("api_key_id mismatch")
	}
	if e.CostUSD != 0.003 {
		t.Fatal("cost mismatch")
	}
	if e.TransformRule != "rule_1" {
		t.Fatal("transform_rule mismatch")
	}

	data, err := json.Marshal(e)
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}
	var decoded Event
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if decoded.ClientModel != "claude-3.5" {
		t.Fatal("round-trip client_model mismatch")
	}
}
