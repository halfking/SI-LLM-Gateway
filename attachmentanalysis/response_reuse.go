package attachmentanalysis

import (
	"sync"
	"time"
)

// ResponseReuseCache is an in-memory, bounded cache of upstream LLM
// response text keyed by request_id. It implements ResponseReuseSource.
//
// The relay pipeline calls SetResponseText when the full assistant
// response is materialized (both streaming and non-streaming paths
// converge there). The analyzer's worker then reads it back via
// GetDescription to populate the description field from source A —
// zero additional cost, since the response was already captured for
// request_logs anyway.
//
// Entries expire after a few minutes (analysis runs within seconds of
// archival, so a short TTL is plenty) and the map is capped to avoid
// unbounded growth on high-traffic deployments.
type ResponseReuseCache struct {
	mu     sync.RWMutex
	items  map[string]responseCacheEntry
	maxLen int
	ttl    time.Duration
}

type responseCacheEntry struct {
	text      string
	tenantID  string
	expiresAt time.Time
}

// NewResponseReuseCache builds a cache. Defaults: 4096 entries, 10m TTL.
func NewResponseReuseCache() *ResponseReuseCache {
	return &ResponseReuseCache{
		items:  make(map[string]responseCacheEntry),
		maxLen: 4096,
		ttl:    10 * time.Minute,
	}
}

// SetResponseText stores the assistant response text for a request. Called
// from the relay telemetry path (non-blocking; the mutex is short-lived).
func (c *ResponseReuseCache) SetResponseText(requestID, tenantID, text string) {
	if c == nil || requestID == "" || text == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	// Eviction: if the map has grown past maxLen, opportunistically drop
	// expired entries (cheap sweep, not a full scan).
	if len(c.items) >= c.maxLen {
		now := time.Now()
		for k, v := range c.items {
			if now.After(v.expiresAt) {
				delete(c.items, k)
			}
		}
		// If still full after sweeping expired entries, drop ~10% at random
		// (map iteration order) to make room — better to lose a stale reuse
		// opportunity than to grow unbounded.
		if len(c.items) >= c.maxLen {
			i := 0
			target := c.maxLen / 10
			for k := range c.items {
				delete(c.items, k)
				i++
				if i >= target {
					break
				}
			}
		}
	}
	c.items[requestID] = responseCacheEntry{
		text:      text,
		tenantID:  tenantID,
		expiresAt: time.Now().Add(c.ttl),
	}
}

// GetDescription implements ResponseReuseSource.
func (c *ResponseReuseCache) GetDescription(requestID, tenantID string) (string, bool) {
	if c == nil || requestID == "" {
		return "", false
	}
	c.mu.RLock()
	entry, ok := c.items[requestID]
	c.mu.RUnlock()
	if !ok {
		return "", false
	}
	if time.Now().After(entry.expiresAt) {
		return "", false
	}
	// Tenant scope check: super_admin (tenantID="") can read any; otherwise
	// must match. This mirrors the attachments manager's ListByRequestID.
	if tenantID != "" && entry.tenantID != "" && entry.tenantID != tenantID {
		return "", false
	}
	return entry.text, true
}
