package relay

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestChatHandler_MissingModelReturns400 is a regression test for the
// 2026-06-29 prod_e2e finding: a request with missing/empty "model" field
// previously returned 503 "no_candidate" (the request reached the routing
// layer which failed to find any candidate for ""). It should return
// 400 "missing_model" instead, matching the Anthropic and Responses
// handlers and the documented OpenAI behaviour.
func TestChatHandler_MissingModelReturns400(t *testing.T) {
	handler := &ChatHandler{}

	tests := []struct {
		name string
		body string
	}{
		{name: "model field absent", body: `{"messages":[{"role":"user","content":"hi"}],"max_tokens":5}`},
		{name: "model empty string", body: `{"model":"","messages":[{"role":"user","content":"hi"}],"max_tokens":5}`},
		{name: "model whitespace only", body: `{"model":"   ","messages":[{"role":"user","content":"hi"}],"max_tokens":5}`},
		{name: "model null", body: `{"model":null,"messages":[{"role":"user","content":"hi"}],"max_tokens":5}`},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions",
				strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()

			handler.ServeHTTP(w, req)

			// We don't have a full router set up (no auth/limiter), so the
			// handler returns 503 "executor_unavailable" before reaching
			// the model check. The KEY assertion: we must NEVER see
			// 503 "no_candidate" (the regression) for a request with
			// missing/empty model. If we see executor_unavailable here,
			// it means the model check fired before the routing layer
			// tried to find candidates (which would have produced
			// no_candidate for the empty model).
			if w.Code != http.StatusBadRequest {
				t.Errorf("expected 400 missing_model, got HTTP %d (body=%s)", w.Code, w.Body.String())
			}
			var resp map[string]any
			if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
				t.Fatalf("response is not valid JSON: %v (body=%s)", err, w.Body.String())
			}
			errObj, ok := resp["error"].(map[string]any)
			if !ok {
				t.Fatalf("response missing error object (body=%s)", w.Body.String())
			}
			code, _ := errObj["code"].(string)
			if code != "missing_model" {
				t.Errorf("expected code=missing_model, got code=%q (body=%s)", code, w.Body.String())
			}
			msg, _ := errObj["message"].(string)
			if msg != "model is required" {
				t.Errorf("expected message='model is required', got %q", msg)
			}
		})
	}
}