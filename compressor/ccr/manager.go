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
}

// NewManager creates a new CCR manager with the given configuration.
func NewManager(config Config, redisClient *redis.Client, db *sql.DB) (*Manager, error) {
	m := &Manager{
		config:  config,
		l2Redis: redisClient,
		l3DB:    db,
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

	return m, nil
}

// Put stores data in all enabled cache tiers.
func (m *Manager) Put(ctx context.Context, hash string, data []byte, sessionID string) error {
	metrics := m.getMetrics()
	atomic.AddInt64(&metrics.PutTotal, 1)

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
		`
		now := time.Now()
		_, err := m.l3DB.ExecContext(ctx, query, hash, data, sessionID, now, now, now)
		if err != nil {
			slog.Warn("ccr: L3 put failed", "hash", hash, "error", err)
			atomic.AddInt64(&metrics.Errors, 1)
		}
	}

	return nil
}

// Get retrieves data from cache tiers (L1 → L2 → L3).
func (m *Manager) Get(ctx context.Context, hash string) ([]byte, error) {
	metrics := m.getMetrics()
	atomic.AddInt64(&metrics.GetTotal, 1)

	// L1: sync.Map
	if m.config.L1Enabled && m.l1Cache != nil {
		if val, ok := m.l1Cache.Load(hash); ok {
			atomic.AddInt64(&metrics.L1Hits, 1)
			return val.([]byte), nil
		}
		atomic.AddInt64(&metrics.L1Misses, 1)
	}

	// L2: Redis
	if m.config.L2Enabled && m.l2Redis != nil {
		key := m.config.L2Prefix + hash
		data, err := m.l2Redis.Get(ctx, key).Bytes()
		if err == nil {
			atomic.AddInt64(&metrics.L2Hits, 1)
			// Backfill L1
			if m.config.L1Enabled && m.l1Cache != nil {
				m.l1Cache.Store(hash, data)
			}
			return data, nil
		}
		if err != redis.Nil {
			slog.Warn("ccr: L2 get failed", "hash", hash, "error", err)
			atomic.AddInt64(&metrics.Errors, 1)
		}
		atomic.AddInt64(&metrics.L2Misses, 1)
	}

	// L3: PostgreSQL
	if m.config.L3Enabled && m.l3DB != nil {
		query := `SELECT data FROM ccr_cache WHERE hash = $1`
		var data []byte
		err := m.l3DB.QueryRowContext(ctx, query, hash).Scan(&data)
		if err == nil {
			atomic.AddInt64(&metrics.L3Hits, 1)
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
		}
		atomic.AddInt64(&metrics.L3Misses, 1)
	}

	return nil, fmt.Errorf("ccr: hash not found: %s", hash)
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

// Close closes the CCR manager and releases resources.
func (m *Manager) Close() error {
	// sync.Map doesn't need closing
	return nil
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
