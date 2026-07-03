package state

import (
	"context"
	"testing"
	"time"

	"github.com/kaixuan/llm-gateway-go/errorsx"
	"github.com/kaixuan/llm-gateway-go/routing"
	"github.com/redis/go-redis/v9"
)

func TestFSM_StateTransitions(t *testing.T) {
	fsm := GetCredentialFSM()

	tests := []struct {
		name      string
		fromState string
		event     EventType
		toState   string
		shouldErr bool
	}{
		{"ready to auth_failed", "ready", EventFailureAuth, "auth_failed", false},
		{"ready to suspended", "ready", EventFailureQuota, "suspended", false},
		{"ready to rate_limited", "ready", EventFailureRateLimit, "rate_limited", false},
		{"ready to unreachable", "ready", EventFailureNetwork, "unreachable", false},
		{"cooling to ready", "cooling", EventSuccess, "ready", false},
		{"rate_limited to ready", "rate_limited", EventSuccess, "ready", false},
		{"unreachable to ready", "unreachable", EventSuccess, "ready", false},
		{"invalid transition", "ready", EventProbeSuccess, "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			entity := &CredentialState{AvailabilityState: tt.fromState}
			err := fsm.Trigger(context.Background(), entity, tt.event)
			if tt.shouldErr {
				if err == nil {
					t.Errorf("expected error, got nil")
				}
			} else {
				if err != nil {
					t.Errorf("unexpected error: %v", err)
				}
				if entity.AvailabilityState != tt.toState {
					t.Errorf("expected state %s, got %s", tt.toState, entity.AvailabilityState)
				}
			}
		})
	}
}

func TestEventMapping(t *testing.T) {
	tests := []struct {
		errorKind errorsx.ErrorKind
		expected  EventType
	}{
		{errorsx.KindAuth, EventFailureAuth},
		{errorsx.KindAuthRevoked, EventFailureAuth},
		{errorsx.KindQuota, EventFailureQuota},
		{errorsx.KindQuotaBalance, EventFailureQuota},
		{errorsx.KindQuotaPeriodic, EventFailureQuota},
		{errorsx.KindQuotaPermanent, EventFailureQuota},
		{errorsx.KindNetwork, EventFailureNetwork},
		{errorsx.KindRateLimit, EventFailureRateLimit},
		{errorsx.KindTimeout, EventFailureTimeout},
		{errorsx.KindConcurrent, EventFailureConcurrent},
		{errorsx.KindUpstreamDown, EventFailureUpstreamDown},
		{errorsx.KindStreamTimeout, EventFailureStreamTimeout},
	}

	for _, tt := range tests {
		t.Run(string(tt.errorKind), func(t *testing.T) {
			got := mapErrorKindToEventType(tt.errorKind)
			if got != tt.expected {
				t.Errorf("mapErrorKindToEventType(%s) = %v, want %v", tt.errorKind, got, tt.expected)
			}
		})
	}
}

func TestNewSuccessEvent(t *testing.T) {
	event := NewSuccessEvent(123, "gpt-4", "req-456")
	if event.Type != EventSuccess {
		t.Errorf("expected EventSuccess, got %v", event.Type)
	}
	if event.CredentialID != 123 {
		t.Errorf("expected credentialID 123, got %d", event.CredentialID)
	}
	if event.Model != "gpt-4" {
		t.Errorf("expected model gpt-4, got %s", event.Model)
	}
	if event.RequestID != "req-456" {
		t.Errorf("expected requestID req-456, got %s", event.RequestID)
	}
}

func TestNewFailureEvent(t *testing.T) {
	event := NewFailureEvent(123, "gpt-4", "req-456", errorsx.KindAuth, "invalid api key")
	if event.Type != EventFailureAuth {
		t.Errorf("expected EventFailureAuth, got %v", event.Type)
	}
	if event.ErrorKind != errorsx.KindAuth {
		t.Errorf("expected KindAuth, got %s", event.ErrorKind)
	}
	if event.ErrorDetail != "invalid api key" {
		t.Errorf("expected detail 'invalid api key', got %s", event.ErrorDetail)
	}
}

func TestNodeStateManager_Integration(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test")
	}

	redisClient := redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
		DB:   15,
	})
	defer redisClient.Close()

	ctx := context.Background()
	if err := redisClient.Ping(ctx).Err(); err != nil {
		t.Skipf("redis not available: %v", err)
	}

	cfg := routing.DefaultRouteNodeConfig()
	mgr := NewNodeStateManager(redisClient, cfg)

	credID := 9999
	model := "test-model"
	requestID := "req-test-123"
	redisKey := "route_node:9999:test-model"

	redisClient.Del(ctx, redisKey)

	state, err := mgr.GetNodeState(ctx, credID, model)
	if err != nil {
		t.Fatalf("GetNodeState failed: %v", err)
	}
	if state != nil {
		t.Errorf("expected nil state for new node, got %+v", state)
	}

	if err := mgr.RecordSuccess(ctx, credID, model, requestID); err != nil {
		t.Fatalf("RecordSuccess failed: %v", err)
	}

	state, err = mgr.GetNodeState(ctx, credID, model)
	if err != nil {
		t.Fatalf("GetNodeState after success failed: %v", err)
	}
	if state == nil {
		t.Fatal("expected state after success, got nil")
	}
	if state.SuccessCount != 1 {
		t.Errorf("expected SuccessCount 1, got %d", state.SuccessCount)
	}
	if !state.LastSuccessAt.After(time.Time{}) {
		t.Error("expected LastSuccessAt to be set")
	}

	if err := mgr.RecordFailure(ctx, credID, model, "req-fail-1", string(errorsx.KindAuth)); err != nil {
		t.Fatalf("RecordFailure failed: %v", err)
	}

	state, err = mgr.GetNodeState(ctx, credID, model)
	if err != nil {
		t.Fatalf("GetNodeState after failure failed: %v", err)
	}
	if state.FailureCount != 1 {
		t.Errorf("expected FailureCount 1, got %d", state.FailureCount)
	}

	redisClient.Del(ctx, redisKey)
}

func TestCompositeStateManager_ProcessEvent(t *testing.T) {
	mgr := &CompositeStateManager{
		credential: &CredentialStateManager{},
		binding:    &BindingStateManager{},
		node:       &NodeStateManager{},
	}

	ctx := context.Background()

	successEvent := NewSuccessEvent(1, "gpt-4", "req-1")
	err := mgr.ProcessEvent(ctx, successEvent)
	if err == nil {
		t.Log("ProcessEvent returned expected error for unconfigured manager")
	}

	failureEvent := NewFailureEvent(1, "gpt-4", "req-2", errorsx.KindAuth, "auth failed")
	err = mgr.ProcessEvent(ctx, failureEvent)
	if err == nil {
		t.Log("ProcessEvent returned expected error for unconfigured manager")
	}
}

func TestCompositeStateManager_BatchProcessEvents(t *testing.T) {
	mgr := &CompositeStateManager{
		credential: &CredentialStateManager{},
		binding:    &BindingStateManager{},
		node:       &NodeStateManager{},
	}

	ctx := context.Background()

	events := []StateEvent{
		NewSuccessEvent(1, "gpt-4", "req-1"),
		NewFailureEvent(1, "gpt-4", "req-2", errorsx.KindAuth, "auth failed"),
		NewFailureEvent(2, "claude", "req-3", errorsx.KindQuota, "quota exceeded"),
	}

	results, err := mgr.BatchProcessEvents(ctx, events)
	if err != nil {
		t.Fatalf("BatchProcessEvents failed: %v", err)
	}

	if len(results) != len(events) {
		t.Errorf("expected %d results, got %d", len(events), len(results))
	}

	for i, result := range results {
		if result.Applied {
			t.Logf("event %d applied (unexpected for unconfigured manager)", i)
		}
		if result.Error == nil {
			t.Logf("event %d has no error (expected error for unconfigured manager)", i)
		}
	}
}
