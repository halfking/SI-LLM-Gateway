package relay

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/kaixuan/llm-gateway-go/circuit"
	"github.com/kaixuan/llm-gateway-go/identity"
	"github.com/kaixuan/llm-gateway-go/limiter"
	"github.com/kaixuan/llm-gateway-go/pool"
	"github.com/kaixuan/llm-gateway-go/resolve"
	"github.com/kaixuan/llm-gateway-go/transform"
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

type chatRequestBody struct {
	Model    string          `json:"model"`
	Stream   bool            `json:"stream"`
	Messages json.RawMessage `json:"messages,omitempty"`
}

type chatResponseBody struct {
	Model string `json:"model"`
}

//-----------------------------------------------------------------------------
// Chat handler — integrates circuit breaker + concurrency limiter
//-----------------------------------------------------------------------------

// ChatHandler handles chat completions with circuit breaker and concurrency control.
type ChatHandler struct {
	circuit  *circuit.Manager
	limiter  *limiter.Limiter
	matrix   *transform.Matrix
	pools    *pool.PoolManager
	resolver *resolve.Resolver
}

func NewChatHandler(cm *circuit.Manager, l *limiter.Limiter, matrix *transform.Matrix, pools *pool.PoolManager, resolver *resolve.Resolver) *ChatHandler {
	return &ChatHandler{circuit: cm, limiter: l, matrix: matrix, pools: pools, resolver: resolver}
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

	// ── Read and buffer body ───────────────────────────────────────────
	bodyBytes, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]string{
				"message": "failed to read request body",
				"type":    "invalid_request",
				"code":    "body_read_error",
			},
		})
		return
	}
	r.Body.Close()

	// ── Parse request body for model + stream ──────────────────────────
	var reqBody chatRequestBody
	if err := json.Unmarshal(bodyBytes, &reqBody); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]string{
				"message": "invalid JSON in request body",
				"type":    "invalid_request",
				"code":    "json_parse_error",
			},
		})
		return
	}

	clientModel := reqBody.Model
	isStream := reqBody.Stream

	// ── Build identity from request ────────────────────────────────────
	clientID := identity.BuildIdentityFromRequest(r, "default", nil, nil, "")
	identityHash := clientID.ShortID()

	// ── Resolve model name via control plane ──────────────────────────
	var modelResolution *resolve.Resolution
	if h.resolver != nil {
		modelResolution = h.resolver.Resolve(r.Context(), clientModel, clientID.Fingerprint.ClientProfile)
		slog.Debug("model resolved",
			"client_model", clientModel,
			"resolution_path", modelResolution.ResolutionPath,
			"raw_models", modelResolution.RawModels,
			"canonical", modelResolution.CanonicalName,
		)
	}

	// ── Resolve transform rules ────────────────────────────────────────
	tCtx := &transform.TransformContext{
		RequestMode:   "chat",
		ClientProfile: clientID.Fingerprint.ClientProfile,
		ClientModel:   clientModel,
	}
	if modelResolution != nil && modelResolution.CanonicalName != nil {
		tCtx.CanonicalName = *modelResolution.CanonicalName
	}
	var txResult *transform.TransformResult
	if h.matrix != nil {
		txResult = h.matrix.Resolve(tCtx)
	}
	explicitOutbound := ""
	if txResult != nil && txResult.OutboundModel != "" {
		explicitOutbound = transform.RenderOutboundModel(
			txResult.OutboundModel, txResult.OutboundModel, clientModel, "",
		)
	}

	// ── Replace model in request body if transformed ───────────────────
	if explicitOutbound != "" && explicitOutbound != clientModel {
		bodyBytes = replaceModelInRequestBody(bodyBytes, explicitOutbound)
	}

	// ── Concurrency limiter ────────────────────────────────────────────
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

	// ── Build upstream request ─────────────────────────────────────────
	ChatCompletionsPhase3(w, r, bodyBytes, isStream, clientModel, explicitOutbound, clientID, txResult, svc, h.circuit, h.limiter, h.pools, release)
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
// ChatCompletionsPhase3 — full pipeline with transform, pool, streaming
//-----------------------------------------------------------------------------

func ChatCompletionsPhase3(
	w http.ResponseWriter,
	r *http.Request,
	bodyBytes []byte,
	isStream bool,
	clientModel string,
	explicitOutbound string,
	clientID identity.ClientIdentity,
	txResult *transform.TransformResult,
	svc ServiceID,
	cm *circuit.Manager,
	lim *limiter.Limiter,
	pools *pool.PoolManager,
	release limiter.ReleaseFunc,
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
			release()
			cm.RecordFailure(svc.ProviderID, svc.CredentialID, circuit.KindTransient)
		}
	}()

	rid := r.Header.Get("X-Request-Id")
	slog.Info("chat completions",
		"request_id", rid,
		"client_model", clientModel,
		"outbound_model", explicitOutbound,
		"stream", isStream,
		"identity", clientID.ShortID(),
		"upstream", upstream.String(),
	)

	// ── Build upstream request ─────────────────────────────────────────
	upstreamReq, err := http.NewRequestWithContext(r.Context(), r.Method, upstream.String()+r.URL.Path, bytes.NewReader(bodyBytes))
	if err != nil {
		slog.Error("failed to create upstream request", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{
			"error": map[string]string{
				"message": "failed to create upstream request",
				"type":    "server_error",
				"code":    "upstream_error",
			},
		})
		release()
		cm.RecordFailure(svc.ProviderID, svc.CredentialID, circuit.KindTransient)
		return
	}

	// Copy headers
	upstreamReq.Header = r.Header.Clone()
	upstreamReq.Header.Set("X-Request-Id", rid)
	upstreamReq.Header.Set("Content-Type", "application/json")

	// ── Inject identity headers ────────────────────────────────────────
	upstreamReq.Header.Set("X-Virtual-Client-Id", clientID.VirtualClientID)
	upstreamReq.Header.Set("X-Virtual-IP", clientID.VirtualIP)
	upstreamReq.Header.Set("X-Virtual-MAC", clientID.VirtualMAC)

	// ── Apply transform header rules ───────────────────────────────────
	if txResult != nil {
		for _, h := range txResult.StripHeaders {
			upstreamReq.Header.Del(h)
		}
		for k, v := range txResult.InjectHeaders {
			upstreamReq.Header.Set(k, v)
		}
	}

	// ── Get HTTP client (identity-bound pool or default) ───────────────
	var httpClient *http.Client
	if pools != nil {
		poolKey := pool.PoolKey{
			IdentityHash: clientID.IdentityHash,
			ProviderID:   svc.ProviderID,
			CredentialID: svc.CredentialID,
		}
		p := pools.Get(poolKey)
		if p != nil && p.State() == pool.PoolActive {
			httpClient = p.Client()
		}
	}
	if httpClient == nil {
		httpClient = http.DefaultClient
	}

	// ── Send the request ───────────────────────────────────────────────
	ctx, cancel := context.WithTimeout(r.Context(), 120*time.Second)
	defer cancel()
	upstreamReq = upstreamReq.WithContext(ctx)

	resp, err := httpClient.Do(upstreamReq)
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
		release()
		if errKind == "" {
			cm.RecordSuccess(svc.ProviderID, svc.CredentialID)
		} else {
			cm.RecordFailure(svc.ProviderID, svc.CredentialID, errKind)
			if errKind == circuit.KindRateLimit {
				lim.Shrink(svc.ProviderID, svc.CredentialID)
			}
		}
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

		release()
		if resp.StatusCode >= 400 && resp.StatusCode < 500 &&
			resp.StatusCode != 429 && resp.StatusCode != 401 &&
			resp.StatusCode != 403 && resp.StatusCode != 402 {
			cm.RecordSuccess(svc.ProviderID, svc.CredentialID)
		} else {
			cm.RecordFailure(svc.ProviderID, svc.CredentialID, errKind)
			if errKind == circuit.KindRateLimit {
				lim.Shrink(svc.ProviderID, svc.CredentialID)
			}
		}
		return
	}

	// ── Success — proxy the response ───────────────────────────────────
	if isStream {
		StreamChat(w, resp, clientModel, explicitOutbound)
		release()
		cm.RecordSuccess(svc.ProviderID, svc.CredentialID)
	} else {
		defer resp.Body.Close()
		respBody, err := io.ReadAll(resp.Body)
		if err != nil {
			slog.Error("failed to read upstream response", "error", err)
			writeJSON(w, http.StatusBadGateway, map[string]any{
				"error": map[string]string{
					"message": "failed to read upstream response",
					"type":    "upstream_error",
					"code":    "read_error",
				},
			})
			release()
			cm.RecordFailure(svc.ProviderID, svc.CredentialID, circuit.KindTransient)
			return
		}

		// Replace model in non-streaming response
		if clientModel != "" {
			respBody = replaceModelInResponseBody(respBody, clientModel)
		}

		for k, vs := range resp.Header {
			for _, v := range vs {
				w.Header().Add(k, v)
			}
		}
		w.WriteHeader(resp.StatusCode)
		w.Write(respBody)
		release()
		cm.RecordSuccess(svc.ProviderID, svc.CredentialID)
	}
}

// replaceModelInRequestBody replaces the "model" field in a JSON body.
func replaceModelInRequestBody(body []byte, newModel string) []byte {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(body, &obj); err != nil {
		return body
	}
	if _, ok := obj["model"]; ok {
		obj["model"], _ = json.Marshal(newModel)
		newBody, err := json.Marshal(obj)
		if err != nil {
			return body
		}
		return newBody
	}
	return body
}

// replaceModelInResponseBody replaces whatever model is in the response with clientModel.
func replaceModelInResponseBody(body []byte, clientModel string) []byte {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(body, &obj); err != nil {
		return body
	}
	if _, ok := obj["model"]; ok {
		obj["model"], _ = json.Marshal(clientModel)
		newBody, err := json.Marshal(obj)
		if err == nil {
			return newBody
		}
	}
	return body
}

// ChatCompletionsWithHooks proxies a chat completion request and calls the
// done callback with success/failure after the request completes.
// Deprecated: Use ChatCompletionsPhase3 instead.
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

	isStream := isStreamRequest(r)

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

	upstreamReq.Header = r.Header.Clone()
	upstreamReq.Header.Set("X-Request-Id", rid)

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

		if resp.StatusCode >= 400 && resp.StatusCode < 500 &&
			resp.StatusCode != 429 && resp.StatusCode != 401 &&
			resp.StatusCode != 403 && resp.StatusCode != 402 {
			done(true, "")
		} else {
			done(false, errKind)
		}
		return
	}

	if isStream {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		w.WriteHeader(http.StatusOK)

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

// isStreamRequest checks if the client requested streaming via Accept header.
func isStreamRequest(r *http.Request) bool {
	return r.Header.Get("Accept") == "text/event-stream"
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

// StreamChatFromResponse streams a chat response as SSE without model replacement.
// Deprecated: Use StreamChat from stream.go for proper SSE parsing and model replacement.
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
