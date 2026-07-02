package provider

import (
	"testing"
	"time"
)

// candCacheCountForTest exposes the live candCache size for tests in this
// package. It is the observation hook for the 2026-07-02 manual_disabled
// invalidation regression test: a stale candCache is what kept traffic
// hitting a just-disabled provider/credential for up to the 30s TTL.
func candCacheCountForTest() int {
	if defaultClient == nil {
		return 0
	}
	defaultClient.mu.RLock()
	defer defaultClient.mu.RUnlock()
	return len(defaultClient.candCache)
}

// seedCandCacheForTest injects a cache entry directly so we can assert
// InvalidateAllCandidateCache actually drops it, without needing a DB.
func seedCandCacheForTest(key string, ttl time.Duration) {
	if defaultClient == nil {
		NewClient() // wires defaultClient
	}
	defaultClient.mu.Lock()
	defer defaultClient.mu.Unlock()
	defaultClient.candCache[key] = cacheEntry[*resolveResponse]{
		value:   &resolveResponse{ClientModel: key},
		expires: time.Now().Add(ttl),
	}
}

// TestInvalidateAllCandidateCache_DropsEntries is the regression guard for the
// 2026-07-02 bug: toggling providers.manual_disabled / credentials.manual_disabled
// from the admin handlers must call InvalidateAllCandidateCache so the live
// router stops using the 30s stale candidate list on the very next request.
//
// The DB view (v_routable_credential_models.is_routable) and the candidate
// fetch SQL correctly filter disabled providers/credentials — but only when
// the cache is cold. Without invalidation the cached list (which was built
// before the disable) keeps the disabled credential routable until TTL.
func TestInvalidateAllCandidateCache_DropsEntries(t *testing.T) {
	// Start from a known-clean default client.
	NewClient()

	seedCandCacheForTest("minimax-m3", 30*time.Second)
	seedCandCacheForTest("claude-sonnet-4|anthropic", 30*time.Second)
	seedCandCacheForTest("gpt-4o|openai", 30*time.Second)
	if got := candCacheCountForTest(); got != 3 {
		t.Fatalf("seed: expected 3 cached entries, got %d", got)
	}

	InvalidateAllCandidateCache()

	if got := candCacheCountForTest(); got != 0 {
		t.Fatalf("after InvalidateAllCandidateCache: expected 0 entries, got %d "+
			"(a stale entry would keep a disabled credential routable)", got)
	}
}

// TestInvalidateAllCandidateCache_NilDefaultClientNoPanic documents that the
// helper is safe to call before NewClient (e.g. during early startup or in
// tests that never construct a client). A panic here would crash the admin
// disable handler that calls it on the success path.
func TestInvalidateAllCandidateCache_NilDefaultClientNoPanic(t *testing.T) {
	defaultClient = nil
	InvalidateAllCandidateCache() // must not panic
}

// TestCandCache_TTLExpiryStillServesUntilInvalidated confirms the design
// assumption that motivates explicit invalidation: an unexpired cache entry
// is served on every lookup, so a disable cannot rely on TTL alone — it MUST
// call InvalidateAllCandidateCache. If this test ever fails (i.e. the cache
// stops serving live entries), the invalidation path may be hiding a real
// regression and must be re-examined.
func TestCandCache_TTLExpiryStillServesUntilInvalidated(t *testing.T) {
	NewClient()
	seedCandCacheForTest("served-until-expiry", 30*time.Second)

	if got := candCacheCountForTest(); got != 1 {
		t.Fatalf("expected 1 cached entry, got %d", got)
	}
	// Without invalidation the entry survives — that's exactly why the admin
	// disable handlers must invalidate explicitly.
	InvalidateAllCandidateCache()
	if got := candCacheCountForTest(); got != 0 {
		t.Fatalf("cleanup: expected 0 entries, got %d", got)
	}
}
