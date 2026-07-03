// Package routingcore tests for the unified Engine.
package routingcore

import (
	"context"
	"errors"
	"testing"

	"github.com/kaixuan/llm-gateway-go/routing-core/decision"
	"github.com/kaixuan/llm-gateway-go/routing-core/resource"
	"github.com/kaixuan/llm-gateway-go/routing-core/state"
	"github.com/kaixuan/llm-gateway-go/routing-core/tracking"
)

// mockEngineRM implements resource.ResourceManager for testing.
type mockEngineRM struct {
	eligibilities map[int]bool
}

func (m *mockEngineRM) CheckEligibility(ctx context.Context, req resource.EligibilityRequest) (*resource.EligibilityResult, error) {
	eligible, ok := m.eligibilities[req.CredentialID]
	if !ok {
		eligible = true
	}
	return &resource.EligibilityResult{
		Eligible:          eligible,
		FpSlotAvailable:   eligible,
		ConcurAvailable:   eligible,
		ResourcePressure:  0.3,
		RecommendedAction: "proceed",
	}, nil
}

func (m *mockEngineRM) AcquireResources(ctx context.Context, req resource.AcquireRequest) (*resource.AcquiredResources, resource.ReleaseFunc, error) {
	return &resource.AcquiredResources{}, func(ctx context.Context) error { return nil }, nil
}

func (m *mockEngineRM) GetResourceStats(ctx context.Context, credentialID int) (*resource.ResourceStats, error) {
	return &resource.ResourceStats{}, nil
}

func (m *mockEngineRM) CalculatePressure(ctx context.Context, credentialID int) (float64, error) {
	return 0.3, nil
}

// mockEngineSM implements state.StateManager for testing.
type mockEngineSM struct {
	events []string
}

func (m *mockEngineSM) GetCredentialState(ctx context.Context, credentialID int) (*state.CredentialState, error) {
	return &state.CredentialState{CredentialID: credentialID, AvailabilityState: "ready"}, nil
}

func (m *mockEngineSM) GetBindingState(ctx context.Context, credentialID int, model string) (*state.BindingState, error) {
	return &state.BindingState{CredentialID: credentialID, Model: model, Available: true}, nil
}

func (m *mockEngineSM) GetNodeState(ctx context.Context, credentialID int, model string) (*state.NodeState, error) {
	return &state.NodeState{CredentialID: credentialID, Model: model}, nil
}

func (m *mockEngineSM) ProcessEvent(ctx context.Context, event state.StateEvent) error {
	m.events = append(m.events, eventTypeToString(event.Type))
	return nil
}

func eventTypeToString(t state.EventType) string {
	switch t {
	case state.EventSuccess:
		return "EventSuccess"
	case state.EventFailureAuth:
		return "EventFailureAuth"
	case state.EventFailureQuota:
		return "EventFailureQuota"
	case state.EventFailureNetwork:
		return "EventFailureNetwork"
	case state.EventFailureRateLimit:
		return "EventFailureRateLimit"
	case state.EventFailureTimeout:
		return "EventFailureTimeout"
	case state.EventFailureConcurrent:
		return "EventFailureConcurrent"
	case state.EventFailureUpstreamDown:
		return "EventFailureUpstreamDown"
	case state.EventFailureStreamTimeout:
		return "EventFailureStreamTimeout"
	case state.EventManualDisable:
		return "EventManualDisable"
	case state.EventManualEnable:
		return "EventManualEnable"
	case state.EventManualSuspend:
		return "EventManualSuspend"
	case state.EventProbeSuccess:
		return "EventProbeSuccess"
	case state.EventProbeFailure:
		return "EventProbeFailure"
	default:
		return "Unknown"
	}
}

func (m *mockEngineSM) BatchProcessEvents(ctx context.Context, events []state.StateEvent) ([]state.EventResult, error) {
	results := make([]state.EventResult, 0, len(events))
	for _, e := range events {
		_ = m.ProcessEvent(ctx, e)
		results = append(results, state.EventResult{Event: e, Applied: true})
	}
	return results, nil
}

func TestEngine_Plan_BasicSelection(t *testing.T) {
	ctx := context.Background()

	rm := &mockEngineRM{eligibilities: map[int]bool{1: true, 2: true}}
	scorer := decision.NewCompositeScorer()
	classifier := tracking.NewErrorClassifier()
	sm := &mockEngineSM{}

	engine := NewEngine(rm, scorer, classifier, sm, nil)

	candidates := []Candidate{
		{CredentialID: 1, ProviderID: 1, Model: "gpt-4", Tier: 1, Weight: 100,
			PriceInPer1M: float64Ptr(10), P95LatencyMs: 1000, SuccessRate: 0.99, Holder: "session-1"},
		{CredentialID: 2, ProviderID: 1, Model: "gpt-4", Tier: 2, Weight: 50,
			PriceInPer1M: float64Ptr(5), P95LatencyMs: 3000, SuccessRate: 0.90, Holder: "session-1"},
	}

	result, err := engine.Plan(ctx, PlanRequest{
		RequestID: "req-1",
		Model:     "gpt-4",
		Holder:    "session-1",
	}, candidates)

	if err != nil {
		t.Fatalf("Plan failed: %v", err)
	}

	if result.Selected == nil {
		t.Fatal("expected a selected candidate")
	}

	if result.Selected.Candidate.CredentialID != 1 {
		t.Errorf("expected credential 1 (tier 1, lower latency), got %d", result.Selected.Candidate.CredentialID)
	}

	if len(result.Alternatives) != 1 {
		t.Errorf("expected 1 alternative, got %d", len(result.Alternatives))
	}
}

func TestEngine_Plan_ResourceFilter(t *testing.T) {
	ctx := context.Background()

	rm := &mockEngineRM{eligibilities: map[int]bool{1: true, 2: false}}
	scorer := decision.NewCompositeScorer()
	classifier := tracking.NewErrorClassifier()
	sm := &mockEngineSM{}

	engine := NewEngine(rm, scorer, classifier, sm, nil)

	candidates := []Candidate{
		{CredentialID: 1, ProviderID: 1, Model: "gpt-4", Tier: 1, Holder: "session-1"},
		{CredentialID: 2, ProviderID: 1, Model: "gpt-4", Tier: 1, Holder: "session-1"},
	}

	result, err := engine.Plan(ctx, PlanRequest{
		RequestID: "req-2",
		Model:     "gpt-4",
		Holder:    "session-1",
	}, candidates)

	if err != nil {
		t.Fatalf("Plan failed: %v", err)
	}

	if result.Selected.Candidate.CredentialID != 1 {
		t.Errorf("expected only credential 1 to be selectable, got %d", result.Selected.Candidate.CredentialID)
	}

	if len(result.Skipped) != 1 {
		t.Errorf("expected 1 skipped candidate, got %d", len(result.Skipped))
	}
}

func TestEngine_ReportResult_Success(t *testing.T) {
	ctx := context.Background()
	rm := &mockEngineRM{}
	scorer := decision.NewCompositeScorer()
	classifier := tracking.NewErrorClassifier()
	sm := &mockEngineSM{}

	engine := NewEngine(rm, scorer, classifier, sm, nil)

	err := engine.ReportResult(ctx, RequestOutcome{
		RequestID:    "req-success",
		CredentialID: 1,
		Model:        "gpt-4",
		StatusCode:   200,
	})

	if err != nil {
		t.Fatalf("ReportResult failed: %v", err)
	}

	if len(sm.events) != 1 {
		t.Errorf("expected 1 event, got %d", len(sm.events))
	}

	if sm.events[0] != "EventSuccess" {
		t.Errorf("expected EventSuccess, got %s", sm.events[0])
	}
}

func TestEngine_ReportResult_AuthFailure(t *testing.T) {
	ctx := context.Background()
	rm := &mockEngineRM{}
	scorer := decision.NewCompositeScorer()
	classifier := tracking.NewErrorClassifier()
	sm := &mockEngineSM{}

	engine := NewEngine(rm, scorer, classifier, sm, nil)

	err := engine.ReportResult(ctx, RequestOutcome{
		RequestID:    "req-auth",
		CredentialID: 1,
		Model:        "gpt-4",
		StatusCode:   401,
		Error:        errors.New("invalid api key"),
	})

	if err != nil {
		t.Fatalf("ReportResult failed: %v", err)
	}

	if len(sm.events) != 1 {
		t.Errorf("expected 1 event, got %d", len(sm.events))
	}

	if sm.events[0] != "EventFailureAuth" {
		t.Errorf("expected EventFailureAuth, got %s", sm.events[0])
	}
}

func TestEngine_ReportResult_RateLimit(t *testing.T) {
	ctx := context.Background()
	rm := &mockEngineRM{}
	scorer := decision.NewCompositeScorer()
	classifier := tracking.NewErrorClassifier()
	sm := &mockEngineSM{}

	engine := NewEngine(rm, scorer, classifier, sm, nil)

	err := engine.ReportResult(ctx, RequestOutcome{
		RequestID:    "req-rl",
		CredentialID: 1,
		Model:        "gpt-4",
		StatusCode:   429,
		Error:        errors.New("rate limit exceeded"),
	})

	if err != nil {
		t.Fatalf("ReportResult failed: %v", err)
	}

	if len(sm.events) != 1 {
		t.Errorf("expected 1 event, got %d", len(sm.events))
	}

	if sm.events[0] != "EventFailureRateLimit" {
		t.Errorf("expected EventFailureRateLimit, got %s", sm.events[0])
	}
}

func float64Ptr(v float64) *float64 {
	return &v
}
