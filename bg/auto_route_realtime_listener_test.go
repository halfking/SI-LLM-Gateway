package bg

import (
	"testing"
)

// TestAutoRouteRealtimeListener_HandleNotification_InvalidatesCandCache
// is the regression test for the 2026-07-03 minimax-m3 incident
// (request a69a71a05e6610adcf55df32f2618797): the NOTIFY path must
// synchronously invalidate the candCache, not just schedule the
// debounced autoroute.Index refresh.
func TestAutoRouteRealtimeListener_HandleNotification_InvalidatesCandCache(t *testing.T) {
	l := NewAutoRouteRealtimeListener(nil, nil, nil)

	var calls int
	l.invalidateCandCache = func() { calls++ }

	l.handleNotification("credential_model_bindings:UPDATE:42")

	if calls != 1 {
		t.Errorf("invalidateCandCache should fire exactly once per NOTIFY, got %d", calls)
	}
	if !l.pending {
		t.Errorf("pending should be set after a NOTIFY")
	}
}

// TestAutoRouteRealtimeListener_HandleNotification_NilInvalidator
// confirms the listener stays functional when the provider client is
// not wired (defaultClient == nil → helper is a no-op anyway). The
// debounced index refresh must still be scheduled.
func TestAutoRouteRealtimeListener_HandleNotification_NilInvalidator(t *testing.T) {
	l := NewAutoRouteRealtimeListener(nil, nil, nil)

	l.handleNotification("credentials:UPDATE:7")

	if !l.pending {
		t.Errorf("pending should be set even without an invalidator")
	}
}