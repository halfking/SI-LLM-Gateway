package relay

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

type ModelsHandler struct {
	pythonEndpoint string
	client         *http.Client
}

func NewModelsHandler(pythonEndpoint string) *ModelsHandler {
	endpoint := pythonEndpoint
	if endpoint != "" {
		for _, suffix := range []string{"/v1/chat/completions", "/v1/responses", "/v1/completions"} {
			if len(endpoint) > len(suffix) && endpoint[len(endpoint)-len(suffix):] == suffix {
				endpoint = endpoint[:len(endpoint)-len(suffix)]
				break
			}
		}
		if len(endpoint) > 3 && endpoint[len(endpoint)-3:] == "/v1" {
			endpoint = endpoint[:len(endpoint)-3]
		}
		endpoint = strings.TrimRight(endpoint, "/")
	}
	return &ModelsHandler{
		pythonEndpoint: endpoint,
		client: &http.Client{
			Timeout: 15 * time.Second,
		},
	}
}

func (h *ModelsHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h.pythonEndpoint == "" {
		writeJSON(w, http.StatusOK, map[string]any{
			"object": "list",
			"data":   []any{},
			"models":  []string{},
			"count":   0,
			"mode":    "gateway",
		})
		return
	}

	target := h.pythonEndpoint + "/v1/models"
	if r.URL.RawQuery != "" {
		target += "?" + r.URL.RawQuery
	}

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		slog.Error("models: build request failed", "error", err)
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]string{
				"message": "failed to build models request",
				"type":    "upstream_error",
			},
		})
		return
	}

	for key, vals := range r.Header {
		for _, val := range vals {
			switch key {
			case "Authorization", "X-Client-Profile", "X-Request-Id":
				req.Header.Add(key, val)
			}
		}
	}

	resp, err := h.client.Do(req)
	if err != nil {
		slog.Error("models: upstream request failed", "error", err)
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]string{
				"message": "upstream models request failed",
				"type":    "upstream_error",
			},
		})
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		slog.Error("models: read body failed", "error", err)
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]string{
				"message": "failed to read models response",
				"type":    "upstream_error",
			},
		})
		return
	}

	var payload json.RawMessage = body
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	w.Write(payload)
}
