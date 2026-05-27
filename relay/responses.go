package relay

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/kaixuan/llm-gateway-go/audit"
	"github.com/kaixuan/llm-gateway-go/auth"
	"github.com/kaixuan/llm-gateway-go/identity"
	"github.com/kaixuan/llm-gateway-go/resolve"
	"github.com/kaixuan/llm-gateway-go/routing"
	"github.com/kaixuan/llm-gateway-go/transform"
)

type responsesRequestBody struct {
	Model          string          `json:"model"`
	Input          json.RawMessage `json:"input"`
	Instructions   string          `json:"instructions,omitempty"`
	MaxOutputTokens *int           `json:"max_output_tokens,omitempty"`
	Stream         bool            `json:"stream"`
	Temperature    *float64        `json:"temperature,omitempty"`
	TopP           *float64        `json:"top_p,omitempty"`
}

type ResponsesHandler struct {
	chatHandler *ChatHandler
}

func NewResponsesHandler(ch *ChatHandler) *ResponsesHandler {
	return &ResponsesHandler{chatHandler: ch}
}

func (h *ResponsesHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeResponsesError(w, http.StatusMethodNotAllowed, "Method not allowed", "invalid_request", "method_not_allowed")
		return
	}

	requestID := r.Header.Get("X-Request-Id")

	var keyInfo *auth.KeyInfo
	if h.chatHandler.keyVerifier != nil && h.chatHandler.keyVerifier.Enabled() {
		rawKey := extractBearerToken(r)
		if rawKey == "" {
			writeResponsesError(w, http.StatusUnauthorized, "Missing API key", "authentication_error", "missing_key")
			return
		}
		ki, verifyErr := h.chatHandler.keyVerifier.Verify(r.Context(), rawKey)
		if verifyErr != nil {
			if _, ok := verifyErr.(*auth.InvalidKeyError); ok {
				writeResponsesError(w, http.StatusUnauthorized, "Invalid or expired API key", "authentication_error", "invalid_key")
				return
			}
			slog.Warn("responses: key verification RPC failed", "error", verifyErr)
		} else {
			keyInfo = ki
		}
	}

	if keyInfo != nil && h.chatHandler.rateLimiter != nil && keyInfo.RateLimitRPM != nil && *keyInfo.RateLimitRPM > 0 {
		if !h.chatHandler.rateLimiter.CheckRPM(keyInfo.ID, *keyInfo.RateLimitRPM) {
			writeResponsesError(w, http.StatusTooManyRequests, "Rate limit exceeded", "rate_limit_exceeded", "rate_limit_exceeded")
			return
		}
	}

	bodyBytes, err := io.ReadAll(io.LimitReader(r.Body, int64(maxBodySize)+1))
	if err != nil {
		writeResponsesError(w, http.StatusBadRequest, "Failed to read request body", "invalid_request", "body_read_error")
		return
	}
	if len(bodyBytes) > maxBodySize {
		writeResponsesError(w, http.StatusRequestEntityTooLarge, "Request body too large", "invalid_request", "body_too_large")
		return
	}
	r.Body.Close()

	var reqBody responsesRequestBody
	if err := json.Unmarshal(bodyBytes, &reqBody); err != nil {
		writeResponsesError(w, http.StatusBadRequest, "Invalid JSON in request body", "invalid_request", "json_parse_error")
		return
	}
	if reqBody.Model == "" {
		writeResponsesError(w, http.StatusBadRequest, "model is required", "invalid_request", "missing_model")
		return
	}

	chatBody := convertResponsesToChatBody(&reqBody)
	chatBodyBytes, err := json.Marshal(chatBody)
	if err != nil {
		writeResponsesError(w, http.StatusInternalServerError, "Internal conversion error", "server_error", "conversion_error")
		return
	}

	clientModel := reqBody.Model
	isStream := reqBody.Stream
	endUser := extractEndUser(r)
	clientID := identity.BuildIdentityFromRequest(r, tenant(keyInfo), appID(keyInfo), apiKeyIDPtr(keyInfo), "")

	auditBuilder := audit.NewEvent().
		ClientModel(clientModel).
		IdentityHash(clientID.ShortID()).
		ClientProfile(clientID.Fingerprint.ClientProfile).
		Stream(isStream).
		RequestChecksum(bodyBytes)

	var streamCapture *audit.StreamCapture
	if isStream {
		streamCapture = audit.NewStreamCapture()
	}
	defer func() {
		if streamCapture != nil {
			auditBuilder.StreamMetrics(streamCapture)
		}
		h.chatHandler.auditor.Emit(r.Context(), auditBuilder.Build())
	}()

	candidates, policy, candErr := h.chatHandler.provider.GetCandidates(r.Context(), clientModel, clientID.Fingerprint.ClientProfile)
	if candErr != nil || len(candidates) == 0 {
		writeResponsesError(w, http.StatusServiceUnavailable, fmt.Sprintf("No available provider for model '%s'", clientModel), "server_error", "no_candidate")
		return
	}

	var modelResolution *resolve.Resolution
	if h.chatHandler.resolver != nil {
		modelResolution = h.chatHandler.resolver.Resolve(r.Context(), clientModel, clientID.Fingerprint.ClientProfile)
	}

	var txResult *transform.TransformResult
	tCtx := &transform.TransformContext{
		RequestMode:   "chat",
		ClientProfile: clientID.Fingerprint.ClientProfile,
		ClientModel:   clientModel,
	}
	if modelResolution != nil && modelResolution.CanonicalName != nil {
		tCtx.CanonicalName = *modelResolution.CanonicalName
	}
	if h.chatHandler.matrix != nil {
		txResult = h.chatHandler.matrix.Resolve(tCtx)
	}
	explicitOutbound := ""
	if txResult != nil && txResult.OutboundModel != "" {
		explicitOutbound = transform.RenderOutboundModel(txResult.OutboundModel, txResult.OutboundModel, clientModel, tCtx.CanonicalName)
	}

	result, execErr := h.chatHandler.executor.Execute(&routing.ExecParams{
		W:             w,
		R:             r,
		BodyBytes:     chatBodyBytes,
		IsStream:      isStream,
		ClientModel:   clientModel,
		OutboundModel: explicitOutbound,
		ClientID:      clientID,
		Transform:     txResult,
		Resolution:    modelResolution,
		Candidates:    candidates,
		Policy:        policy,
		AuditBuilder:  auditBuilder,
		Capture:       streamCapture,
		StreamWrapper: responsesStreamWrapper(requestID, clientModel, explicitOutbound, streamCapture),
	})

	if execErr != nil {
		if execErr, ok := execErr.(*routing.ExecuteError); ok && execErr.Exhausted {
			writeResponsesError(w, http.StatusServiceUnavailable, "All providers unavailable", "server_error", "provider_unavailable")
			return
		}
		writeResponsesError(w, http.StatusServiceUnavailable, "Upstream request failed", "server_error", "upstream_error")
		return
	}

	_ = result
	auditBuilder.Success(true).Latency(time.Duration(result.LatencyMs) * time.Millisecond)

	if h.chatHandler.sticky != nil && policy != nil {
		stickyKey := routing.BuildStickyKey(tenant(keyInfo), appID(keyInfo), apiKeyIDPtr(keyInfo), endUser, clientID.Fingerprint.PrimarySeed())
		stickyTTL := time.Duration(policy.StickyTTLMilliseconds) * time.Second
		if stickyTTL < time.Minute {
			stickyTTL = time.Minute
		}
		h.chatHandler.sticky.Set(stickyKey, result.Candidate.CredentialID, stickyTTL)
	}

	if !isStream {
		h.writeNonStreamResponse(w, result.Response, clientModel, requestID)
	}

	h.chatHandler.emitTelemetry(auditBuilder.Build(), result, endUser, keyInfo, streamCapture)
}

func convertResponsesToChatBody(req *responsesRequestBody) map[string]any {
	chatBody := map[string]any{
		"model":  req.Model,
		"stream": req.Stream,
	}

	var messages []any
	if req.Instructions != "" {
		messages = append(messages, map[string]any{"role": "system", "content": req.Instructions})
	}

	var rawInput json.RawMessage = req.Input
	if len(rawInput) > 0 {
		if rawInput[0] == '"' {
			var s string
			if json.Unmarshal(rawInput, &s) == nil {
				messages = append(messages, map[string]any{"role": "user", "content": s})
			}
		} else if rawInput[0] == '[' {
			var items []map[string]any
			if json.Unmarshal(rawInput, &items) == nil {
				for _, item := range items {
					role, _ := item["role"].(string)
					if role == "" {
						role = "user"
					}
					content := item["content"]
					if content == nil {
						content = ""
					}
					messages = append(messages, map[string]any{"role": role, "content": content})
				}
			}
		}
	}
	chatBody["messages"] = messages

	if req.MaxOutputTokens != nil {
		chatBody["max_tokens"] = *req.MaxOutputTokens
	}
	if req.Temperature != nil {
		chatBody["temperature"] = *req.Temperature
	}
	if req.TopP != nil {
		chatBody["top_p"] = *req.TopP
	}

	return chatBody
}

func (h *ResponsesHandler) writeNonStreamResponse(w http.ResponseWriter, resp *http.Response, clientModel, requestID string) {
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, int64(maxBodySize)+1))
	if err != nil {
		writeResponsesError(w, http.StatusInternalServerError, "Failed to read upstream response", "server_error", "upstream_read_error")
		return
	}
	if len(body) > maxBodySize {
		body = body[:maxBodySize]
	}

	respBody := convertChatResponseToResponses(body, clientModel, requestID)

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Request-Id", requestID)
	w.WriteHeader(http.StatusOK)
	w.Write(respBody)
}

func convertChatResponseToResponses(body []byte, clientModel, requestID string) []byte {
	var chatResp map[string]json.RawMessage
	if err := json.Unmarshal(body, &chatResp); err != nil {
		return body
	}

	var choices []map[string]any
	if raw, ok := chatResp["choices"]; ok {
		json.Unmarshal(raw, &choices)
	}

	finishReason := "stop"
	textContent := ""

	if len(choices) > 0 {
		choice := choices[0]
		if fr, ok := choice["finish_reason"].(string); ok {
			finishReason = fr
		}
		if msg, ok := choice["message"].(map[string]any); ok {
			if c, ok := msg["content"].(string); ok {
				textContent = c
			}
		}
	}

	status := "completed"
	if finishReason == "length" {
		status = "incomplete"
	}

	inputTokens := 0
	outputTokens := 0
	totalTokens := 0
	if raw, ok := chatResp["usage"]; ok {
		var usage map[string]any
		if json.Unmarshal(raw, &usage) == nil {
			if v, ok := usage["prompt_tokens"].(float64); ok {
				inputTokens = int(v)
			}
			if v, ok := usage["completion_tokens"].(float64); ok {
				outputTokens = int(v)
			}
			if v, ok := usage["total_tokens"].(float64); ok {
				totalTokens = int(v)
			}
		}
	}

	created := int(time.Now().Unix())
	if raw, ok := chatResp["created"]; ok {
		var v float64
		if json.Unmarshal(raw, &v) == nil {
			created = int(v)
		}
	}

	respID := "resp_"
	msgID := "msg_"
	if len(requestID) > 24 {
		respID += requestID[:24]
		msgID += requestID[8:24]
	} else {
		respID += requestID
		msgID += requestID
	}

	resp := map[string]any{
		"id":         respID,
		"object":     "response",
		"created_at": created,
		"model":      clientModel,
		"status":     status,
		"output": []map[string]any{
			{
				"type":   "message",
				"id":     msgID,
				"status": status,
				"role":   "assistant",
				"content": []map[string]any{
					{
						"type":        "output_text",
						"text":        textContent,
						"annotations": []any{},
					},
				},
			},
		},
		"usage": map[string]any{
			"input_tokens":  inputTokens,
			"output_tokens": outputTokens,
			"total_tokens":  totalTokens,
		},
		"x_request_id": requestID,
	}

	result, err := json.Marshal(resp)
	if err != nil {
		return body
	}
	return result
}

func writeResponsesError(w http.ResponseWriter, statusCode int, message, errType, code string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]any{
			"message": message,
			"type":    errType,
			"param":   "model",
			"code":    code,
		},
	})
}

func responsesStreamWrapper(requestID, clientModel, outboundModel string, capture *audit.StreamCapture) routing.StreamWrapperFunc {
	return func(w http.ResponseWriter, resp *http.Response, norm routing.NormalizerFunc, cap *audit.StreamCapture) {
		c := cap
		if c == nil {
			c = capture
		}
		StreamResponsesSSE(w, resp, clientModel, outboundModel, requestID, c)
	}
}
