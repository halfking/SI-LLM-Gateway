package relay

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/kaixuan/llm-gateway-go/audit"
)

func TestStreamAnthropicPassthrough_ForwardsBytes(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(200)
		//nolint:errcheck // HTTP write error non-recoverable
		w.Write([]byte("event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_x\"}}\n\n"))
		//nolint:errcheck // HTTP write error non-recoverable
		w.Write([]byte("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"))
	}))
	defer upstream.Close()

	resp, err := http.Get(upstream.URL)
	if err != nil {
		t.Fatal(err)
	}
	//nolint:errcheck // best-effort close
	defer resp.Body.Close()

	rec := httptest.NewRecorder()
	capture := audit.NewStreamCapture()
	outcome := StreamAnthropicPassthrough(rec, resp, "MiniMax-M2.7", "MiniMax-M2.7", "req-1", capture, nil)

	if outcome.Interrupted {
		t.Errorf("stream interrupted: %s", outcome.Reason)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "msg_x") {
		t.Errorf("body should contain message_start payload; got: %s", body)
	}
	if !strings.Contains(body, "message_stop") {
		t.Errorf("body should contain message_stop; got: %s", body)
	}
	if !strings.HasPrefix(body, "event: ") {
		t.Errorf("body should start with SSE event line; got prefix: %q", body[:50])
	}
}

func TestStreamAnthropicPassthrough_DetectsThinking(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(200)
		events := []string{
			"event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\"}}\n\n",
			"event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"deep thought\"}}\n\n",
			"event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
			"event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
		}
		for _, e := range events {
			//nolint:errcheck // HTTP write error non-recoverable
			w.Write([]byte(e))
		}
	}))
	defer upstream.Close()
	resp, err := http.Get(upstream.URL)
	if err != nil {
		t.Fatal(err)
	}
	//nolint:errcheck // best-effort close
	defer resp.Body.Close()

	rec := httptest.NewRecorder()
	capture := audit.NewStreamCapture()
	_ = StreamAnthropicPassthrough(rec, resp, "MiniMax-M2.7", "MiniMax-M2.7", "req-2", capture, nil)
	if !capture.HasThinking {
		t.Error("expected capture.HasThinking=true when thinking block present")
	}
}

func TestStreamAnthropicPassthrough_AccumulatesUsage(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(200)
		events := []string{
			"event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":42,\"output_tokens\":0}}}\n\n",
			"event: message_delta\ndata: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":17}}\n\n",
			"event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
		}
		for _, e := range events {
			//nolint:errcheck // HTTP write error non-recoverable
			w.Write([]byte(e))
		}
	}))
	defer upstream.Close()
	resp, err := http.Get(upstream.URL)
	if err != nil {
		t.Fatal(err)
	}
	//nolint:errcheck // best-effort close
	defer resp.Body.Close()

	rec := httptest.NewRecorder()
	capture := audit.NewStreamCapture()
	_ = StreamAnthropicPassthrough(rec, resp, "MiniMax-M2.7", "MiniMax-M2.7", "req-3", capture, nil)
	if capture.InputTokens == nil || *capture.InputTokens != 42 {
		t.Errorf("InputTokens = %v, want 42", capture.InputTokens)
	}
	if capture.OutputTokens == nil || *capture.OutputTokens != 17 {
		t.Errorf("OutputTokens = %v, want 17", capture.OutputTokens)
	}
}

// TestStreamAnthropicPassthrough_CapturesCacheFields covers the
// 2026-06-30 fix: message_start carries the initial cache_read /
// cache_creation counts, and message_delta carries the FINAL
// cache_read value. Both must land in the capture so the audit
// summary surfaces cache_read_tokens / cache_write_tokens on the
// request_logs row.
//
// Before this fix, only InputTokens / OutputTokens were lifted from
// the SSE events, so Anthropic cached-prompt calls were charged
// without showing the cache discount in request_logs.
func TestStreamAnthropicPassthrough_CapturesCacheFields(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(200)
		events := []string{
			// message_start: input + cache_creation (cache write) only.
			"event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":120,\"output_tokens\":0,\"cache_creation_input_tokens\":20}}}\n\n",
			// message_delta: output + FINAL cache_read. Anthropic
			// emits the cumulative cache_read on the delta, not on
			// message_start — observeAnthropicPayload must overwrite
			// any earlier value so the capture ends with the
			// billing-relevant count.
			"event: message_delta\ndata: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":17,\"cache_read_input_tokens\":100}}\n\n",
			"event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
		}
		for _, e := range events {
			//nolint:errcheck // HTTP write error non-recoverable
			w.Write([]byte(e))
		}
	}))
	defer upstream.Close()
	resp, err := http.Get(upstream.URL)
	if err != nil {
		t.Fatal(err)
	}
	//nolint:errcheck // best-effort close
	defer resp.Body.Close()

	rec := httptest.NewRecorder()
	capture := audit.NewStreamCapture()
	_ = StreamAnthropicPassthrough(rec, resp, "claude-3-5-sonnet", "claude-3-5-sonnet", "req-cache", capture, nil)
	if capture.InputTokens == nil || *capture.InputTokens != 120 {
		t.Errorf("InputTokens = %v, want 120", capture.InputTokens)
	}
	if capture.OutputTokens == nil || *capture.OutputTokens != 17 {
		t.Errorf("OutputTokens = %v, want 17", capture.OutputTokens)
	}
	// cache_read comes from message_delta, not message_start.
	cr := capture.GetCacheReadTokens()
	if cr == nil || *cr != 100 {
		t.Errorf("CacheReadTokens = %v, want pointer to 100 (from message_delta)", cr)
	}
	// cache_creation comes from message_start.
	cw := capture.GetCacheWriteTokens()
	if cw == nil || *cw != 20 {
		t.Errorf("CacheWriteTokens = %v, want pointer to 20 (from message_start)", cw)
	}
	// And the audit summary must surface them so emitTelemetry can
	// lift them into the request_logs row.
	m := capture.SummaryAsMap()
	if v, ok := m["cache_read_tokens"].(int); !ok || v != 100 {
		t.Errorf("SummaryAsMap cache_read_tokens = %v, want 100", m["cache_read_tokens"])
	}
	if v, ok := m["cache_write_tokens"].(int); !ok || v != 20 {
		t.Errorf("SummaryAsMap cache_write_tokens = %v, want 20", m["cache_write_tokens"])
	}
}
