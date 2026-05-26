// Package pool implements identity-bound HTTP connection pools.
//
// Each pool is keyed by (identity_hash[:16], provider_id, credential_id) so
// that connections are isolated per virtual identity + provider + credential.
// This prevents credential mix-up and allows per-identity connection limits.
package pool

import (
	"context"
	"crypto/tls"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

const (
	maxIdleConnsPerHost    = 32
	maxConnsPerHost        = 128
	idleConnTimeout        = 90 * time.Second
	healthCheckInterval    = 30 * time.Second
	healthCheckTimeout     = 5 * time.Second
	degradedThreshold      = 3
)

// PoolState represents the health state of a connection pool.
type PoolState int32

const (
	PoolActive   PoolState = 0
	PoolDegraded PoolState = 1
	PoolDead     PoolState = 2
)

func (s PoolState) String() string {
	switch s {
	case PoolActive:
		return "active"
	case PoolDegraded:
		return "degraded"
	case PoolDead:
		return "dead"
	default:
		return "unknown"
	}
}

// PoolKey uniquely identifies a connection pool.
type PoolKey struct {
	IdentityHash string
	ProviderID   int
	CredentialID int
}

func (k PoolKey) String() string {
	id := k.IdentityHash
	if len(id) > 16 {
		id = id[:16]
	}
	return fmt.Sprintf("%s/%d/%d", id, k.ProviderID, k.CredentialID)
}

// Pool manages a set of HTTP connections for a specific identity+provider+credential.
type Pool struct {
	key       PoolKey
	transport *http.Transport
	client    *http.Client
	probeURL  string

	state       atomic.Int32
	failCount   atomic.Int32
	mu          sync.Mutex
	stopCh      chan struct{}
}

// NewPool creates a new connection pool.
func NewPool(key PoolKey, probeURL string) *Pool {
	transport := &http.Transport{
		MaxIdleConns:        maxConnsPerHost,
		MaxIdleConnsPerHost: maxIdleConnsPerHost,
		IdleConnTimeout:     idleConnTimeout,
		DialContext: (&net.Dialer{
			Timeout:   10 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		TLSClientConfig: &tls.Config{InsecureSkipVerify: false},
	}

	p := &Pool{
		key:      key,
		transport: transport,
		client:   &http.Client{Transport: transport, Timeout: 120 * time.Second},
		probeURL: probeURL,
		stopCh:   make(chan struct{}),
	}
	p.state.Store(int32(PoolActive))
	return p
}

// Client returns the HTTP client for this pool.
func (p *Pool) Client() *http.Client { return p.client }

// State returns the current pool health state.
func (p *Pool) State() PoolState { return PoolState(p.state.Load()) }

// StartHealthCheck begins periodic health probing.
func (p *Pool) StartHealthCheck() {
	go p.healthLoop()
}

// StopHealthCheck stops periodic health probing.
func (p *Pool) StopHealthCheck() {
	p.mu.Lock()
	defer p.mu.Unlock()
	select {
	case <-p.stopCh:
		// already closed
	default:
		close(p.stopCh)
	}
}

// RecordFailure increments the failure counter and may mark the pool degraded.
func (p *Pool) RecordFailure() {
	count := p.failCount.Add(1)
	if count >= degradedThreshold {
		p.state.Store(int32(PoolDegraded))
		slog.Warn("pool degraded", "key", p.key.String(), "failures", count)
	}
}

// RecordSuccess resets the failure counter and marks the pool active.
func (p *Pool) RecordSuccess() {
	p.failCount.Store(0)
	p.state.Store(int32(PoolActive))
}

// Close shuts down the pool's idle connections.
func (p *Pool) Close() {
	p.StopHealthCheck()
	p.transport.CloseIdleConnections()
}

func (p *Pool) healthLoop() {
	defer func() {
		if r := recover(); r != nil {
			slog.Error("pool healthLoop panic", "recover", r)
		}
	}()
	interval := healthCheckInterval
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			p.probe()
			// Speed up probing when degraded: check every 10s instead of 30s
			newInterval := healthCheckInterval
			if p.State() == PoolDegraded {
				newInterval = 10 * time.Second
			}
			if newInterval != interval {
				interval = newInterval
				ticker.Reset(interval)
			}
		case <-p.stopCh:
			return
		}
	}
}

func (p *Pool) probe() {
	if p.probeURL == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), healthCheckTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, p.probeURL, nil)
	if err != nil {
		return
	}
	resp, err := p.client.Do(req)
	if err != nil || resp.StatusCode >= 500 {
		p.RecordFailure()
		if resp != nil {
			resp.Body.Close()
		}
		return
	}
	resp.Body.Close()
	p.RecordSuccess()
}

// ---------------------------------------------------------------------------
// PoolManager — global registry of identity-bound pools
// ---------------------------------------------------------------------------

// PoolManager manages all connection pools keyed by (identity, provider, credential).
type PoolManager struct {
	mu    sync.RWMutex
	pools map[PoolKey]*Pool
}

// NewPoolManager creates a new pool manager.
func NewPoolManager() *PoolManager {
	return &PoolManager{pools: make(map[PoolKey]*Pool)}
}

// GetOrCreate returns the pool for the given key, creating it if needed.
func (pm *PoolManager) GetOrCreate(key PoolKey, probeURL string) *Pool {
	pm.mu.RLock()
	p, ok := pm.pools[key]
	pm.mu.RUnlock()
	if ok {
		return p
	}

	pm.mu.Lock()
	defer pm.mu.Unlock()

	// Double-check after acquiring write lock
	if p, ok = pm.pools[key]; ok {
		return p
	}
	p = NewPool(key, probeURL)
	p.StartHealthCheck()
	pm.pools[key] = p
	slog.Info("pool created", "key", key.String(), "probe", probeURL)
	return p
}

// Get returns the pool for the given key, or nil.
func (pm *PoolManager) Get(key PoolKey) *Pool {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	return pm.pools[key]
}

// CloseAll stops and closes all pools.
func (pm *PoolManager) CloseAll() {
	pm.mu.Lock()
	defer pm.mu.Unlock()
	for key, p := range pm.pools {
		p.Close()
		delete(pm.pools, key)
	}
}

// Stats returns the count of pools by state.
func (pm *PoolManager) Stats() map[string]int {
	pm.mu.RLock()
	defer pm.mu.RUnlock()
	stats := map[string]int{"active": 0, "degraded": 0, "dead": 0}
	for _, p := range pm.pools {
		switch p.State() {
		case PoolActive:
			stats["active"]++
		case PoolDegraded:
			stats["degraded"]++
		case PoolDead:
			stats["dead"]++
		}
	}
	return stats
}
