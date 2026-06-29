// Tests for the 2026-06-30 Phase 2 P1 fixes: SetResponseBody /
// SetUpstreamStatusCode land in the persisted RequestLogEntry on the
// Exhausted failure path. Regression test for the minimax-m3 incident
// where 217 request_logs rows had NULL response_body /
// upstream_status_code because the relay handler's Exhausted branch
// never called these setters.
package relay

import (
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/kaixuan/llm-gateway-go/circuit"
	"github.com/kaixuan/llm-gateway-go/limiter"
)

// TestBuildFailureEntry_CapturesUpstreamBodyAndStatus exercises the
// Phase 2 P1 fix: SetResponseBody + SetUpstreamStatusCode on the
// RequestLogContext must be reflected in the entry returned by
// BuildFailureEntry, which is what the failure INSERT/UPDATE writes
// to request_logs.response_body / upstream_status_code.
func TestBuildFailureEntry_CapturesUpstreamBodyAndStatus(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	r := httptest.NewRequest("POST", "/v1/chat/completions",
		strings.NewReader(`{"model":"minimax-m3"}`))
	ctx := ch.NewRequestLogContext(r, "req-m3-1", time.Now())
	ctx.Body = []byte(`{"model":"minimax-m3"}`)
	ctx.SetClientModel("minimax-m3")

	// Simulate the relay/handler.go Exhausted branch's calls:
	vendorBody := []byte(`{"error":{"type":"rate_limit_error","code":"rpm_exceeded","message":"RPM limit hit"}}`)
	ctx.SetResponseBody(vendorBody)
	ctx.SetUpstreamStatusCode(429)

	entry := ctx.BuildFailureEntry("rate_limit", "upstream 429: rpm exceeded", nil, nil)
	if entry == nil {
		t.Fatal("nil entry")
	}

	// 2026-06-30 fix: upstream_status_code must round-trip into the entry.
	if entry.UpstreamStatusCode == nil {
		t.Fatalf("expected UpstreamStatusCode=429 on entry, got nil")
	}
	if *entry.UpstreamStatusCode != 429 {
		t.Errorf("expected 429, got %d", *entry.UpstreamStatusCode)
	}

	// 2026-06-30 fix: response_body must round-trip.
	if entry.ResponseBody == nil {
		t.Fatalf("expected ResponseBody populated, got nil")
	}
	if !strings.Contains(*entry.ResponseBody, "rpm_exceeded") {
		t.Errorf("expected response body to contain vendor 'rpm_exceeded', got %q", *entry.ResponseBody)
	}
}

// TestSetUpstreamStatusCode_IgnoresZero verifies the setter does not
// leak a zero-value placeholder into request_logs when the upstream
// connection failed before receiving an HTTP status (network-level).
// Regression for the symptom where every timeout would clobber
// upstream_status_code=502 with 0.
func TestSetUpstreamStatusCode_IgnoresZero(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	r := httptest.NewRequest("POST", "/v1/chat/completions",
		strings.NewReader(`{}`))
	ctx := ch.NewRequestLogContext(r, "req-m3-2", time.Now())

	ctx.SetUpstreamStatusCode(0) // network-level failure (no HTTP response)
	if ctx.UpstreamStatusCode != 0 {
		t.Fatalf("expected 0 to be ignored by SetUpstreamStatusCode, got %d", ctx.UpstreamStatusCode)
	}

	// Now set a real code and verify it lands.
	ctx.SetUpstreamStatusCode(503)
	if ctx.UpstreamStatusCode != 503 {
		t.Errorf("expected 503, got %d", ctx.UpstreamStatusCode)
	}

	entry := ctx.BuildFailureEntry("upstream_down", "no HTTP response", nil, nil)
	if entry == nil {
		t.Fatal("nil entry")
	}
	if entry.UpstreamStatusCode == nil || *entry.UpstreamStatusCode != 503 {
		t.Errorf("expected entry.UpstreamStatusCode=503, got %v", entry.UpstreamStatusCode)
	}
}

// TestBuildFailureEntry_NoUpstreamMeansNilPointer ensures we don't
// emit an upstream_status_code pointer at all (rather than a zero
// int) when the relay layer never saw an HTTP response.
func TestBuildFailureEntry_NoUpstreamMeansNilPointer(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	r := httptest.NewRequest("POST", "/v1/chat/completions",
		strings.NewReader(`{}`))
	ctx := ch.NewRequestLogContext(r, "req-m3-3", time.Now())

	// No SetUpstreamStatusCode call → entry.UpstreamStatusCode must stay nil.
	entry := ctx.BuildFailureEntry("network", "i/o timeout", nil, nil)
	if entry == nil {
		t.Fatal("nil entry")
	}
	if entry.UpstreamStatusCode != nil {
		t.Errorf("expected nil UpstreamStatusCode, got %d", *entry.UpstreamStatusCode)
	}
}