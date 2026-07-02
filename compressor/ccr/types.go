// Package ccr implements the Compress-Cache-Retrieve storage layer.
// It provides three-tier caching for compressed data:
// - L1: In-memory Ristretto cache (nanosecond access)
// - L2: Redis distributed cache (millisecond access, 24h TTL)
// - L3: PostgreSQL persistent storage (session-bound lifetime)
package ccr

import (
	"context"
	"errors"
	"time"
)

// Sentinel errors returned by Manager.GetForSession. Callers (especially
// tool handlers like relay/CCRRetrievalTool) MUST distinguish ErrNotFound
// from ErrUnauthorized so they can return 404 vs 403 to the LLM — never
// leak the existence of a hash to an unauthorized caller.
var (
	ErrNotFound      = errors.New("ccr: entry not found")
	ErrUnauthorized  = errors.New("ccr: caller session does not match entry owner")
)

// Store is the interface for CCR storage backends.
type Store interface {
	// Put stores data under the given hash, attributed to sessionID.
	// A later GetForSession(hash, sessionID) call must succeed when the
	// sessionID matches; with an empty sessionID the entry is shared.
	Put(ctx context.Context, hash string, data []byte, sessionID string) error

	// Get retrieves data by hash without any session check. Use only when
	// the caller has already authorized the lookup through other means
	// (e.g. when replaying from a CCR marker embedded in the same
	// session's outbound body, which the gateway already serialized).
	Get(ctx context.Context, hash string) ([]byte, error)

	// GetForSession retrieves data by hash AND verifies the caller is the
	// same session that originally wrote the entry. Returns ErrNotFound
	// if the row doesn't exist OR exists but belongs to a different
	// session (no leak of existence). sessionID="" skips the check.
	GetForSession(ctx context.Context, hash, sessionID string) ([]byte, error)

	// Delete removes data by hash.
	Delete(ctx context.Context, hash string) error

	// Close closes the store and releases resources.
	Close() error
}

// Config configures the CCR manager.
type Config struct {
	// L1 cache configuration
	L1Enabled  bool
	L1MaxItems int64
	L1MaxCost  int64

	// L2 Redis configuration
	L2Enabled bool
	L2TTL     time.Duration
	L2Prefix  string

	// L3 PostgreSQL configuration
	L3Enabled bool

	// Metrics
	EnableMetrics bool
}

// DefaultConfig returns the default CCR configuration.
func DefaultConfig() Config {
	return Config{
		L1Enabled:     true,
		L1MaxItems:    1000,
		L1MaxCost:     100 * 1024 * 1024, // 100 MB
		L2Enabled:     true,
		L2TTL:         24 * time.Hour,
		L2Prefix:      "ccr:",
		L3Enabled:     true,
		EnableMetrics: true,
	}
}

// Metrics tracks CCR storage statistics.
type Metrics struct {
	L1Hits   int64
	L1Misses int64
	L2Hits   int64
	L2Misses int64
	L3Hits   int64
	L3Misses int64
	PutTotal int64
	GetTotal int64
	Errors   int64
}

// HitRatio returns the overall cache hit ratio.
func (m *Metrics) HitRatio() float64 {
	total := m.L1Hits + m.L1Misses + m.L2Hits + m.L2Misses + m.L3Hits + m.L3Misses
	if total == 0 {
		return 0
	}
	hits := m.L1Hits + m.L2Hits + m.L3Hits
	return float64(hits) / float64(total)
}