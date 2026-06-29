// Package reconnect provides configuration for client reconnection and
// response replay behavior. When enabled, the gateway caches vendor
// responses so disconnected clients can recover them on reconnect
// without re-sending to the LLM.
//
// Design: 2026-06-29 断线重连增强
//
// See also: pending/ for the storage layer, sessions/handler.go for
// the GET endpoint, and relay/stream.go for the capture hooks.
package reconnect

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Config controls reconnect behavior. Zero value = disabled (backwards compatible).
type Config struct {
	// Enabled is the global kill-switch. When false, all reconnect
	// logic is skipped (caching still happens for async retry, but
	// clients cannot retrieve cached responses).
	Enabled bool

	// AutoResumeByDefault controls whether clients automatically
	// try cache resume on every request (when true) or only when
	// explicitly requested via forceResumeFromCache flag (when false).
	//
	// Recommendation: start false, enable after verifying cache hit rate.
	AutoResumeByDefault bool

	// CacheTTL is how long completed responses remain in Redis.
	// Zero falls back to pending.DefaultTTL (7 days).
	CacheTTL time.Duration

	// MaxCacheBodyBytes is the cap on cached response size. Larger
	// responses are truncated with a stub pointing to request_logs.
	// Zero falls back to pending.MaxBodyBytes (1 MiB).
	MaxCacheBodyBytes int

	// TenantOverrides allows per-tenant configuration. If a tenant
	// is present in this map, its config takes precedence over the
	// global defaults above.
	TenantOverrides map[string]*TenantConfig

	mu sync.RWMutex
}

// TenantConfig is the per-tenant reconnect configuration.
type TenantConfig struct {
	Enabled             bool
	AutoResumeByDefault bool
}

// NewConfig returns a Config with sensible defaults (disabled by default
// for backwards compatibility).
func NewConfig() *Config {
	return &Config{
		Enabled:             false, // must opt-in
		AutoResumeByDefault: false,
		TenantOverrides:     make(map[string]*TenantConfig),
	}
}

// IsEnabledForTenant returns true if reconnect is enabled globally
// and not explicitly disabled for this tenant.
func (c *Config) IsEnabledForTenant(tenantID string) bool {
	if !c.Enabled {
		return false
	}
	c.mu.RLock()
	defer c.mu.RUnlock()
	if override, ok := c.TenantOverrides[tenantID]; ok {
		return override.Enabled
	}
	return true
}

// ShouldAutoResume returns true if the given tenant should automatically
// attempt cache resume (vs requiring explicit forceResumeFromCache flag).
func (c *Config) ShouldAutoResume(tenantID string) bool {
	if !c.IsEnabledForTenant(tenantID) {
		return false
	}
	c.mu.RLock()
	defer c.mu.RUnlock()
	if override, ok := c.TenantOverrides[tenantID]; ok {
		return override.AutoResumeByDefault
	}
	return c.AutoResumeByDefault
}

// SetTenantConfig updates the per-tenant override. Pass nil to remove.
func (c *Config) SetTenantConfig(tenantID string, tc *TenantConfig) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if tc == nil {
		delete(c.TenantOverrides, tenantID)
	} else {
		c.TenantOverrides[tenantID] = tc
	}
}

// Manager handles reconnect configuration persistence and hot-reload.
type Manager struct {
	config *Config
	db     *pgxpool.Pool
	mu     sync.RWMutex
}

// NewManager creates a Manager with the given initial config and
// optional database connection for persistence (pass nil to disable
// persistence; config will only live in memory).
func NewManager(cfg *Config, db *pgxpool.Pool) *Manager {
	if cfg == nil {
		cfg = NewConfig()
	}
	return &Manager{
		config: cfg,
		db:     db,
	}
}

// GetConfig returns the current global config (safe for concurrent reads).
func (m *Manager) GetConfig() *Config {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.config
}

// UpdateGlobal atomically updates global reconnect settings.
func (m *Manager) UpdateGlobal(enabled, autoResumeByDefault bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.config.Enabled = enabled
	m.config.AutoResumeByDefault = autoResumeByDefault
}

// UpdateTenant atomically updates tenant-specific settings.
func (m *Manager) UpdateTenant(tenantID string, tc *TenantConfig) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.config.SetTenantConfig(tenantID, tc)
}

// LoadFromDB loads reconnect configuration from the database.
// Currently a no-op stub; extend when persistence is needed.
func (m *Manager) LoadFromDB(ctx context.Context) error {
	if m.db == nil {
		return nil
	}
	// TODO: implement schema + query when config persistence is needed.
	// For now, config lives in memory (set via env vars or admin API).
	return nil
}

// SaveToDB persists the current configuration to the database.
// Currently a no-op stub; extend when persistence is needed.
func (m *Manager) SaveToDB(ctx context.Context) error {
	if m.db == nil {
		return nil
	}
	// TODO: implement INSERT/UPDATE when persistence is needed.
	return nil
}
