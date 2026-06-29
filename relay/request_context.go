package relay

import (
	"net/http"
	"strings"

	"github.com/kaixuan/llm-gateway-go/sessions"
)

// gwSessionTaskFromRequest resolves gateway session and task identifiers for
// request_logs correlation. Priority:
//   - session: X-Gw-Session-Id > X-Session-Id > X-Conversation-Id > X-Chat-Session-Id > X-Thread-Id > loaded session.SessionID
//   - task:    X-Gw-Task-Id > loaded session.TaskID
//
// 2026-06-29: extended to recognize the full header set used by resolveSessionFromRequest
// so that /v1/messages and /v1/responses requests using alternate headers (X-Conversation-Id,
// X-Thread-Id) are properly correlated in request_logs.gw_session_id.
func gwSessionTaskFromRequest(r *http.Request, session *sessions.Session) (sessionID, taskID string) {
	if r != nil {
		sessionID = strings.TrimSpace(r.Header.Get("X-Gw-Session-Id"))
		if sessionID == "" {
			sessionID = strings.TrimSpace(r.Header.Get("X-Session-Id"))
		}
		if sessionID == "" {
			sessionID = strings.TrimSpace(r.Header.Get("X-Conversation-Id"))
		}
		if sessionID == "" {
			sessionID = strings.TrimSpace(r.Header.Get("X-Chat-Session-Id"))
		}
		if sessionID == "" {
			sessionID = strings.TrimSpace(r.Header.Get("X-Thread-Id"))
		}
		taskID = strings.TrimSpace(r.Header.Get("X-Gw-Task-Id"))
	}
	if session != nil {
		if sessionID == "" {
			sessionID = strings.TrimSpace(session.SessionID)
		}
		if taskID == "" {
			taskID = strings.TrimSpace(session.TaskID)
		}
	}
	return sessionID, taskID
}
