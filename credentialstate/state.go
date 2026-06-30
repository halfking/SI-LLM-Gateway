// Package credentialstate provides unified real-time state management for
// credential+model combinations. It replaces scattered state tracking across
// circuit breakers, route node state, and probe state with a single source of truth.
//
// Core responsibilities:
//   - Track success/failure rates for each (credential_id, model) pair
//   - Maintain availability status (healthy/degraded/unavailable)
//   - Coordinate active probing with anti-flap protection
//   - Provide real-time state queries for routing decisions
//   - Support state change notifications
//
// Architecture:
//   - L1: In-memory LRU cache (1000 entries, <1ms latency)
//   - L2: Redis cache (5min TTL, <5ms latency)
//   - L3: PostgreSQL persistence (credential_model_state table)
//
// Usage:
//   manager := credentialstate.NewManager(db, redis)
//   manager.Start(ctx)
//
//   // Record request result
//   manager.RecordSuccess(ctx, credID, model, latencyMs)
//   manager.RecordFailure(ctx, credID, model, errorKind)
//
//   // Query state for routing
//   state, err := manager.GetState(ctx, credID, model)
//   if state.Available {
//       // route to this credential
//   }
package credentialstate

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// State represents the real-time health status of a credential+model combination.
type State struct {
	CredentialID int64  `json:"credential_id"`
	Model        string `json:"model"`

	// Status and availability
	Status    StatusEnum `json:"status"`    // healthy/degraded/unavailable/probing/unknown
	Available bool       `json:"available"` // whether routable

	// Request statistics
	TotalRequests        int     `json:"total_requests"`
	SuccessCount         int     `json:"success_count"`
	FailureCount         int     `json:"failure_count"`
	ConsecutiveFailures  int     `json:"consecutive_failures"`
	ConsecutiveSuccesses int     `json:"consecutive_successes"`
	SuccessRate          float64 `json:"success_rate"` // 0-100

	// Recent error
	LastErrorKind string    `json:"last_error_kind,omitempty"`
	LastErrorAt   time.Time `json:"last_error_at,omitempty"`

	// Recent success
	LastSuccessAt time.Time `json:"last_success_at,omitempty"`
	LastLatencyMs int       `json:"last_latency_ms,omitempty"`

	// Probe state
	LastProbeAt              time.Time `json:"last_probe_at,omitempty"`
	LastProbeSuccess         bool      `json:"last_probe_success"`
	LastProbeLatencyMs       int       `json:"last_probe_latency_ms,omitempty"`
	ProbeConsecutiveFailures int       `json:"probe_consecutive_failures"`
	ProbeConsecutiveSuccesses int      `json:"probe_consecutive_successes"`
	NextProbeAt              time.Time `json:"next_probe_at,omitempty"`
	ProbeIntervalSec         int       `json:"probe_interval_sec"`

	// Anti-flap (transient failure tracking)
	TransientFailureCount      int       `json:"transient_failure_count"`
	TransientFailureWindowStart time.Time `json:"transient_window_start,omitempty"`
	PendingVerification        bool      `json:"pending_verification"`
	VerificationScheduledAt    time.Time `json:"verification_scheduled_at,omitempty"`

	// Degradation info
	DegradedAt       time.Time `json:"degraded_at,omitempty"`
	DegradedReason   string    `json:"degraded_reason,omitempty"`
	UnavailableAt    time.Time `json:"unavailable_at,omitempty"`
	UnavailableReason string   `json:"unavailable_reason,omitempty"`
	UnavailableUntil time.Time `json:"unavailable_until,omitempty"`

	// Metadata
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// StatusEnum defines the possible states of a credential+model combination.
type StatusEnum string

const (
	StatusHealthy      StatusEnum = "healthy"      // Normal operation, success rate > 80%
	StatusDegraded     StatusEnum = "degraded"     // Degraded, success rate 50-80%
	StatusUnavailable  StatusEnum = "unavailable"  // Not available, success rate < 50% or probe failed
	StatusProbing      StatusEnum = "probing"      // Active probing in progress
	StatusUnknown      StatusEnum = "unknown"      // No data yet
)

// IsHealthy returns true if the state indicates normal operation.
func (s *State) IsHealthy() bool {
	return s.Status == StatusHealthy && s.Available
}

// IsDegraded returns true if the state is degraded but still available.
func (s *State) IsDegraded() bool {
	return s.Status == StatusDegraded && s.Available
}

// IsUnavailable returns true if the state is unavailable for routing.
func (s *State) IsUnavailable() bool {
	return s.Status == StatusUnavailable || !s.Available
}

// ShouldProbe returns true if this state needs probing.
func (s *State) ShouldProbe(now time.Time) bool {
	if s.NextProbeAt.IsZero() {
		return false
	}
	return now.After(s.NextProbeAt) || now.Equal(s.NextProbeAt)
}

// CalculateSuccessRate computes the success rate percentage.
func (s *State) CalculateSuccessRate() float64 {
	if s.TotalRequests == 0 {
		return 0
	}
	return (float64(s.SuccessCount) / float64(s.TotalRequests)) * 100
}

// DetermineStatus determines the appropriate status based on success rate and probe results.
func (s *State) DetermineStatus() StatusEnum {
	// If actively probing, return probing status
	if s.PendingVerification {
		return StatusProbing
	}

	// If explicitly marked unavailable with a reason
	if !s.UnavailableReason == "" && time.Now().Before(s.UnavailableUntil) {
		return StatusUnavailable
	}

	// No data yet
	if s.TotalRequests == 0 && s.LastProbeAt.IsZero() {
		return StatusUnknown
	}

	rate := s.CalculateSuccessRate()

	// Check consecutive failures (strong signal of unavailability)
	if s.ConsecutiveFailures >= 5 {
		return StatusUnavailable
	}

	// Check probe failures
	if s.ProbeConsecutiveFailures >= 3 {
		return StatusUnavailable
	}

	// Success rate based classification
	if rate >= 80 {
		return StatusHealthy
	} else if rate >= 50 {
		return StatusDegraded
	} else if s.TotalRequests >= 5 { // Need minimum sample size
		return StatusUnavailable
	}

	// Default to unknown for insufficient data
	return StatusUnknown
}

// RequestResult represents the outcome of a single request.
type RequestResult struct {
	Success   bool
	LatencyMs int
	ErrorKind string
	Timestamp time.Time
}

// ProbeResult represents the outcome of a probe attempt.
type ProbeResult struct {
	Success   bool
	LatencyMs int
	Error     string
	Timestamp time.Time
}

// Config holds configuration for the state manager.
type Config struct {
	// Cache sizes
	MemoryCacheSize int           // LRU cache size, default 1000
	RedisTTL        time.Duration // Redis cache TTL, default 5min

	// Probe intervals based on state
	HealthyProbeInterval     time.Duration // default 60s
	DegradedProbeInterval    time.Duration // default 30s
	UnavailableProbeInterval time.Duration // default 10s

	// Anti-flap configuration
	AntiFlapWindowDuration   time.Duration // default 30s
	AntiFlapFailureThreshold int           // default 3
	VerifyDelay1             time.Duration // default 2s (first verification)
	VerifyDelay2             time.Duration // default 5s (second verification)

	// Degradation thresholds
	DegradationThreshold   float64 // success rate threshold for degraded, default 80%
	UnavailableThreshold   float64 // success rate threshold for unavailable, default 50%
	MinSampleSize          int     // minimum requests before applying thresholds, default 5
	ConsecutiveFailureMax  int     // consecutive failures to mark unavailable, default 5

	// Recovery thresholds
	RecoverySuccessCount int // consecutive successes needed to recover, default 2
}

// DefaultConfig returns the default configuration.
func DefaultConfig() *Config {
	return &Config{
		MemoryCacheSize:          1000,
		RedisTTL:                 5 * time.Minute,
		HealthyProbeInterval:     60 * time.Second,
		DegradedProbeInterval:    30 * time.Second,
		UnavailableProbeInterval: 10 * time.Second,
		AntiFlapWindowDuration:   30 * time.Second,
		AntiFlapFailureThreshold: 3,
		VerifyDelay1:             2 * time.Second,
		VerifyDelay2:             5 * time.Second,
		DegradationThreshold:     80.0,
		UnavailableThreshold:     50.0,
		MinSampleSize:            5,
		ConsecutiveFailureMax:    5,
		RecoverySuccessCount:     2,
	}
}

// Key returns a string key for this credential+model combination.
func Key(credentialID int64, model string) string {
	// Use a simple format that's easy to parse
	return fmt.Sprintf("%d:%s", credentialID, model)
}

// ParseKey parses a key back into credential ID and model.
func ParseKey(key string) (int64, string, error) {
	parts := strings.SplitN(key, ":", 2)
	if len(parts) != 2 {
		return 0, "", fmt.Errorf("invalid key format: %s", key)
	}
	credID, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return 0, "", fmt.Errorf("invalid credential_id in key: %s", parts[0])
	}
	return credID, parts[1], nil
}
