package admin

import (
	"encoding/json"
	"net/http"

	"github.com/kaixuan/llm-gateway-go/reconnect"
)

// ReconnectConfigHandler handles admin operations for reconnect configuration.
type ReconnectConfigHandler struct {
	manager *reconnect.Manager
}

// NewReconnectConfigHandler creates a handler for reconnect config management.
func NewReconnectConfigHandler(mgr *reconnect.Manager) *ReconnectConfigHandler {
	return &ReconnectConfigHandler{manager: mgr}
}

// ServeHTTP handles:
//   GET  /api/reconnect/config           — get current global config
//   POST /api/reconnect/config           — update global config
//   GET  /api/reconnect/config/:tenantID — get tenant override
//   POST /api/reconnect/config/:tenantID — update tenant override
func (h *ReconnectConfigHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h.manager == nil {
		http.Error(w, "reconnect manager not configured", http.StatusServiceUnavailable)
		return
	}

	path := r.URL.Path
	switch {
	case path == "/api/reconnect/config":
		if r.Method == http.MethodGet {
			h.getGlobalConfig(w, r)
		} else if r.Method == http.MethodPost {
			h.updateGlobalConfig(w, r)
		} else {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	default:
		// Tenant-specific routes would go here
		http.NotFound(w, r)
	}
}

func (h *ReconnectConfigHandler) getGlobalConfig(w http.ResponseWriter, r *http.Request) {
	cfg := h.manager.GetConfig()
	response := map[string]interface{}{
		"enabled":                cfg.Enabled,
		"auto_resume_by_default": cfg.AutoResumeByDefault,
		"cache_ttl_seconds":      int(cfg.CacheTTL.Seconds()),
		"max_cache_body_bytes":   cfg.MaxCacheBodyBytes,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (h *ReconnectConfigHandler) updateGlobalConfig(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Enabled             *bool `json:"enabled"`
		AutoResumeByDefault *bool `json:"auto_resume_by_default"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	cfg := h.manager.GetConfig()
	enabled := cfg.Enabled
	autoResume := cfg.AutoResumeByDefault

	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	if req.AutoResumeByDefault != nil {
		autoResume = *req.AutoResumeByDefault
	}

	h.manager.UpdateGlobal(enabled, autoResume)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "reconnect config updated",
	})
}
