// Tests for the 2026-06-30 Phase 2 P2 MiniMax-specific error
// classification. Regression coverage for the minimax-m3 production
// incident where 2162 HTTP 400 errors with vendor-private error codes
// 2013 / 1008 / 1004 were mis-classified as KindTransient instead of
// the precise KindToolCallIdMismatch / KindContextLength / KindAuth /
// KindQuota. The exact body strings below are copied verbatim from
// candidate_failure_logs.error_message in the production DB
// (14.103.112.184:11032/llm_gateway) between 2026-06-23 and 2026-06-30.
package errorsx

import (
	"net/http"
	"testing"
)

// TestClassifyErrorWithBody_MiniMaxToolCallIdMismatch covers the dominant
// 2162-row class: vendor returns `invalid params, tool result's tool
// id(...) not found (2013)` on HTTP 400. Must classify as
// KindToolCallIdMismatch (a client bug — IsClientBug = true), so the
// gateway does NOT cool the credential for the caller's mistake.
func TestClassifyErrorWithBody_MiniMaxToolCallIdMismatch(t *testing.T) {
	cases := [][]byte{
		[]byte(`{"type":"error","error":{"type":"bad_request_error","message":"invalid params, tool result's tool id(call_function_i3ye00n766a2_3) not found (2013)","http_code":"400","code":2013},"request_id":"06921fac6c666f569ae70c46fd6d9ed3"}`),
		[]byte(`{"type":"error","error":{"type":"bad_request_error","message":"invalid params, tool result's tool id(call_nLUjWFmoaMZTjJvZeg4eXwMF) not found (2013)","http_code":"400","code":2013},"request_id":"06921fac6c666f569ae70c46fd6d9ed3"}`),
		[]byte(`{"type":"error","error":{"type":"bad_request_error","message":"invalid params, tool result's tool id(call-f5e9f14c-fa38-40da-97d8-9bcb8e94e080) not found (2013)","http_code":"400","code":2013}}`),
		[]byte(`upstream 400: {"type":"error","error":{"type":"bad_request_error","message":"invalid params, tool result's tool id(calluse_xdK01NWVKhe4ebDJ49Unhs) not found (2013)","http_code":"400"},"request_id":"0689f7ecb74a4bc4"}`),
	}
	for i, body := range cases {
		got := ClassifyErrorWithBody(400, body)
		if got != KindToolCallIdMismatch {
			t.Errorf("case %d: expected KindToolCallIdMismatch, got %q\nbody: %s", i, got, body)
		}
	}
}

// TestClassifyErrorWithBody_MiniMaxContextLength covers the 98-row class:
// `invalid params, context window exceeds limit (2013)`. Must classify
// as KindContextLength so the executor's one-shot trim+retry path can
// trigger instead of bouncing the same oversized body across credentials.
//
// This is the most important regression: previously this body matched
// `toolCallIdMismatchRe` (which used a bare `2013` fallback) and was
// mis-classified as a client bug — IsClientBug=true → circuit was
// skipped, availability state NOT cooled, but the actual fix
// (trim+retry) was also skipped, so the user saw a raw 400 every time.
func TestClassifyErrorWithBody_MiniMaxContextLength(t *testing.T) {
	cases := [][]byte{
		[]byte(`{"type":"error","error":{"type":"bad_request_error","message":"invalid params, context window exceeds limit (2013)","http_code":"400","code":2013},"request_id":"0689b9d26067e9086c5ac1031847c344"}`),
		[]byte(`{"type":"error","error":{"type":"bad_request_error","message":"invalid params, context window exceeds limit (2013)","http_code":"400","code":2013},"request_id":"0689d3e06334642f4fd2fbf93a1c5336"}`),
		// MiniMax-style plain message (no JSON wrapper) seen in some logs.
		[]byte(`invalid params, context window exceeds limit (2013)`),
	}
	for i, body := range cases {
		got := ClassifyErrorWithBody(400, body)
		if got != KindContextLength {
			t.Errorf("case %d: expected KindContextLength, got %q\nbody: %s", i, got, body)
		}
	}
}

// TestClassifyErrorWithBody_MiniMaxAuth covers the 30-row class:
// `authorized_error` with `(1004)` error-code suffix returned by
// api.minimaxi.com on HTTP 401/403 for invalid/revoked API keys.
// Must classify as KindAuth so IsCredentialFatal = true → circuit
// opens, availability_state = auth_failed, alerting fires immediately
// instead of cycling through every retry across every credential.
func TestClassifyErrorWithBody_MiniMaxAuth(t *testing.T) {
	cases := []struct {
		body   []byte
		status int
	}{
		{[]byte(`{"type":"error","error":{"type":"authorized_error","message":"login fail: Please carry the API secret key in the 'Authorization' field of the request header (1004)","http_code":"401"},"request_id":"06921fac6c666f569ae70c46fd6d9ed3"}`), 401},
		{[]byte(`{"type":"error","error":{"type":"authorized_error","message":"login fail: Please carry the API secret key in the 'Authorization' field of the request header (1004)","http_code":"401"},"request_id":"06921facc19020be3e7a62eea1d511d1"}`), 401},
		// 1005 = API key revoked / disabled
		{[]byte(`{"type":"error","error":{"type":"authorized_error","message":"API key revoked (1005)","http_code":"403"}}`), 403},
		// Plain text format (defensive — some old log rows don't wrap in JSON)
		{[]byte(`upstream 401: authorized_error: login fail (1004)`), 401},
	}
	for i, c := range cases {
		got := ClassifyErrorWithBody(c.status, c.body)
		if got != KindAuth {
			t.Errorf("case %d: expected KindAuth, got %q\nbody: %s", i, got, c.body)
		}
	}
}

// TestClassifyErrorWithBody_MiniMaxQuota covers the MiniMax balance
// errors. The (1008) error-code suffix is the vendor-private marker.
// Must classify as KindQuota so the circuit opens with quota_state
// (not auth_state), alerting uses the right runbook, and the operator
// can see "balance ran out" instead of generic transient retry noise.
func TestClassifyErrorWithBody_MiniMaxQuota(t *testing.T) {
	cases := [][]byte{
		[]byte(`{"type":"error","error":{"type":"insufficient_balance_error","message":"balance insufficient (1008)","http_code":"402"},"request_id":"06921fac6c666f569ae70c46fd6d9ed3"}`),
		[]byte(`{"type":"error","error":{"type":"quota_exceeded_error","message":"账户余额不足 (1008)","http_code":"402"}}`),
		[]byte(`balance insufficient (1008)`), // 402 must not be re-classified as transient.
	}
	for i, body := range cases {
		got := ClassifyErrorWithBody(402, body)
		if got != KindQuota {
			t.Errorf("case %d: expected KindQuota, got %q\nbody: %s", i, got, body)
		}
	}
}

// TestClassifyErrorWithBody_PriorityOrder verifies that the
// context-length check runs BEFORE the tool-call-id check on MiniMax
// bodies that match both patterns. The "(2013)" error code suffix is
// shared between the two error types, and the message wording
// determines which one applies.
func TestClassifyErrorWithBody_PriorityOrder(t *testing.T) {
	// (2013) + "context window" → context_length (NOT tool_call_id_mismatch)
	body := []byte(`{"error":{"message":"invalid params, context window exceeds limit (2013)","code":2013}}`)
	if got := ClassifyErrorWithBody(400, body); got != KindContextLength {
		t.Errorf("context-window body with (2013) should be KindContextLength, got %q", got)
	}

	// (2013) + "tool result's tool id" → tool_call_id (NOT context_length)
	body2 := []byte(`{"error":{"message":"invalid params, tool result's tool id(call_xyz) not found (2013)","code":2013}}`)
	if got := ClassifyErrorWithBody(400, body2); got != KindToolCallIdMismatch {
		t.Errorf("tool_call_id body with (2013) should be KindToolCallIdMismatch, got %q", got)
	}
}

// TestClassifyResponseBody_MiniMax covers the ClassifyResponseBody path
// (used for streaming/SSE error chunks) which has slightly different
// rules — no status-code gate on most regexes. The 4xx-gated
// model_not_found is preserved but everything else uses pure body
// matching, so MiniMax tool_call_id and context_length bodies must
// still classify correctly.
func TestClassifyResponseBody_MiniMax(t *testing.T) {
	cases := []struct {
		body     []byte
		expected ErrorKind
	}{
		{
			[]byte(`{"error":{"message":"invalid params, tool result's tool id(call_xxx) not found (2013)","code":2013}}`),
			KindToolCallIdMismatch,
		},
		{
			[]byte(`{"error":{"message":"invalid params, context window exceeds limit (2013)","code":2013}}`),
			KindContextLength,
		},
		{
			[]byte(`{"error":{"type":"authorized_error","message":"login fail (1004)"}}`),
			KindAuth,
		},
	}
	for i, c := range cases {
		got := ClassifyResponseBody(400, c.body)
		if got != c.expected {
			t.Errorf("case %d: expected %q, got %q", i, c.expected, got)
		}
	}
}

// TestClassifyError_NilAuthMeansTransient sanity-checks the boundary:
// a 401 status with NO body must still fall through to KindAuth via
// the status-code-only path in ClassifyResponseStatus. (ClassifyError
// delegates to it when resp != nil and err == nil.)
func TestClassifyError_NilAuthMeansTransient(t *testing.T) {
	kind := ClassifyError(nil, &http.Response{StatusCode: 401})
	if kind != KindAuth {
		t.Errorf("expected KindAuth for 401 status-only, got %q", kind)
	}
}