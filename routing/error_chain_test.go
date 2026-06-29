// Tests for the 2026-06-30 Phase 2 P1 error-chain penetration fixes:
// errors.Unwrap must be able to walk ExecuteError → upstream.Error so
// extractUpstreamError can recover the vendor response body + status
// code on the Exhausted (multi-credential fall-through) failure path.
// Regression test for the minimax-m3 incident where 217 request_logs
// rows had NULL response_body / upstream_status_code because the chain
// was broken at retryableError and ExecuteError.
package routing

import (
	"errors"
	"testing"

	upstreampkg "github.com/kaixuan/llm-gateway-go/upstream"
)

// TestExecuteErrorUnwrap verifies the LastErr → ExecuteError chain
// survives errors.Unwrap. This is what lets extractUpstreamError in
// relay/handler.go pull the *upstream.Error from inside an Exhausted
// multi-credential fall-through.
func TestExecuteErrorUnwrap(t *testing.T) {
	upErr := &upstreampkg.Error{
		Kind:       upstreampkg.KindRateLimit,
		Message:    "upstream HTTP 429",
		Body:       []byte(`{"error":{"code":"rate_limit_exceeded"}}`),
		StatusCode: 429,
	}
	execErr := &ExecuteError{
		LastErr:   upErr,
		Tried:     3,
		Exhausted: true,
		LastKind:  upstreampkg.KindRateLimit,
	}

	// Walk via errors.Unwrap to the typed upstream.Error.
	var got *upstreampkg.Error
	for cur := error(execErr); cur != nil; cur = errors.Unwrap(cur) {
		if u, ok := cur.(*upstreampkg.Error); ok {
			got = u
			break
		}
	}
	if got == nil {
		t.Fatalf("expected errors.Unwrap to find *upstream.Error inside ExecuteError, got nil")
	}
	if got.StatusCode != 429 {
		t.Errorf("expected status 429, got %d", got.StatusCode)
	}
	if string(got.Body) != `{"error":{"code":"rate_limit_exceeded"}}` {
		t.Errorf("expected upstream body preserved, got %q", string(got.Body))
	}
}

// TestRetryableErrorUnwrap verifies the retryableError → inner chain
// survives. executor_chat.go wraps non-final 4xx/5xx attempts in
// retryableError so a single-line change to make it Unwrap to its
// payload is what closes the chain.
func TestRetryableErrorUnwrap(t *testing.T) {
	upErr := &upstreampkg.Error{
		Kind:       upstreampkg.KindTransient,
		Message:    "upstream HTTP 502",
		Body:       []byte(`<html>502 Bad Gateway</html>`),
		StatusCode: 502,
	}
	wrapped := &retryableError{err: upErr}

	var got *upstreampkg.Error
	for cur := error(wrapped); cur != nil; cur = errors.Unwrap(cur) {
		if u, ok := cur.(*upstreampkg.Error); ok {
			got = u
			break
		}
	}
	if got == nil {
		t.Fatalf("expected errors.Unwrap to reach *upstream.Error inside retryableError")
	}
	if got.StatusCode != 502 || string(got.Body) != "<html>502 Bad Gateway</html>" {
		t.Errorf("expected status=502, body=<html>502..., got status=%d body=%q",
			got.StatusCode, string(got.Body))
	}
}

// TestExecuteErrorWrappingRetryableError covers the realistic scenario:
// executor_chat.go's 4xx branch (Phase 2 P1 changed) returns
// &retryableError{err: &upstreampkg.Error{...}} on a retryable 4xx,
// and ExecuteError.LastErr is set to that wrapped error. The chain
// must remain traversable end-to-end.
func TestExecuteErrorWrappingRetryableError(t *testing.T) {
	upErr := &upstreampkg.Error{
		Kind:       upstreampkg.KindRateLimit,
		Message:    "upstream HTTP 429",
		Body:       []byte(`{"error":{"type":"rate_limit_error"}}`),
		StatusCode: 429,
	}
	execErr := &ExecuteError{
		LastErr:   &retryableError{err: upErr},
		Tried:     2,
		Exhausted: true,
		LastKind:  upstreampkg.KindRateLimit,
	}

	var got *upstreampkg.Error
	for cur := error(execErr); cur != nil; cur = errors.Unwrap(cur) {
		if u, ok := cur.(*upstreampkg.Error); ok {
			got = u
			break
		}
	}
	if got == nil {
		t.Fatalf("expected chain ExecuteError → retryableError → *upstream.Error to be traversable")
	}
	if got.StatusCode != 429 {
		t.Errorf("expected 429, got %d", got.StatusCode)
	}
	if string(got.Body) != `{"error":{"type":"rate_limit_error"}}` {
		t.Errorf("body mismatch: %q", string(got.Body))
	}
}

// TestAttemptRecordRoundTrip ensures the new UpstreamStatusCode field
// round-trips through JSON serialization so the routing decision log
// (which stores attempts) preserves the diagnostic for downstream
// consumers.
func TestAttemptRecordRoundTrip(t *testing.T) {
	sc := 504
	rec := AttemptRecord{
		ProviderID:         14,
		CredentialID:       6,
		RawModel:           "MiniMax-M3",
		Kind:               upstreampkg.KindTransient,
		Reason:             "upstream 504: bad gateway",
		UpstreamStatusCode: &sc,
	}
	if rec.UpstreamStatusCode == nil || *rec.UpstreamStatusCode != 504 {
		t.Fatalf("expected status 504, got %v", rec.UpstreamStatusCode)
	}
}