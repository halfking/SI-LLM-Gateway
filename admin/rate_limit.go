package admin

import (
	"os"
	"strconv"
	"sync"
	"time"
)

// RateLimiter implements a simple per-key fixed-window rate limit.
// In-memory only; resets on gateway restart.
//
// Two-stage API: Check + Record. Successful operations don't burn
// the limit, only failures do. This matches the UX intent for the
// login endpoint (legitimate password rotations shouldn't lock
// ops out of the admin console).
type RateLimiter struct {
	mu     sync.Mutex
	counts map[string]*window
	limit  int
	win    time.Duration
}

type window struct {
	count   int
	resetAt time.Time
}

// NewRateLimiter creates a fixed-window rate limiter.
// limit: max failures per window. window: e.g. 1*time.Minute.
func NewRateLimiter(limit int, win time.Duration) *RateLimiter {
	return &RateLimiter{
		counts: make(map[string]*window),
		limit:  limit,
		win:    win,
	}
}

// Check returns true if the key is under the failure cap (does not
// increment). The caller should follow up with Record on a failure,
// Reset on a success. A stale window (past resetAt) is treated as a
// fresh window so callers don't stay locked out forever after the
// window expires; Record on the next failure will reset the clock.
func (r *RateLimiter) Check(key string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	w, ok := r.counts[key]
	if !ok {
		return true
	}
	if time.Now().After(w.resetAt) {
		// Window expired — drop the entry so the next Record starts
		// fresh. Keep Check idempotent (no increment).
		delete(r.counts, key)
		return true
	}
	return w.count < r.limit
}

// Record increments the failure counter for key (creating the
// window on first failure). Reset on next success is the caller's
// responsibility.
func (r *RateLimiter) Record(key string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now()
	w, ok := r.counts[key]
	if !ok || now.After(w.resetAt) {
		r.counts[key] = &window{count: 1, resetAt: now.Add(r.win)}
		return
	}
	w.count++
}

// Reset clears the counter for a key (call on success).
func (r *RateLimiter) Reset(key string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.counts, key)
}

// Size returns the number of tracked keys (for tests).
func (r *RateLimiter) Size() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.counts)
}

// loginLimiterLimit / loginLimiterWindow are env-overridable so ops
// can loosen the cap in dev / after a password rotation spike.
// Defaults: 10 failures per IP per minute.
func loginLimiterLimit() int {
	if v := os.Getenv("LLM_GATEWAY_LOGIN_LIMIT"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return 10
}

func loginLimiterWindow() time.Duration {
	if v := os.Getenv("LLM_GATEWAY_LOGIN_WINDOW"); v != "" {
		if d, err := time.ParseDuration(v); err == nil && d > 0 {
			return d
		}
	}
	return time.Minute
}

// Global login rate limiter. Limit + window are env-configurable
// (LLM_GATEWAY_LOGIN_LIMIT, LLM_GATEWAY_LOGIN_WINDOW). Counts only
// FAILED attempts — successful logins never burn the cap.
var loginLimiter = NewRateLimiter(loginLimiterLimit(), loginLimiterWindow())
