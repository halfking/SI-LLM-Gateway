package relay

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/kaixuan/llm-gateway-go/auth"
	"github.com/kaixuan/llm-gateway-go/sessions"
)

// sessionResolutionResult holds the outcome of resolving a session from request headers.
type sessionResolutionResult struct {
	Session   *sessions.Session
	SessionID string
	Context   context.Context
	// ResumeHeader is set when a fallback session was created or reused
	ResumeHeader string
	// AutoCreated is true when the gateway created a fresh session
	AutoCreated bool
}

// resolveSessionFromRequest extracts session headers, loads or creates a session,
// and returns an enriched context with the session attached. This replaces the
// duplicated session-resolution logic in /v1/chat/completions, /v1/messages, and
// /v1/responses.
//
// Priority order for session headers:
//   1. X-Gw-Session-Id   — gateway-native V2 id (must start with "gw_")
//   2. X-Session-Id      — legacy gateway header
//   3. X-Conversation-Id — Anthropic / OpenAI Assistants convention
//   4. X-Chat-Session-Id — vendor-specific
//   5. X-Thread-Id       — OpenAI Assistants / Threads
//
// When no session header is present and keyInfo is non-nil, a fresh V2 session
// is auto-created. When an explicit session ID is not found, a fallback V2
// session is created to replace it (so clients see X-Gw-Session-Id-Resume in
// the response).
//
// Returns nil result when sessionGetter is nil (session management disabled).
func (h *ChatHandler) resolveSessionFromRequest(
	ctx context.Context,
	r *http.Request,
	keyInfo *auth.KeyInfo,
) *sessionResolutionResult {
	if h.sessionGetter == nil {
		return nil
	}

	// Extract session ID from headers (priority order)
	sessionID := sanitizeGwSessionHeader(r.Header.Get("X-Gw-Session-Id"))
	if sessionID == "" {
		sessionID = r.Header.Get("X-Session-Id")
	}
	if sessionID == "" {
		sessionID = r.Header.Get("X-Conversation-Id")
	}
	if sessionID == "" {
		sessionID = r.Header.Get("X-Chat-Session-Id")
	}
	if sessionID == "" {
		sessionID = r.Header.Get("X-Thread-Id")
	}

	result := &sessionResolutionResult{
		SessionID: sessionID,
		Context:   ctx,
	}

	// Path 1: Explicit session ID provided
	if sessionID != "" {
		si, err := h.sessionGetter.Get(ctx, sessionID)
		if err != nil {
			if err == sessions.ErrSessionNotFound && keyInfo != nil {
				// Fallback: create replacement session
				newSession := h.createFallbackSession(ctx, keyInfo, r, sessionID)
				if newSession != nil {
					result.Session = newSession
					result.SessionID = newSession.SessionID
					result.Context = sessions.SessionFromContextWith(ctx, newSession)
					result.ResumeHeader = newSession.SessionID
					result.AutoCreated = true
				}
			} else if err == sessions.ErrSessionExpired && keyInfo != nil {
				// 2026-06-29: expired session handling - create replacement
				slog.Warn("session expired, creating replacement",
					"original_session_id", sessionID,
					"api_key_id", keyInfo.ID)
				newSession := h.createFallbackSession(ctx, keyInfo, r, sessionID)
				if newSession != nil {
					result.Session = newSession
					result.SessionID = newSession.SessionID
					result.Context = sessions.SessionFromContextWith(ctx, newSession)
					result.ResumeHeader = newSession.SessionID
					result.AutoCreated = true
				}
			} else if err != sessions.ErrSessionNotFound {
				slog.Warn("session lookup failed", "error", err, "session_id", sessionID)
			}
			return result
		}

		// Session found - verify ownership and bind if orphan
		if keyInfo != nil && si.APIKeyID != keyInfo.ID {
			if si.APIKeyID == 0 {
				// Orphan session: bind to current API key
				if bindErr := h.sessionGetter.BindAPIKey(ctx, sessionID, keyInfo.ID, keyInfo.TenantID); bindErr != nil {
					slog.Warn("orphan session bind failed", "error", bindErr, "session_id", sessionID)
					return result
				}
				si.APIKeyID = keyInfo.ID
				si.TenantID = keyInfo.TenantID
			} else {
				// Session owned by different API key - forbidden
				slog.Warn("session ownership mismatch",
					"session_id", sessionID,
					"session_api_key_id", si.APIKeyID,
					"request_api_key_id", keyInfo.ID)
				return result
			}
		}

		// Success: session loaded and ownership verified
		result.Session = si
		result.Context = sessions.SessionFromContextWith(ctx, si)

		// Touch session asynchronously
		go func() {
			touchCtx, touchCancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer touchCancel()
			//nolint:errcheck // best-effort touch, non-critical
			h.sessionGetter.Touch(touchCtx, sessionID)
		}()

		return result
	}

	// Path 2: No session ID provided - auto-create if authenticated
	if keyInfo != nil {
		deviceSeed := r.Header.Get("X-Device-Seed")
		if deviceSeed == "" {
			deviceSeed = r.Header.Get("X-Machine-Id")
		}
		if deviceSeed == "" {
			deviceSeed = "default"
		}
		taskID := r.Header.Get("X-Gw-Task-Id")

		newSession, createErr := h.sessionGetter.CreateV2(ctx, keyInfo.ID, keyInfo.TenantID, deviceSeed, taskID)
		if createErr != nil {
			slog.Error("session auto-create failed (no id path)", "error", createErr)
			return result
		}

		result.Session = newSession
		result.SessionID = newSession.SessionID
		result.Context = sessions.SessionFromContextWith(ctx, newSession)
		result.ResumeHeader = newSession.SessionID
		result.AutoCreated = true

		slog.Info("session auto-assigned (no id)",
			"client_id", keyInfo.ID,
			"new_session_id", newSession.SessionID,
			"task_id", taskID)

		// Record in last-system-session index for 5-minute reuse
		if h.lastSystemSessionIndex != nil {
			_ = h.lastSystemSessionIndex.Set(ctx, keyInfo.ID, &sessions.LastSystemSessionEntry{
				SessionID:  newSession.SessionID,
				DeviceSeed: deviceSeed,
				TaskID:     taskID,
			})
		}
	}

	return result
}

// createFallbackSession creates a V2 session to replace a not-found or expired session.
func (h *ChatHandler) createFallbackSession(
	ctx context.Context,
	keyInfo *auth.KeyInfo,
	r *http.Request,
	originalSessionID string,
) *sessions.Session {
	deviceSeed := r.Header.Get("X-Device-Seed")
	if deviceSeed == "" {
		deviceSeed = r.Header.Get("X-Machine-Id")
	}
	if deviceSeed == "" {
		deviceSeed = "default"
	}
	taskID := r.Header.Get("X-Gw-Task-Id")

	newSession, createErr := h.sessionGetter.CreateV2(ctx, keyInfo.ID, keyInfo.TenantID, deviceSeed, taskID)
	if createErr != nil {
		slog.Error("session fallback create failed", "error", createErr, "session_id", originalSessionID)
		return nil
	}

	slog.Info("session fallback created",
		"original_session_id", originalSessionID,
		"new_session_id", newSession.SessionID,
		"task_id", taskID)

	// Record in last-system-session index for 5-minute reuse
	if h.lastSystemSessionIndex != nil {
		_ = h.lastSystemSessionIndex.Set(ctx, keyInfo.ID, &sessions.LastSystemSessionEntry{
			SessionID:  newSession.SessionID,
			DeviceSeed: deviceSeed,
			TaskID:     taskID,
		})
	}

	if r.Header.Get("X-Session-Id") != "" {
		slog.Warn("legacy X-Session-Id used, fallback created; migrate to X-Gw-Session-Id",
			"original_session_id", r.Header.Get("X-Session-Id"),
			"new_session_id", newSession.SessionID)
	}

	return newSession
}

// parseSessionIDFromHeaders extracts session ID from request headers without
// loading the session. Used for audit/logging when session object is not needed.
//
// Priority matches resolveSessionFromRequest.
func parseSessionIDFromHeaders(r *http.Request) string {
	sessionID := strings.TrimSpace(r.Header.Get("X-Gw-Session-Id"))
	if sessionID != "" {
		return sessionID
	}
	sessionID = strings.TrimSpace(r.Header.Get("X-Session-Id"))
	if sessionID != "" {
		return sessionID
	}
	sessionID = strings.TrimSpace(r.Header.Get("X-Conversation-Id"))
	if sessionID != "" {
		return sessionID
	}
	sessionID = strings.TrimSpace(r.Header.Get("X-Chat-Session-Id"))
	if sessionID != "" {
		return sessionID
	}
	sessionID = strings.TrimSpace(r.Header.Get("X-Thread-Id"))
	return sessionID
}
