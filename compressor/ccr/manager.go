package ccr

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"
)

// Manager implements three-tier CCR storage.
type Manager struct {
	config  Config
	l1Cache *sync.Map // Simple in-memory cache
	l2Redis *redis.Client
	l3DB    *sql.DB
	metrics atomic.Value // *Metrics

	// Lifecycle management for the background metrics updater
	stop chan struct{}  // closed by Close() to signal shutdown
	done chan struct{}  // closed by metricsUpdater() when it exits
	once sync.Once      // ensures stop is closed only once
}

// NewManager creates a new CCR manager with the given configuration.
func NewManager(config Config, redisClient *redis.Client, db *sql.DB) (*Manager, error) {
	m := &Manager{
		config:  config,
		l2Redis: redisClient,
		l3DB:    db,
		stop:     make(chan struct{}),
		done:     make(chan struct{}),
	}

	// Initialize L1 cache (simple sync.Map for now)
	if config.L1Enabled {
		m.l1Cache = &sync.Map{}
	}

	// Initialize metrics
	m.metrics.Store(&Metrics{})

	// Auto-migrate L3 schema if enabled
	if config.L3Enabled && db != nil {
		if err := m.migrateSchema(); err != nil {
			return nil, fmt.Errorf("failed to migrate CCR schema: %w", err)
		}
	}

	// Start background metrics updater (updates Prometheus gauges every 10s)
	go m.metricsUpdater()

	return m, nil
}

// Close stops the background metrics updater and releases resources.
// Safe to call multiple times (idempotent via sync.Once).
func (m *Manager) Close() error {
	m.once.Do(func() {
		close(m.stop)
	})
	// Wait for the goroutine to exit (with a sane upper bound so we
	// don't hang forever in tests).
	select {
	case <-m.done:
	case <-time.After(2 * time.Second):
		slog.Warn("ccr: metricsUpdater did not exit within 2s")
	}
	return nil
}

// metricsUpdater runs in the background and periodically updates Prometheus gauge metrics.
// Exits cleanly when Close() is called.
func (m *Manager) metricsUpdater() {
	defer close(m.done)
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-m.stop:
			return
		case <-ticker.C:
			m.UpdateMetrics()
		}
	}
}

// Put stores data in all enabled cache tiers.
func (m *Manager) Put(ctx context.Context, hash string, data []byte, sessionID string) error {
	metrics := m.getMetrics()
	atomic.AddInt64(&metrics.PutTotal, 1)
	RecordPut()

	// L1: sync.Map
	if m.config.L1Enabled && m.l1Cache != nil {
		m.l1Cache.Store(hash, data)
	}

	// L2: Redis
	if m.config.L2Enabled && m.l2Redis != nil {
		key := m.config.L2Prefix + hash
		if err := m.l2Redis.Set(ctx, key, data, m.config.L2TTL).Err(); err != nil {
			slog.Warn("ccr: L2 put failed", "hash", hash, "error", err)
			atomic.AddInt64(&metrics.Errors, 1)
			RecordError()
		}
	}

	// L3: PostgreSQL
	if m.config.L3Enabled && m.l3DB != nil {
		query := `
			INSERT INTO ccr_cache (hash, data, session_id, created_at, updated_at, accessed_at, access_count)
			VALUES ($1, $2, $3, $4, $5, $6, 0)
			ON CONFLICT (hash) DO UPDATE SET
				data = EXCLUDED.data,
				session_id = EXCLUDED.session_id,
				updated_at = EXCLUDED.updated_at
			WHERE ccr_cache.updated_at <= EXCLUDED.updated_at
		`
		now := time.Now()
		_, err := m.l3DB.ExecContext(ctx, query, hash, data, sessionID, now, now, now)
		if err != nil {
			slog.Warn("ccr: L3 put failed", "hash", hash, "error", err)
			atomic.AddInt64(&metrics.Errors, 1)
			RecordError()
		}
	}

	return nil
}

// Get retrieves data from cache tiers (L1 → L2 → L3).
func (m *Manager) Get(ctx context.Context, hash string) ([]byte, error) {
	return m.GetForSession(ctx, hash, "")
}

// GetForSession retrieves CCR data, optionally scoping to a sessionID.
// When sessionID is non-empty, the call is rejected (returns ErrUnauthorized)
// unless the stored row's session_id matches. This prevents a session from
// retrieving data from a different session just by guessing the hash.
//
// L1/L2 caches are shared across sessions and do not carry session
// metadata — only L3 enforces the sessionID match. Callers that need
// strict isolation MUST use this function (never Get).
func (m *Manager) GetForSession(ctx context.Context, hash, sessionID string) ([]byte, error) {
	metrics := m.getMetrics()
	atomic.AddInt64(&metrics.GetTotal, 1)
	RecordGet()

	// SECURITY: When sessionID is provided, we MUST enforce session isolation.
	// L1 and L2 don't store sessionID, so they can't validate ownership.
	// Therefore, when sessionID != "", we skip L1/L2 and go straight to L3.
	if sessionID != "" {
		if !m.config.L3Enabled || m.l3DB == nil {
			// L3 disabled but caller requires session-scoped lookup.
			// Refuse to serve data from L1/L2 as they can't enforce isolation.
			return nil, fmt.Errorf("ccr: session-scoped lookup requires L3 (PostgreSQL)")
		}

		// L3 query with session validation
		query := `SELECT data, session_id FROM ccr_cache WHERE hash = $1`
		var data []byte
		var rowSessionID string
		err := m.l3DB.QueryRowContext(ctx, query, hash).Scan(&data, &rowSessionID)
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		if err != nil {
			atomic.AddInt64(&metrics.Errors, 1)
			RecordError()
			return nil, fmt.Errorf("ccr: L3 get failed: %w", err)
		}
		if rowSessionID != sessionID {
			// Treat as not-found rather than leaking that the hash exists.
			atomic.AddInt64(&metrics.Errors, 1)
			RecordError()
			return nil, ErrUnauthorized
		}
		atomic.AddInt64(&metrics.L3Hits, 1)
		RecordCacheHit("L3")
		// Backfill L1 (content only; future unscoped lookups can use it)
		if m.config.L1Enabled && m.l1Cache != nil {
			m.l1Cache.Store(hash, data)
		}
		return data, nil
	}

	// Unscoped lookup: try L1 → L2 → L3 (no session validation)
	// L1: sync.Map
	if m.config.L1Enabled && m.l1Cache != nil {
		if val, ok := m.l1Cache.Load(hash); ok {
			atomic.AddInt64(&metrics.L1Hits, 1)
			RecordCacheHit("L1")
			return val.([]byte), nil
		}
		// Only count miss if L1 is actually enabled AND cache is non-nil.
		// (Previous bug: miss was counted when L1 was disabled but m.l1Cache was non-nil.)
		atomic.AddInt64(&metrics.L1Misses, 1)
		RecordCacheMiss("L1")
	}

	// L2: Redis
	if m.config.L2Enabled && m.l2Redis != nil {
		key := m.config.L2Prefix + hash
		data, err := m.l2Redis.Get(ctx, key).Bytes()
		if err == nil {
			atomic.AddInt64(&metrics.L2Hits, 1)
			RecordCacheHit("L2")
			// Backfill L1
			if m.config.L1Enabled && m.l1Cache != nil {
				m.l1Cache.Store(hash, data)
			}
			return data, nil
		}
		if err != redis.Nil {
			slog.Warn("ccr: L2 get failed", "hash", hash, "error", err)
			atomic.AddInt64(&metrics.Errors, 1)
			RecordError()
		}
		atomic.AddInt64(&metrics.L2Misses, 1)
		RecordCacheMiss("L2")
	}

	// L3: PostgreSQL
	if m.config.L3Enabled && m.l3DB != nil {
		query := `SELECT data FROM ccr_cache WHERE hash = $1`
		var data []byte
		err := m.l3DB.QueryRowContext(ctx, query, hash).Scan(&data)
		if err == nil {
			atomic.AddInt64(&metrics.L3Hits, 1)
			RecordCacheHit("L3")
			// Backfill L2 and L1
			if m.config.L2Enabled && m.l2Redis != nil {
				key := m.config.L2Prefix + hash
				m.l2Redis.Set(ctx, key, data, m.config.L2TTL)
			}
			if m.config.L1Enabled && m.l1Cache != nil {
				m.l1Cache.Store(hash, data)
			}

			// Update access tracking
			updateQuery := `UPDATE ccr_cache SET access_count = access_count + 1, accessed_at = $1 WHERE hash = $2`
			m.l3DB.ExecContext(ctx, updateQuery, time.Now(), hash)

			return data, nil
		}
		if err != sql.ErrNoRows {
			slog.Warn("ccr: L3 get failed", "hash", hash, "error", err)
			atomic.AddInt64(&metrics.Errors, 1)
			RecordError()
		}
		atomic.AddInt64(&metrics.L3Misses, 1)
		RecordCacheMiss("L3")
	}

	return nil, fmt.Errorf("%w: %s", ErrNotFound, hash)
}

// Delete removes data from all cache tiers.
func (m *Manager) Delete(ctx context.Context, hash string) error {
	// L1: sync.Map
	if m.config.L1Enabled && m.l1Cache != nil {
		m.l1Cache.Delete(hash)
	}

	// L2: Redis
	if m.config.L2Enabled && m.l2Redis != nil {
		key := m.config.L2Prefix + hash
		m.l2Redis.Del(ctx, key)
	}

	// L3: PostgreSQL
	if m.config.L3Enabled && m.l3DB != nil {
		query := `DELETE FROM ccr_cache WHERE hash = $1`
		m.l3DB.ExecContext(ctx, query, hash)
	}

	return nil
}

// GetMetrics returns a snapshot of current metrics.
func (m *Manager) GetMetrics() Metrics {
	return *m.getMetrics()
}

// ResetMetrics resets all metrics to zero.
func (m *Manager) ResetMetrics() {
	m.metrics.Store(&Metrics{})
}

// getMetrics returns the current metrics pointer.
func (m *Manager) getMetrics() *Metrics {
	return m.metrics.Load().(*Metrics)
}

// migrateSchema creates the CCR table if it doesn't exist.
func (m *Manager) migrateSchema() error {
	query := `
		CREATE TABLE IF NOT EXISTS ccr_cache (
			hash VARCHAR(24) PRIMARY KEY,
			data BYTEA NOT NULL,
			session_id VARCHAR(64),
			created_at TIMESTAMP NOT NULL DEFAULT NOW(),
			accessed_at TIMESTAMP NOT NULL DEFAULT NOW(),
			access_count INT NOT NULL DEFAULT 0,
			updated_at TIMESTAMP NOT NULL DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_ccr_session ON ccr_cache(session_id);
		CREATE INDEX IF NOT EXISTS idx_ccr_created ON ccr_cache(created_at);
	`
	_, err := m.l3DB.Exec(query)
	return err
}
