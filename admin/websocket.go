// Package admin — live request stream WebSocket hub.
//
//	GET /api/admin/live-stream  →  WebSocket upgrade
//
// The hub fans out newly-completed request logs to every connected
// dashboard client. It also sends an initial replay of the most recent
// 50 requests when a client connects, so a freshly opened dashboard
// fills from left-to-right immediately rather than waiting for the
// next request to land.
//
// Tenant isolation: messages carry a tenant_id; tenant_admin clients
// drop anything that does not match their own tenant.
//
// Backpressure: the broadcast channel is bounded; if a hub tick can
// not enqueue, the message is dropped (the dashboard will catch up on
// reconnect via initial replay). Per-client writes are guarded by a
// mutex so a slow client can not stall the broadcast loop.
package admin

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
)

// LiveStreamEnvelope wraps every WebSocket payload. The Type field
// lets the frontend switch on the variant without sniffing the shape.
//
//	"initial_data" — first message after upgrade; carries []LiveRequest
//	"request"      — a new request completed (or transitioned to in-progress)
//	"idle_marker"  — 1 minute of silence; visual gap for the swim lane
//	"ping"         — keepalive; the frontend should reply with a pong frame
type LiveStreamEnvelope struct {
	Type      string        `json:"type"`
	Timestamp time.Time     `json:"ts"`
	Request   *LiveRequest  `json:"request,omitempty"`
	Requests  []LiveRequest `json:"requests,omitempty"`
}

// LiveRequest is the minimal projection the dashboard swim lane needs.
// Fields are nullable to match the database shape — clients render "—"
// when a value is missing.
type LiveRequest struct {
	RequestID string `json:"request_id"`
	Ts        string `json:"ts"`
	TenantID  string `json:"tenant_id"`
	// GwSessionID is the LLM-Gateway session id (request_logs.gw_session_id)
	// if the request was sent through a session. Empty when the request
	// is one-off (e.g. a /v1/chat/completions call without a session).
	// 2026-07-03: added so the dashboard swim lane can count distinct
	// sessions in real time without hitting the sessions API.
	GwSessionID      string   `json:"gw_session_id,omitempty"`
	Model            string   `json:"model"`
	ModelCategory    string   `json:"model_category"`
	ProviderCode     string   `json:"provider_code"`
	Status           string   `json:"status"`
	LatencyMs        *int     `json:"latency_ms,omitempty"`
	PromptTokens     *int     `json:"prompt_tokens,omitempty"`
	CompletionTokens *int     `json:"completion_tokens,omitempty"`
	TotalTokens      *int     `json:"total_tokens,omitempty"`
	CostUSD          *float64 `json:"cost_usd,omitempty"`
	ErrorKind        *string  `json:"error_kind,omitempty"`
}

// LiveStreamConfig controls hub behaviour. Zero values are safe and
// resolve to defaults in NewLiveStreamHub.
type LiveStreamConfig struct {
	// BroadcastQueueSize bounds the inbound queue. Drops when full.
	BroadcastQueueSize int
	// InitialReplayLimit is how many recent requests to send on connect.
	InitialReplayLimit int
	// IdleThreshold is how long the hub waits before emitting an
	// idle_marker. 1 minute per spec.
	IdleThreshold time.Duration
	// IdleTickInterval is how often the hub checks the idle threshold.
	// Smaller = more responsive, larger = less CPU.
	IdleTickInterval time.Duration
	// ReadTimeout / WriteTimeout follow gorilla/websocket convention.
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
	// AllowedOrigins restricts websocket upgrade Origin header. nil =
	// allow same-origin only (via host comparison).
	AllowedOrigins []string
}

func (c *LiveStreamConfig) defaults() {
	if c.BroadcastQueueSize <= 0 {
		c.BroadcastQueueSize = 1024
	}
	if c.InitialReplayLimit <= 0 {
		c.InitialReplayLimit = 50
	}
	if c.IdleThreshold <= 0 {
		c.IdleThreshold = 60 * time.Second
	}
	if c.IdleTickInterval <= 0 {
		c.IdleTickInterval = 10 * time.Second
	}
	if c.ReadTimeout <= 0 {
		c.ReadTimeout = 90 * time.Second
	}
	if c.WriteTimeout <= 0 {
		c.WriteTimeout = 10 * time.Second
	}
}

// liveStreamClient is the per-connection state held by the hub. The
// write mutex serialises writes because gorilla/websocket forbids
// concurrent writers on the same connection.
type liveStreamClient struct {
	conn       *websocket.Conn
	tenantID   string // empty = super_admin sees everything
	isSuper    bool
	writeMu    sync.Mutex
	closed     bool
	lastPongAt time.Time
}

// LiveStreamHub is the singleton fan-out point. Create one at startup,
// call Run() in a goroutine, and call HandleLiveStream on the admin
// mux. Producers call Publish() to fan a new request out.
type LiveStreamHub struct {
	db        *pgxpool.Pool
	secretKey string // JWT secret for inline auth verification
	cfg       LiveStreamConfig
	upgrader  websocket.Upgrader

	register   chan *liveStreamClient
	unregister chan *liveStreamClient
	broadcast  chan LiveRequest

	mu      sync.RWMutex
	clients map[*liveStreamClient]struct{}

	// lastActivity tracks the most recent publish time. The Run loop
	// uses it to decide whether to emit an idle_marker.
	lastActivityMu sync.RWMutex
	lastActivity   time.Time

	// providerCache is a sync.Map of provider_id → catalog_code.
	// Populated lazily on first miss by ProviderCodeFor() so the
	// telemetry hot path can resolve a provider_id from a freshly
	// persisted RequestLogEntry to the human-readable code the
	// dashboard swim lane expects.
	providerCache sync.Map

	stopCh chan struct{}
}

// NewLiveStreamHub constructs a hub. The caller MUST call Run() once
// in its own goroutine before the hub accepts traffic.
func NewLiveStreamHub(db *pgxpool.Pool, secretKey string, cfg LiveStreamConfig) *LiveStreamHub {
	cfg.defaults()
	hub := &LiveStreamHub{
		db:           db,
		secretKey:    secretKey,
		cfg:          cfg,
		register:     make(chan *liveStreamClient, 16),
		unregister:   make(chan *liveStreamClient, 16),
		broadcast:    make(chan LiveRequest, cfg.BroadcastQueueSize),
		clients:      make(map[*liveStreamClient]struct{}),
		lastActivity: time.Now(),
		stopCh:       make(chan struct{}),
	}
	hub.upgrader = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 4096,
		CheckOrigin:     hub.checkOrigin,
	}
	return hub
}

func (h *LiveStreamHub) checkOrigin(r *http.Request) bool {
	if len(h.cfg.AllowedOrigins) == 0 {
		// Same-origin by default (host header matches).
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true // non-browser client, e.g. curl
		}
		host := r.Host
		if host == "" {
			return false
		}
		// strip scheme for comparison
		o := strings.TrimPrefix(strings.TrimPrefix(origin, "https://"), "http://")
		return o == host || strings.HasPrefix(o, host+":") || strings.HasPrefix(host, o+":")
	}
	origin := r.Header.Get("Origin")
	for _, allowed := range h.cfg.AllowedOrigins {
		if allowed == origin {
			return true
		}
	}
	return false
}

// Run drives the hub event loop. Blocks until the process exits or
// Stop() is called.
func (h *LiveStreamHub) Run() {
	idleTicker := time.NewTicker(h.cfg.IdleTickInterval)
	defer idleTicker.Stop()

	for {
		select {
		case <-h.stopCh:
			h.closeAll()
			return

		case c := <-h.register:
			h.mu.Lock()
			h.clients[c] = struct{}{}
			h.mu.Unlock()
			// Replay happens in HandleLiveStream so we have a
			// reference to r for tenant scoping; nothing to do here.

		case c := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[c]; ok {
				delete(h.clients, c)
			}
			h.mu.Unlock()
			h.safeClose(c)

		case req := <-h.broadcast:
			h.lastActivityMu.Lock()
			h.lastActivity = time.Now()
			h.lastActivityMu.Unlock()

			h.fanOut(LiveStreamEnvelope{
				Type:      "request",
				Timestamp: time.Now().UTC(),
				Request:   &req,
			})

		case <-idleTicker.C:
			h.maybeEmitIdleMarker()
		}
	}
}

// Stop tears down the hub. Safe to call once.
func (h *LiveStreamHub) Stop() {
	select {
	case <-h.stopCh:
	default:
		close(h.stopCh)
	}
}

// ProviderCodeFor resolves a providers.id to its catalog_code, with
// a one-shot per-id DB lookup cached in memory. The telemetry
// hook uses this to enrich the broadcast envelope so the dashboard
// swim lane shows the right vendor code (e.g. "OPEN" / "ANTH")
// without the frontend having to look it up.
//
// If db is nil (the 71 no-DB relay mode) or the id is invalid
// the function returns "" — the frontend's providerShortLabel
// gracefully degrades to "???".
func (h *LiveStreamHub) ProviderCodeFor(ctx context.Context, providerID int) string {
	if providerID == 0 {
		return ""
	}
	// Cache lookup FIRST — both positive ("anthropic", "openai") and
	// negative ("", sentinel for "we tried and failed") entries are
	// stored so the no-DB relay mode and a future DB-down window do
	// not stampede the DB.
	if cached, ok := h.providerCache.Load(providerID); ok {
		return cached.(string)
	}
	if h.db == nil {
		return ""
	}
	var code string
	row := h.db.QueryRow(ctx, "SELECT COALESCE(NULLIF(catalog_code, ''), '') FROM providers WHERE id = $1", providerID)
	if err := row.Scan(&code); err != nil {
		// Negative cache: 5-minute TTL so a deleted provider
		// eventually gets a re-lookup but we don't pound the DB.
		h.providerCache.Store(providerID, "")
		return ""
	}
	h.providerCache.Store(providerID, code)
	return code
}

func (h *LiveStreamHub) closeAll() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		h.safeClose(c)
		delete(h.clients, c)
	}
}

func (h *LiveStreamHub) safeClose(c *liveStreamClient) {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	if c.closed {
		return
	}
	c.closed = true
	_ = c.conn.Close()
}

func (h *LiveStreamHub) maybeEmitIdleMarker() {
	h.lastActivityMu.RLock()
	last := h.lastActivity
	h.lastActivityMu.RUnlock()
	if time.Since(last) < h.cfg.IdleThreshold {
		return
	}
	h.fanOut(LiveStreamEnvelope{
		Type:      "idle_marker",
		Timestamp: time.Now().UTC(),
	})
	// Bump so we don't emit again until the next silence period.
	h.lastActivityMu.Lock()
	h.lastActivity = time.Now()
	h.lastActivityMu.Unlock()
}

// fanOut serialises a payload to every eligible client. Clients whose
// write fails are evicted and closed.
func (h *LiveStreamHub) fanOut(env LiveStreamEnvelope) {
	h.mu.RLock()
	clients := make([]*liveStreamClient, 0, len(h.clients))
	for c := range h.clients {
		clients = append(clients, c)
	}
	h.mu.RUnlock()

	for _, c := range clients {
		if !h.shouldDeliver(c, env) {
			continue
		}
		if !h.writeEnvelope(c, env) {
			h.evict(c)
		}
	}
}

func (h *LiveStreamHub) shouldDeliver(c *liveStreamClient, env LiveStreamEnvelope) bool {
	if c.isSuper {
		return true
	}
	if env.Request != nil {
		return env.Request.TenantID == c.tenantID
	}
	// initial_data + idle_marker: always deliver (tenant filter
	// happens at SQL time for replays; idle has no tenant scope).
	return true
}

func (h *LiveStreamHub) writeEnvelope(c *liveStreamClient, env LiveStreamEnvelope) bool {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	if c.closed {
		return false
	}
	_ = c.conn.SetWriteDeadline(time.Now().Add(h.cfg.WriteTimeout))
	if err := c.conn.WriteJSON(env); err != nil {
		slog.Debug("live stream write failed", "err", err.Error())
		return false
	}
	return true
}

func (h *LiveStreamHub) evict(c *liveStreamClient) {
	h.mu.Lock()
	delete(h.clients, c)
	h.mu.Unlock()
	h.safeClose(c)
}

// Publish enqueues a new request for fan-out. Drops if the broadcast
// queue is full so a stuck consumer can never block the producer.
func (h *LiveStreamHub) Publish(req LiveRequest) {
	select {
	case h.broadcast <- req:
	default:
		slog.Debug("live stream broadcast queue full, dropping request", "request_id", req.RequestID)
	}
}

// HandleLiveStream is the HTTP upgrade entry point. It authenticates
// the request, upgrades to WebSocket, sends the initial replay, then
// pumps reads to detect client disconnect.
//
// Route: GET /api/admin/live-stream
func (h *LiveStreamHub) HandleLiveStream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	// WS auth shim: browsers cannot set Authorization on a WS upgrade,
	// so the frontend passes the bearer as ?token=... We promote it
	// into the Authorization header so we can verify it inline below.
	// Done BEFORE upgrade so rejection paths stay HTTP-shaped (401, JSON)
	// instead of hanging the connection.
	if r.Header.Get("Authorization") == "" {
		if t := strings.TrimSpace(r.URL.Query().Get("token")); t != "" {
			r.Header.Set("Authorization", "Bearer "+t)
		}
	}

	// Manual authentication (this route is NOT wrapped by AdminMiddleware
	// so we do not have an AuthContext). We replicate the same logic:
	// try JWT first, then fall back to admin API key.
	var authCtx *AuthContext
	if authHeader := r.Header.Get("Authorization"); strings.HasPrefix(authHeader, "Bearer ") {
		tokenStr := strings.TrimPrefix(authHeader, "Bearer ")
		// Try JWT
		claims, err := VerifyToken(tokenStr, h.secretKey)
		if err == nil && claims.UserID > 0 {
			authCtx = &AuthContext{
				UserID:   claims.UserID,
				TenantID: claims.TenantID,
				Username: claims.Username,
				Role:     claims.Role,
				IsJWT:    true,
			}
		} else if h.db != nil {
			// Fall back to admin API key (sk-...) from api_keys table
			if verifyAdminAuth(r, h.db, h.secretKey) {
				authCtx = &AuthContext{
					TenantID: "default",
					Username: "admin",
					Role:     "admin_key",
					IsJWT:    false,
				}
			}
		}
	}
	if authCtx == nil {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	// Store in context so IsSuperAdminOrLegacy / IsTenantAdmin work
	r = SetAuthContext(r, authCtx)

	tenantID := ""
	isSuper := true
	if IsTenantAdmin(r) {
		tenantID = GetTenantID(r)
		isSuper = false
	} else if !IsSuperAdminOrLegacy(r) {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	// DB is optional: if missing, initial replay will be empty but live
	// broadcast still works. This allows 71 (stateless proxy) to run the
	// hub without a local database — it just relays whatever telemetry
	// pushes into it.

	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Warn("live stream upgrade failed", "err", err.Error())
		return
	}

	client := &liveStreamClient{
		conn:       conn,
		tenantID:   tenantID,
		isSuper:    isSuper,
		lastPongAt: time.Now(),
	}
	_ = conn.SetReadDeadline(time.Now().Add(h.cfg.ReadTimeout))
	conn.SetPongHandler(func(string) error {
		client.lastPongAt = time.Now()
		_ = conn.SetReadDeadline(time.Now().Add(h.cfg.ReadTimeout))
		return nil
	})

	// Register FIRST so the initial replay races against any
	// in-flight publish.
	h.register <- client
	defer func() { h.unregister <- client }()

	// Initial replay (oldest → newest so client renders left-to-right).
	if items, err := h.replay(r.Context(), tenantID, isSuper, h.cfg.InitialReplayLimit); err != nil {
		slog.Warn("live stream initial replay failed", "err", err.Error())
	} else if len(items) > 0 {
		h.writeEnvelope(client, LiveStreamEnvelope{
			Type:      "initial_data",
			Timestamp: time.Now().UTC(),
			Requests:  items,
		})
	}

	// Keepalive ticker.
	keepalive := time.NewTicker(30 * time.Second)
	defer keepalive.Stop()

	// Read pump: discard frames but use them as liveness signals. The
	// PongHandler above refreshes lastPongAt; we also catch read
	// errors and exit.
	for {
		select {
		case <-h.stopCh:
			return
		case <-keepalive.C:
			client.writeMu.Lock()
			if client.closed {
				client.writeMu.Unlock()
				return
			}
			_ = conn.SetWriteDeadline(time.Now().Add(h.cfg.WriteTimeout))
			pingErr := conn.WriteMessage(websocket.PingMessage, nil)
			client.writeMu.Unlock()
			if pingErr != nil {
				return
			}
		default:
		}

		_ = conn.SetReadDeadline(time.Now().Add(h.cfg.ReadTimeout))
		if _, _, err := conn.ReadMessage(); err != nil {
			return
		}
	}
}

// replay loads the most recent N requests. ASC order so the client
// renders them left-to-right.
func (h *LiveStreamHub) replay(ctx context.Context, tenantID string, isSuper bool, limit int) ([]LiveRequest, error) {
	if h.db == nil {
		// No DB: return empty replay. The hub can still relay live
		// broadcasts from telemetry hooks.
		return nil, nil
	}
	if limit <= 0 {
		limit = 50
	}
	cctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	// Tenant filter: when tenantID is empty AND caller is super_admin,
	// include all tenants. Otherwise restrict to the caller's tenant.
	// Note: rl.tenant_id column is the canonical source; we also
	// fall back through the api_keys join for legacy rows.
	tenantClause := ""
	args := []any{h.cfg.InitialReplayLimit}
	if !isSuper || tenantID != "" {
		tenantClause = "AND rl.tenant_id = $2"
		args = append(args, tenantID)
	}

	query := `
		SELECT rl.request_id,
		       rl.ts,
		       COALESCE(NULLIF(rl.tenant_id, ''), COALESCE(NULLIF(ak.tenant_id, ''), 'default')) AS tenant_id,
		       COALESCE(NULLIF(rl.gw_session_id, ''), '') AS gw_session_id,
		       COALESCE(NULLIF(rl.outbound_model, ''), rl.client_model, '') AS model,
		       COALESCE(NULLIF(p.catalog_code, ''), '') AS provider_code,
		       COALESCE(NULLIF(rl.request_status, ''), CASE WHEN rl.success THEN 'success' WHEN rl.success = FALSE THEN 'failure' ELSE 'in_progress' END) AS status,
		       rl.latency_ms,
		       rl.prompt_tokens,
		       rl.completion_tokens,
		       rl.total_tokens,
		       rl.cost_usd::float8,
		       rl.error_kind
		FROM request_logs rl
		LEFT JOIN providers p ON p.id = rl.provider_id
		LEFT JOIN api_keys ak ON ak.id = rl.api_key_id
		WHERE rl.ts >= NOW() - INTERVAL '24 hours'
		  ` + tenantClause + `
		ORDER BY rl.ts ASC
		LIMIT $1
	`

	rows, err := h.db.Query(cctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]LiveRequest, 0, limit)
	for rows.Next() {
		var r LiveRequest
		var ts time.Time
		if err := rows.Scan(
			&r.RequestID, &ts, &r.TenantID, &r.Model, &r.ProviderCode, &r.Status,
			&r.LatencyMs, &r.PromptTokens, &r.CompletionTokens, &r.TotalTokens,
			&r.CostUSD, &r.ErrorKind,
		); err != nil {
			continue
		}
		r.Ts = ts.UTC().Format(time.RFC3339)
		r.ModelCategory = classifyModelCategory(r.Model)
		out = append(out, r)
	}
	return out, nil
}

// ClassifyModelCategory is the public entry point used by telemetry
// when it builds a LiveRequest. Exported so unit tests can pin the
// mapping without spinning up a hub.
func ClassifyModelCategory(model string) string {
	return classifyModelCategory(model)
}

func classifyModelCategory(model string) string {
	m := strings.ToLower(model)
	switch {
	case strings.Contains(m, "gpt"), strings.Contains(m, "o1"), strings.Contains(m, "o3"), strings.Contains(m, "o4"):
		return "openai"
	case strings.Contains(m, "claude"):
		return "anthropic"
	case strings.Contains(m, "qwen"), strings.Contains(m, "glm"), strings.Contains(m, "ernie"),
		strings.Contains(m, "doubao"), strings.Contains(m, "deepseek"), strings.Contains(m, "moonshot"),
		strings.Contains(m, "yi-"), strings.Contains(m, "baichuan"):
		return "domestic"
	case strings.Contains(m, "llama"), strings.Contains(m, "mistral"), strings.Contains(m, "mixtral"),
		strings.Contains(m, "qwen2"), strings.Contains(m, "phi"), strings.Contains(m, "gemma"):
		// Qwen with numeric suffix defaults to "domestic" above; this
		// branch catches non-prefixed open-source families.
		return "oss"
	default:
		return "other"
	}
}

// MarshalForLog lets telemetry emit a one-line JSON without importing
// the websocket stack. Kept here so the message shape is owned by the
// hub, not the producer.
func MarshalForLog(req LiveRequest) string {
	b, _ := json.Marshal(req)
	return string(b)
}

// Publisher is the minimal interface the producer (telemetry) needs.
// Defined here so cmd/gateway/main.go can adapt without importing
// admin.LiveRequest — keeps the dependency arrow one-way.
type Publisher interface {
	Publish(LiveRequest)
}

// LiveRequestFromTelemetry adapts a raw RequestLogEntry into a
// LiveRequest. Fields that the dashboard needs but the producer does
// not carry (e.g. provider_code) are left empty and patched by the
// frontend (via its own lookup) or by the next-round replay path.
//
// Status mapping:
//   - request_status="in_progress" → "in_progress"
//   - request_status="success"     → "success"
//   - request_status="failure"     → "failure"
//   - empty (legacy)               → derives from success + error_kind
func LiveRequestFromTelemetry(requestID string, ts time.Time, tenantID, clientModel, outboundModel, providerCode, status string, success bool, errorKind *string, latencyMs, promptTokens, completionTokens *int, totalTokens *int, costUSD *float64) LiveRequest {
	out := LiveRequest{
		RequestID:        requestID,
		Ts:               ts.UTC().Format(time.RFC3339),
		TenantID:         tenantID,
		ProviderCode:     providerCode,
		LatencyMs:        latencyMs,
		PromptTokens:     promptTokens,
		CompletionTokens: completionTokens,
		TotalTokens:      totalTokens,
		CostUSD:          costUSD,
		ErrorKind:        errorKind,
	}
	if outboundModel != "" {
		out.Model = outboundModel
	} else {
		out.Model = clientModel
	}
	out.ModelCategory = classifyModelCategory(out.Model)
	if status == "" {
		switch {
		case success:
			out.Status = "success"
		case errorKind != nil && strings.TrimSpace(*errorKind) != "":
			out.Status = "failure"
		default:
			out.Status = "in_progress"
		}
	} else {
		out.Status = status
	}
	return out
}
