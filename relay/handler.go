package relay

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/kaixuan/llm-gateway-go/circuit"
	"github.com/kaixuan/llm-gateway-go/limiter"
)

// ServiceID maps an API key to a (providerID, credentialID) pair.
// In production this will come from the Python control plane; for now
// it's configured via environment variables.
type ServiceID struct {
	ProviderID   int
	CredentialID int
}

// defaultService returns the default provider+credential from env vars.
func defaultService() ServiceID {
	pid, _ := strconv.Atoi(os.Getenv("LLM_GATEWAY_DEFAULT_PROVIDER"))
	cid, _ := strconv.Atoi(os.Getenv("LLM_GATEWAY_DEFAULT_CREDENTIAL"))
	if pid == 0 {
		pid = 1
	}
	if cid == 0 {
		cid = 1
	}
	return ServiceID{ProviderID: pid, CredentialID: cid}
}

//-----------------------------------------------------------------------------
// Chat handler — integrates circuit breaker + concurrency limiter
//-----------------------------------------------------------------------------

// ChatHandler handles chat completions with circuit breaker and concurrency control.
type ChatHandler struct {
	circuit *circuit.Manager
	limiter *limiter.Limiter
}

// NewChatHandler creates a new chat handler with the given dependencies.
func NewChatHandler(cm *circuit.Manager, l *limiter.Limiter) *ChatHandler {
	return &ChatHandler{circuit: cm, limiter: l}
}

// ServeHTTP handles /v1/chat/completions and /v1/completions.
func (h *ChatHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"error":{"message":"Method not allowed","type":"invalid_request","code":"method_not_allowed"}}`, http.StatusMethodNotAllowed)
		return
	}

	svc := defaultService()

	// ── Circuit breaker check ──────────────────────────────────────────
	if !h.circuit.Allow(svc.ProviderID, svc.CredentialID) {
		state := h.circuit.GetOrCreate(svc.ProviderID, svc.CredentialID).State()
		status := http.StatusServiceUnavailable
		code := "upstream_down"
		if state == circuit.StateQuarantined {
			status = http.StatusBadGateway
			code = "credential_invalid"
		}
		writeJSON(w, status, map[string]any{
			"error": map[string]string{
				"message": "circuit breaker open",
				"type":    "circuit_open",
				"code":    code,
			},
		})
		return
	}

	// ── Extract identity from request ──────────────────────────────────
	identityHash := identityHashFromRequest(r)

	// ── Concurrency limiter ──────────────────────────────────────────
	release, err := h.limiter.AcquireAll(r.Context(), svc.ProviderID, svc.CredentialID, identityHash)
	if err != nil {
		writeJSON(w, http.StatusTooManyRequests, map[string]any{
			"error": map[string]string{
				"message": "concurrency limit reached",
				"type":    "rate_limit_exceeded",
				"code":    "concurrency_limit",
			},
		})
		return
	}

	// ── Proxy the request ──────────────────────────────────────────────
	ChatCompletionsWithHooks(w, r, func(success bool, errKind circuit.ErrorKind) {
		release()
		if success {
			h.circuit.RecordSuccess(svc.ProviderID, svc.CredentialID)
		} else if errKind == "" {
			// Client-side error (e.g. context canceled, 4xx) —
			// don't open the circuit breaker.
		} else {
			h.circuit.RecordFailure(svc.ProviderID, svc.CredentialID, errKind)
			if errKind == circuit.KindRateLimit {
				h.limiter.Shrink(svc.ProviderID, svc.CredentialID)
			}
		}
	})
}

// identityHashFromRequest extracts a consistent identity hash from the request.
// Uses the X-Device-Seed header, or falls back to a hash of X-Request-Id + remote addr.
func identityHashFromRequest(r *http.Request) string {
	if seed := r.Header.Get("X-Device-Seed"); seed != "" {
		return seed
	}
	// Fallback: use request id first 16 chars
	if rid := r.Header.Get("X-Request-Id"); len(rid) >= 16 {
		return rid[:16]
	}
	// Last resort: remote address
	addr := r.RemoteAddr
	if idx := strings.LastIndex(addr, ":"); idx > 0 {
		addr = addr[:idx]
	}
	return addr
}

//-----------------------------------------------------------------------------
// ChatCompletionsWithHooks — proxy with success/failure callback
//-----------------------------------------------------------------------------

// ChatCompletionsWithHooks proxies a chat completion request and calls the
// done callback with success/failure after the request completes.
func ChatCompletionsWithHooks(
	w http.ResponseWriter,
	r *http.Request,
	done func(success bool, errKind circuit.ErrorKind),
) {
	defer func() {
		if rec := recover(); rec != nil {
			slog.Error("panic in chat handler", "panic", rec)
			writeJSON(w, http.StatusInternalServerError, map[string]any{
				"error": map[string]string{
					"message": "internal server error",
					"type":    "server_error",
					"code":    "panic",
				},
			})
			done(false, circuit.KindTransient)
		}
	}()

	rid := r.Header.Get("X-Request-Id")
	slog.Info("chat completions",
		"request_id", rid,
		"upstream", upstream.String(),
	)

	// Check if streaming is requested
	isStream := isStreamRequest(r)

	// Clone the request for upstream
	upstreamReq, err := http.NewRequestWithContext(r.Context(), r.Method, upstream.String()+r.URL.Path, r.Body)
	if err != nil {
		slog.Error("failed to create upstream request", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{
			"error": map[string]string{
				"message": "failed to create upstream request",
				"type":    "server_error",
				"code":    "upstream_error",
			},
		})
		done(false, circuit.KindTransient)
		return
	}

	// Copy headers
	upstreamReq.Header = r.Header.Clone()
	upstreamReq.Header.Set("X-Request-Id", rid)

	// Send the request
	ctx, cancel := context.WithTimeout(r.Context(), 120*time.Second)
	defer cancel()
	upstreamReq = upstreamReq.WithContext(ctx)

	resp, err := http.DefaultClient.Do(upstreamReq)
	if err != nil {
		slog.Error("upstream request failed", "error", err)
		errKind := classifyError(err, nil)
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]string{
				"message": "upstream request failed: " + err.Error(),
				"type":    "upstream_error",
				"code":    string(errKind),
			},
		})
		// Empty errorKind = client-side error (e.g. context canceled)
		// Record as success to avoid opening the circuit breaker.
		done(errKind == "", errKind)
		return
	}

	if resp.StatusCode >= 400 {
		defer resp.Body.Close()
		body := make([]byte, 4096)
		n, _ := resp.Body.Read(body)
		errKind := classifyError(nil, resp)

		for k, vs := range resp.Header {
			for _, v := range vs {
				w.Header().Add(k, v)
			}
		}
		w.WriteHeader(resp.StatusCode)
		if n > 0 {
			w.Write(body[:n])
		}

		// 4xx client errors (400, 422, etc.) are the client's fault —
		// don't open the circuit breaker. Only 429/401/403/402 affect it.
		if resp.StatusCode >= 400 && resp.StatusCode < 500 &&
			resp.StatusCode != 429 && resp.StatusCode != 401 &&
			resp.StatusCode != 403 && resp.StatusCode != 402 {
			done(true, "")
		} else {
			done(false, errKind)
		}
		return
	}

	// Success — proxy the response
	if isStream {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.WriteHeader(http.StatusOK)

		// Stream the response with model name substitution
		StreamChatFromResponse(w, resp, "", "")
		done(true, "")
	} else {
		defer resp.Body.Close()
		for k, vs := range resp.Header {
			for _, v := range vs {
				w.Header().Add(k, v)
			}
		}
		w.WriteHeader(resp.StatusCode)

		body := make([]byte, 32*1024)
		for {
			n, err := resp.Body.Read(body)
			if n > 0 {
				w.Write(body[:n])
			}
			if err != nil {
				break
			}
		}
		done(true, "")
	}
}

// isStreamRequest checks if the client requested streaming.
func isStreamRequest(r *http.Request) bool {
	if r.Header.Get("Accept") == "text/event-stream" {
		return true
	}
	// Check the request body for stream: true
	return false // full check requires body parsing which we do in the stream handler
}

// classifyError maps HTTP status / Go errors to circuit.ErrorKind.
// Client errors (4xx) are mapped to a non-circuit-breaking kind.
func classifyError(err error, resp *http.Response) circuit.ErrorKind {
	if err != nil {
		// Client context cancellation is NOT an upstream fault.
		if errors.Is(err, context.Canceled) {
			return ""
		}
		msg := err.Error()
		if strings.Contains(msg, "timeout") || strings.Contains(msg, "deadline") {
			return circuit.KindTimeout
		}
		if strings.Contains(msg, "connection") || strings.Contains(msg, "refused") ||
			strings.Contains(msg, "no such host") || strings.Contains(msg, "reset") {
			return circuit.KindNetwork
		}
		return circuit.KindTransient
	}
	if resp == nil {
		return circuit.KindUpstreamDown
	}
	switch {
	case resp.StatusCode == 429:
		return circuit.KindRateLimit
	case resp.StatusCode == 401 || resp.StatusCode == 403:
		return circuit.KindAuth
	case resp.StatusCode == 402:
		return circuit.KindQuota
	case resp.StatusCode >= 500:
		return circuit.KindUpstreamDown
	default:
		return circuit.KindTransient
	}
}

// writeJSON writes a JSON response.
func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

//-----------------------------------------------------------------------------
// Health handler
//-----------------------------------------------------------------------------

// HealthResponse represents the health check response.
type HealthResponse struct {
	Status      string `json:"status"`
	Version     string `json:"version"`
	Circuit     any    `json:"circuit,omitempty"`
	Concurrency any    `json:"concurrency,omitempty"`
}

// HealthHandler returns health information including circuit breaker and limiter stats.
type HealthHandler struct {
	circuit *circuit.Manager
	limiter *limiter.Limiter
}

// NewHealthHandler creates a new health handler.
func NewHealthHandler(cm *circuit.Manager, l *limiter.Limiter) *HealthHandler {
	return &HealthHandler{circuit: cm, limiter: l}
}

func (h *HealthHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	resp := HealthResponse{
		Status:  "ok",
		Version: "0.2.0",
	}

	if r.URL.Query().Get("full") == "true" {
		resp.Circuit = h.circuit.Stats()
		resp.Concurrency = h.limiter.Stats()
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(resp)
}

// StreamChatFromResponse streams a chat response as SSE.
func StreamChatFromResponse(w http.ResponseWriter, resp *http.Response, clientModel, outboundModel string) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		return
	}

	defer resp.Body.Close()
	buf := make([]byte, 4096)
	for {
		n, err := resp.Body.Read(buf)
		if n > 0 {
			data := string(buf[:n])
			w.Write([]byte(data))
			flusher.Flush()
		}
		if err != nil {
			break
		}
	}
}
