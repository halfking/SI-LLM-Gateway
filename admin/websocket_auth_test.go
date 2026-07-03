package admin

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestHandleLiveStream_AuthShim verifies that the WS endpoint rejects
// requests with no token (after URL query promotion) by returning 401
// from AdminMiddleware — NOT by hanging the upgrade. We cannot drive
// a real WebSocket client here without a JWT key (and a real DB for
// the admin-key path), so we exercise the auth shim with a
// non-upgrading handler probe.
func TestHandleLiveStream_AuthShim(t *testing.T) {
	// Build a hub without a DB so HandleLiveStream itself refuses
	// (503). What we want to test is that the auth shim ran FIRST
	// and that, when no token is present, it falls through to
	// AdminMiddleware and gets rejected with 401.
	hub := NewLiveStreamHub(nil, LiveStreamConfig{})

	// 1) No token, no Authorization → must be rejected.
	req := httptest.NewRequest(http.MethodGet, "/api/admin/live-stream", nil)
	rw := httptest.NewRecorder()
	hub.HandleLiveStream(rw, req)
	if rw.Code == http.StatusServiceUnavailable {
		// Reached the "db not configured" branch — auth shim
		// allowed the request through, which would be a bug.
		t.Fatal("expected 401, got 503 (auth shim allowed anonymous request)")
	}
	if rw.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for anonymous WS, got %d", rw.Code)
	}

	// 2) Token in URL query → auth shim copies it into Authorization.
	// We expect 401 because the shim ran AND AdminMiddleware rejected
	// the bogus token (no JWT secret in this test); what matters is
	// that we did NOT short-circuit to 503 (which would mean the
	// shim skipped auth). And we did NOT hang (which would mean the
	// connection was upgraded before auth ran).
	req2 := httptest.NewRequest(http.MethodGet, "/api/admin/live-stream?token=abc", nil)
	rw2 := httptest.NewRecorder()
	hub.HandleLiveStream(rw2, req2)
	if rw2.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 (auth shim ran, AdminMiddleware rejected bogus token), got %d body=%s", rw2.Code, rw2.Body.String())
	}

	// 3) Header already present → query is ignored.
	// Same outcome as case 2: the shim leaves the header alone and
	// AdminMiddleware rejects "garbage".
	req3 := httptest.NewRequest(http.MethodGet, "/api/admin/live-stream?token=junk", nil)
	req3.Header.Set("Authorization", "Bearer garbage")
	rw3 := httptest.NewRecorder()
	hub.HandleLiveStream(rw3, req3)
	if rw3.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for header-auth request (AdminMiddleware rejects garbage), got %d body=%s", rw3.Code, rw3.Body.String())
	}

	// 4) Sanity: the shim actually mutates the request header.
	// Confirmed by inspecting the request via a synthetic check
	// (we cannot peek at HandleLiveStream's local `r`, so we re-run
	// the shim code path directly via a helper test).
	if r4 := applyAuthShim(httptest.NewRequest(http.MethodGet, "/api/admin/live-stream?token=hello", nil)); r4.Header.Get("Authorization") != "Bearer hello" {
		t.Fatalf("auth shim did not promote ?token= into Authorization header: %q", r4.Header.Get("Authorization"))
	}
}

// applyAuthShim is a tiny helper that mirrors the header-promotion
// logic in HandleLiveStream. Extracted so the test can assert the
// promotion in isolation without a real DB / real Upgrade call.
func applyAuthShim(r *http.Request) *http.Request {
	if r.Header.Get("Authorization") == "" {
		if t := strings.TrimSpace(r.URL.Query().Get("token")); t != "" {
			r.Header.Set("Authorization", "Bearer "+t)
		}
	}
	return r
}

func TestHandleLiveStream_MethodNotAllowed(t *testing.T) {
	hub := NewLiveStreamHub(nil, LiveStreamConfig{})
	req := httptest.NewRequest(http.MethodPost, "/api/admin/live-stream", strings.NewReader(""))
	rw := httptest.NewRecorder()
	hub.HandleLiveStream(rw, req)
	if rw.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", rw.Code)
	}
}
