package relay

import (
	"context"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/kaixuan/llm-gateway-go/auth"
	"github.com/kaixuan/llm-gateway-go/circuit"
	"github.com/kaixuan/llm-gateway-go/limiter"
	"github.com/kaixuan/llm-gateway-go/sessions"
)

// mockSessionGetter implements the sessionGetter interface for testing.
type mockSessionGetter struct {
	sessions map[string]*sessions.Session
	created  []*sessions.Session
}

func (m *mockSessionGetter) Get(ctx context.Context, id string) (*sessions.Session, error) {
	if s, ok := m.sessions[id]; ok {
		return s, nil
	}
	return nil, sessions.ErrSessionNotFound
}

func (m *mockSessionGetter) Touch(ctx context.Context, id string) error {
	return nil
}

func (m *mockSessionGetter) CreateV2(ctx context.Context, apiKeyID int, tenantID, deviceSeed, taskID string) (*sessions.Session, error) {
	s := &sessions.Session{
		SessionID: "gw_test_" + time.Now().Format("20060102150405"),
		APIKeyID:  apiKeyID,
		TenantID:  tenantID,
		TaskID:    taskID,
		Namespace: "gw",
		CreatedAt: time.Now(),
	}
	if m.sessions == nil {
		m.sessions = make(map[string]*sessions.Session)
	}
	m.sessions[s.SessionID] = s
	m.created = append(m.created, s)
	return s, nil
}

func (m *mockSessionGetter) BindAPIKey(ctx context.Context, sessionID string, apiKeyID int, tenantID string) error {
	if s, ok := m.sessions[sessionID]; ok {
		s.APIKeyID = apiKeyID
		s.TenantID = tenantID
	}
	return nil
}

func TestResolveSessionFromRequest_ExplicitSessionFound(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	mock := &mockSessionGetter{
		sessions: map[string]*sessions.Session{
			"gw_existing": {
				SessionID: "gw_existing",
				APIKeyID:  5,
				TenantID:  "test-tenant",
			},
		},
	}
	ch.sessionGetter = mock

	r := httptest.NewRequest("POST", "/v1/chat/completions", nil)
	r.Header.Set("X-Gw-Session-Id", "gw_existing")

	keyInfo := &auth.KeyInfo{ID: 5, TenantID: "test-tenant"}
	result := ch.resolveSessionFromRequest(context.Background(), r, keyInfo)

	if result == nil {
		t.Fatal("expected non-nil result")
	}
	if result.Session == nil {
		t.Fatal("expected session to be loaded")
	}
	if result.SessionID != "gw_existing" {
		t.Errorf("expected session_id=gw_existing, got %s", result.SessionID)
	}
	if result.AutoCreated {
		t.Error("existing session should not be marked as auto-created")
	}
}

func TestResolveSessionFromRequest_SessionNotFound_CreatesFallback(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	mock := &mockSessionGetter{sessions: make(map[string]*sessions.Session)}
	ch.sessionGetter = mock

	r := httptest.NewRequest("POST", "/v1/chat/completions", nil)
	r.Header.Set("X-Session-Id", "legacy_missing")

	keyInfo := &auth.KeyInfo{ID: 10, TenantID: "default"}
	result := ch.resolveSessionFromRequest(context.Background(), r, keyInfo)

	if result == nil || result.Session == nil {
		t.Fatal("expected fallback session to be created")
	}
	if !result.AutoCreated {
		t.Error("fallback session should be marked as auto-created")
	}
	if result.ResumeHeader == "" {
		t.Error("expected ResumeHeader to be set")
	}
	if len(mock.created) != 1 {
		t.Fatalf("expected 1 session created, got %d", len(mock.created))
	}
}

func TestResolveSessionFromRequest_SessionExpired_CreatesFallback(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	
	// Use a custom mock that returns ErrSessionExpired for specific session
	expiredMock := &expiredSessionGetter{
		mockSessionGetter: mockSessionGetter{
			sessions: map[string]*sessions.Session{
				"gw_expired": {
					SessionID: "gw_expired",
					APIKeyID:  7,
					TenantID:  "default",
					ExpiresAt: time.Now().Add(-1 * time.Hour), // expired
				},
			},
		},
	}
	ch.sessionGetter = expiredMock

	r := httptest.NewRequest("POST", "/v1/messages", nil)
	r.Header.Set("X-Gw-Session-Id", "gw_expired")

	keyInfo := &auth.KeyInfo{ID: 7, TenantID: "default"}
	result := ch.resolveSessionFromRequest(context.Background(), r, keyInfo)

	if result == nil || result.Session == nil {
		t.Fatal("expected replacement session to be created for expired session")
	}
	if !result.AutoCreated {
		t.Error("replacement session should be marked as auto-created")
	}
	if result.SessionID == "gw_expired" {
		t.Error("expected new session ID, not the expired one")
	}
}

// expiredSessionGetter returns ErrSessionExpired for sessions past their ExpiresAt
type expiredSessionGetter struct {
	mockSessionGetter
}

func (m *expiredSessionGetter) Get(ctx context.Context, id string) (*sessions.Session, error) {
	if s, ok := m.sessions[id]; ok {
		if time.Now().After(s.ExpiresAt) {
			return nil, sessions.ErrSessionExpired
		}
		return s, nil
	}
	return nil, sessions.ErrSessionNotFound
}

func TestResolveSessionFromRequest_NoHeader_AutoCreates(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	mock := &mockSessionGetter{sessions: make(map[string]*sessions.Session)}
	ch.sessionGetter = mock

	r := httptest.NewRequest("POST", "/v1/responses", nil)
	// No session headers

	keyInfo := &auth.KeyInfo{ID: 15, TenantID: "default"}
	result := ch.resolveSessionFromRequest(context.Background(), r, keyInfo)

	if result == nil || result.Session == nil {
		t.Fatal("expected auto-created session")
	}
	if !result.AutoCreated {
		t.Error("session should be marked as auto-created")
	}
	if result.ResumeHeader == "" {
		t.Error("expected ResumeHeader to be set for auto-created session")
	}
}

func TestResolveSessionFromRequest_AlternateHeaders(t *testing.T) {
	testCases := []struct {
		name       string
		headerKey  string
		headerVal  string
		wantLoaded bool
	}{
		{"X-Conversation-Id", "X-Conversation-Id", "gw_conv", true},
		{"X-Chat-Session-Id", "X-Chat-Session-Id", "gw_chat", true},
		{"X-Thread-Id", "X-Thread-Id", "gw_thread", true},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
			mock := &mockSessionGetter{
				sessions: map[string]*sessions.Session{
					tc.headerVal: {
						SessionID: tc.headerVal,
						APIKeyID:  20,
						TenantID:  "default",
					},
				},
			}
			ch.sessionGetter = mock

			r := httptest.NewRequest("POST", "/v1/messages", nil)
			r.Header.Set(tc.headerKey, tc.headerVal)

			keyInfo := &auth.KeyInfo{ID: 20, TenantID: "default"}
			result := ch.resolveSessionFromRequest(context.Background(), r, keyInfo)

			if tc.wantLoaded {
				if result == nil || result.Session == nil {
					t.Fatal("expected session to be loaded")
				}
				if result.SessionID != tc.headerVal {
					t.Errorf("expected session_id=%s, got %s", tc.headerVal, result.SessionID)
				}
			}
		})
	}
}

func TestResolveSessionFromRequest_OrphanSession_Binds(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	mock := &mockSessionGetter{
		sessions: map[string]*sessions.Session{
			"gw_orphan": {
				SessionID: "gw_orphan",
				APIKeyID:  0, // orphan
				TenantID:  "",
			},
		},
	}
	ch.sessionGetter = mock

	r := httptest.NewRequest("POST", "/v1/chat/completions", nil)
	r.Header.Set("X-Gw-Session-Id", "gw_orphan")

	keyInfo := &auth.KeyInfo{ID: 25, TenantID: "tenant-x"}
	result := ch.resolveSessionFromRequest(context.Background(), r, keyInfo)

	if result == nil || result.Session == nil {
		t.Fatal("expected orphan session to be bound")
	}
	if result.Session.APIKeyID != 25 {
		t.Errorf("expected session to be bound to api_key_id=25, got %d", result.Session.APIKeyID)
	}
	if result.Session.TenantID != "tenant-x" {
		t.Errorf("expected tenant_id=tenant-x, got %s", result.Session.TenantID)
	}
}

func TestResolveSessionFromRequest_SessionGetterNil(t *testing.T) {
	ch := NewChatHandler(circuit.NewManager(), limiter.New(), nil, nil, nil, nil)
	// sessionGetter is nil

	r := httptest.NewRequest("POST", "/v1/chat/completions", nil)
	r.Header.Set("X-Gw-Session-Id", "gw_any")

	keyInfo := &auth.KeyInfo{ID: 1, TenantID: "default"}
	result := ch.resolveSessionFromRequest(context.Background(), r, keyInfo)

	if result != nil {
		t.Error("expected nil result when sessionGetter is nil")
	}
}

func TestParseSessionIDFromHeaders_Priority(t *testing.T) {
	r := httptest.NewRequest("POST", "/v1/chat/completions", nil)
	r.Header.Set("X-Gw-Session-Id", "gw_primary")
	r.Header.Set("X-Session-Id", "legacy")
	r.Header.Set("X-Conversation-Id", "conv")

	sessionID := parseSessionIDFromHeaders(r)
	if sessionID != "gw_primary" {
		t.Errorf("expected X-Gw-Session-Id to take precedence, got %s", sessionID)
	}

	r2 := httptest.NewRequest("POST", "/v1/messages", nil)
	r2.Header.Set("X-Conversation-Id", "conv_only")
	sessionID2 := parseSessionIDFromHeaders(r2)
	if sessionID2 != "conv_only" {
		t.Errorf("expected X-Conversation-Id when higher priority headers absent, got %s", sessionID2)
	}
}

func TestParseSessionIDFromHeaders_Empty(t *testing.T) {
	r := httptest.NewRequest("POST", "/v1/responses", nil)
	// No session headers
	sessionID := parseSessionIDFromHeaders(r)
	if sessionID != "" {
		t.Errorf("expected empty session_id, got %s", sessionID)
	}
}
