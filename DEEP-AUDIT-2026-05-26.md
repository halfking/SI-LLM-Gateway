# LLM Gateway Go Data Plane — Deep Audit & Optimization Plan

> **Audited**: 2026-05-26 | 18 source files, ~3,578 LOC | 11 test suites
> **Status**: Sprint 1 complete, pre-production hardening phase

---

## Issue Summary

| Severity | Count | Category |
|----------|-------|----------|
| **P0 Critical** | 5 | Data loss, cascade failure, security |
| **P1 High** | 6 | Logic bugs, resource leaks |
| **P2 Medium** | 14 | Robustness, performance, defensive |
| **P3 Low** | 11 | Code quality, cosmetics |

---

## P0 — Critical (Must Fix Before Production)

### P0-1: Circuit Breaker Half-Open Allows Unlimited Probes
- **File**: `circuit/breaker.go:157-158`
- **Problem**: `StateHalfOpen` returns `true` for ALL concurrent requests, not just one probe. Under load, dozens of requests hit a failing upstream simultaneously, defeating the circuit breaker.
- **Fix**: Use `atomic.CompareAndSwap` to allow only the first request through half-open.
```go
case StateHalfOpen:
    return b.probeCount.CompareAndSwap(0, 1)
```
Reset `probeCount` on state transitions.

### P0-2: Audit Success Never Set — 100% Failure Rate in Audit Trail
- **File**: `relay/handler.go:179-199, 397-438`
- **Problem**: `auditBuilder.Success(true)` is never called. All requests (including successful 200 OK) are recorded as failures. Audit dashboards show 100% failure rate.
- **Fix**: Add `.Success(true)` in both streaming success path (after StreamChat) and non-streaming success path (after writing response).

### P0-3: Request Trace ID Lost When Client Doesn't Provide One
- **File**: `middleware/requestid.go:14-22`
- **Problem**: Generated request ID is only set on response writer (`w.Header`), never on `r.Header` or request context. Handler reads `r.Header.Get("X-Request-Id")` → empty string. Upstream never receives the ID.
- **Fix**: Add `r.Header.Set("X-Request-Id", id)` after generation.

### P0-4: Graceful Shutdown Closes Pools Before Draining In-Flight Requests
- **File**: `cmd/gateway/main.go:136-141`
- **Problem**: `pools.CloseAll()` and `lim.Stop()` called BEFORE `srv.Shutdown()`. In-flight streaming responses lose their connections mid-transfer.
- **Fix**: Reorder to: `srv.Shutdown()` → `lim.Stop()` → `pools.CloseAll()`.

### P0-5: Unbounded Pool Growth — Goroutine & FD Leak
- **File**: `pool/pool.go:215-235`
- **Problem**: `PoolManager.pools` map only grows. Each pool spawns a health-check goroutine + `http.Transport` with 128 max connections. No eviction, no TTL, no max size.
- **Fix**: Add LRU eviction based on last-access time. Periodically close pools idle beyond threshold (e.g., 5 minutes). Track `lastUsed atomic.Int64` per pool.

---

## P1 — High (Fix Before First Real Workload)

### P1-1: Request Body Not Closed on Read Error
- **File**: `relay/handler.go:108-119`
- **Problem**: `r.Body.Close()` only called on success path. On `io.ReadAll` error, body is leaked.
- **Fix**: Add `defer r.Body.Close()` immediately after reading.

### P1-2: Silent Body Truncation at 32 MiB
- **File**: `relay/handler.go:108`
- **Problem**: `LimitReader(r.Body, 32<<20)` silently truncates. No error is returned. Truncated JSON sent upstream.
- **Fix**: Read 32 MiB + 1 byte. If extra byte exists, return 413 Request Entity Too Large.

### P1-3: JSON Re-serialization Destroys Request Body Format
- **File**: `relay/handler.go:443-457` (`replaceModelInRequestBody`)
- **Problem**: `json.Marshal` reorders keys (random map iteration), destroys formatting. Some providers are sensitive to key order.
- **Fix**: Use byte-level replacement: find `"model":"<old>"` pattern and replace in-place, or use `json.Decoder` with `json.Encoder` preserving key order via ordered map.

### P1-4: Context.Canceled Recorded as Circuit Success
- **File**: `relay/handler.go:354-356`
- **Problem**: Empty `ErrorKind` (from context.Canceled) triggers `cm.RecordSuccess()`. Client disconnections mask upstream issues.
- **Fix**: Define `KindCanceled` explicitly. Skip circuit recording for canceled requests entirely.

### P1-5: Resolver Thundering Herd on Cache Expiry
- **File**: `resolve/resolve.go:64-95`
- **Problem**: N concurrent requests for the same expired model → N identical HTTP calls to Python endpoint. Cache stampede amplifies upstream traffic 10-100x.
- **Fix**: Use `golang.org/x/sync/singleflight` to deduplicate in-flight resolves.

### P1-6: Identity "unknown" Seed Creates Massive Collision Domain
- **File**: `identity/identity.go:56-57`
- **Problem**: All clients without fingerprint headers produce the same identity hash. Millions of distinct clients share one pool, one rate limit.
- **Fix**: When no seed is available, use client source IP as fallback. Add remote addr to seed composition.

---

## P2 — Medium (Fix for Production Hardening)

### P2-1: No Global Panic Recovery Middleware
- **File**: `cmd/gateway/main.go:104-106`
- **Fix**: Add `middleware.WithRecovery` as outermost middleware.

### P2-2: PoolDead State Unreachable
- **File**: `pool/pool.go:35`
- **Fix**: Add deadThreshold (e.g., 10 consecutive failures) → PoolDead, stop health check loop.

### P2-3: Pool Degraded→Active Flapping (Single Success Resets)
- **File**: `pool/pool.go:136-139`
- **Fix**: Require N consecutive successes (2-3) before transitioning back to Active.

### P2-4: Pool Health Check Reuses Same Transport (Circular Dependency)
- **File**: `pool/pool.go:187`
- **Fix**: Use a separate lightweight transport for probes.

### P2-5: RecordFailure Ignores Breaker's Configured Policy
- **File**: `circuit/breaker.go:196`
- **Fix**: Use `b.coolingPolicy` instead of always looking up `defaultPolicies[kind]`.

### P2-6: Resolver Cache Never Evicts Internally
- **File**: `resolve/resolve.go:132-141`
- **Fix**: Start background goroutine to call `EvictExpired()` periodically.

### P2-7: Resolver Serves No Stale Entry During Outage
- **File**: `resolve/resolve.go:72-75`
- **Fix**: Serve stale entry if fetch fails, instead of degrading to passthrough.

### P2-8: Transform Matrix Not Thread-Safe
- **File**: `transform/transform.go:46-51`
- **Fix**: Use `sync.RWMutex` or `atomic.Value` for safe concurrent Load/Resolve.

### P2-9: JSONSink Memory Leak (Re-Slice Doesn't Free Old Array)
- **File**: `audit/audit.go:214-217`
- **Fix**: Copy to new slice when trimming: `trimmed := make([]Event, j.maxLen); copy(trimmed, j.lastN[...])`.

### P2-10: MultiSink No Per-Sink Panic Recovery
- **File**: `audit/audit.go:192-196`
- **Fix**: Wrap each sink's Emit in `defer/recover`.

### P2-11: 120s Context Timeout Kills Long Streams
- **File**: `relay/handler.go:323`
- **Fix**: Use longer timeout (e.g., 600s) for streaming requests, or derive from client context only.

### P2-12: Temporary Goroutine Leak on Stream Read Timeout
- **File**: `relay/stream.go:93-121`
- **Fix**: Acceptable but bounded. Could use `runtime.SetFinalizer` pattern or explicit cancel propagation.

### P2-13: Models Handler Forwards Client Auth to Python
- **File**: `relay/models.go:72-79`
- **Fix**: Strip or replace Authorization header with internal service auth.

### P2-14: No Salt in SHA-256 Identity Hash
- **File**: `identity/identity.go:179-180`
- **Fix**: Add per-deployment salt from environment variable.

---

## P3 — Low (Code Quality)

| ID | File | Issue |
|----|------|-------|
| P3-1 | `identity.go:156-161` | `firstNonEmpty` is a no-op, should be variadic or removed |
| P3-2 | `limiter.go:259-276` | Identity semaphores never evicted (unbounded map growth) |
| P3-3 | `errorsx/classify.go:28-35` | String-based error classification is fragile |
| P3-4 | `audit.go:35` | `CompletionToken` (singular) vs `completion_tokens` (plural) |
| P3-5 | `audit.go:248-249` | `rand.Read` error silently discarded |
| P3-6 | `audit.go:99` | Request ID only 32 bits entropy |
| P3-7 | `logging.go:16-22` | `WriteHeader` always forwards even on second call |
| P3-8 | `pool.go:58-64` | `PoolKey.String()` truncates to 16 chars, conflates distinct keys |
| P3-9 | `pool.go:115-124` | No WaitGroup for health loop goroutine exit |
| P3-10 | `transform.go:92` | No file size limit on YAML read |
| P3-11 | `audit.go:252-256` | Two different checksum functions with different semantics |

---

## Recommended Fix Order (Sprint 2)

### Phase A: Critical Safety (P0)
1. P0-3: Fix request ID propagation (1 line change)
2. P0-2: Fix audit Success field (2 lines added)
3. P0-4: Fix shutdown ordering (3 lines moved)
4. P0-1: Fix half-open probe limit (circuit breaker core logic)
5. P0-5: Add pool eviction (new goroutine + lastUsed tracking)

### Phase B: Request Integrity (P1)
6. P1-1: Body close on error
7. P1-2: Body truncation detection
8. P1-3: Replace model without re-serialization
9. P1-4: KindCanceled + skip circuit recording
10. P1-5: Singleflight for resolver
11. P1-6: IP fallback for identity seed

### Phase C: Robustness (P2)
12. P2-1: Global recovery middleware
13. P2-2 + P2-3: Pool state machine (Dead state + success threshold)
14. P2-5: Circuit breaker policy fix
15. P2-6 + P2-7: Resolver eviction + stale-while-revalidate
16. P2-8: Transform matrix mutex
17. P2-9 + P2-10: Audit sink fixes
18. P2-11: Streaming timeout
19. P2-13: Models auth strip
20. P2-14: Identity hash salt

### Phase D: Code Quality (P3)
21-31: Address P3 items incrementally
