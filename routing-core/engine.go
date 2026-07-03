// Package routingcore provides the unified routing engine.
//
// The Engine orchestrates the four core modules:
//   - ResourceManager: Fingerprint slots and concurrency
//   - CompositeScorer: Price + speed + stability scoring
//   - ErrorClassifier: Error categorization
//   - StateManager: Multi-dimensional state management
//
// The Engine is the single entry point for routing decisions. It is
// designed to be thread-safe and stateless across requests.
package routingcore

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/kaixuan/llm-gateway-go/errorsx"
	"github.com/kaixuan/llm-gateway-go/routing-core/decision"
	"github.com/kaixuan/llm-gateway-go/routing-core/resource"
	"github.com/kaixuan/llm-gateway-go/routing-core/state"
	"github.com/kaixuan/llm-gateway-go/routing-core/tracking"
)

// Candidate represents a routing candidate with all the information needed
// to make a decision.
type Candidate struct {
	CredentialID      int
	ProviderID        int
	Model             string
	BillingMode       string
	Tier              int
	Weight            int
	PriceInPer1M      *float64
	PriceOutPer1M     *float64
	P95LatencyMs      int
	SuccessRate       float64
	RecentSuccessRate *float64
	RecentSamples     int
	FpSlotLimit       *int
	ConcurrencyLimit  int
	Holder            string
}

// PlanRequest represents a request to plan candidates.
type PlanRequest struct {
	RequestID        string
	Model            string
	Holder           string
	StickyCredential *int
	SessionPreferred *int
}

// PlanResult represents the output of planning.
type PlanResult struct {
	RequestID    string
	Selected     *decision.ScoredCandidate
	Alternatives []decision.ScoredCandidate
	Skipped      []SkippedCandidate
	Pressure     map[int]float64
}

// SkippedCandidate records why a candidate was filtered out.
type SkippedCandidate struct {
	Candidate Candidate
	Reason    string
}

// Engine is the unified routing engine.
type Engine struct {
	resource   resource.ResourceManager
	scorer     decision.CompositeScorer
	classifier tracking.ErrorClassifier
	stateMgr   state.StateManager
	logger     *slog.Logger
}

// NewEngine creates a new routing engine.
func NewEngine(
	rm resource.ResourceManager,
	sc decision.CompositeScorer,
	cl tracking.ErrorClassifier,
	sm state.StateManager,
	logger *slog.Logger,
) *Engine {
	if logger == nil {
		logger = slog.Default()
	}
	return &Engine{
		resource:   rm,
		scorer:     sc,
		classifier: cl,
		stateMgr:   sm,
		logger:     logger,
	}
}

// Plan is the main entry point for routing decisions.
//
// The flow:
//  1. Filter candidates by resource eligibility
//  2. Score remaining candidates
//  3. Apply session/sticky preferences
//  4. Return the best candidate with alternatives
func (e *Engine) Plan(ctx context.Context, req PlanRequest, candidates []Candidate) (*PlanResult, error) {
	result := &PlanResult{
		RequestID:    req.RequestID,
		Skipped:      []SkippedCandidate{},
		Alternatives: []decision.ScoredCandidate{},
		Pressure:     make(map[int]float64),
	}

	if len(candidates) == 0 {
		return result, fmt.Errorf("no candidates provided")
	}

	eligible := make([]Candidate, 0, len(candidates))
	for _, c := range candidates {
		eligResult, err := e.resource.CheckEligibility(ctx, resource.EligibilityRequest{
			CredentialID:     c.CredentialID,
			Holder:           c.Holder,
			FpSlotLimit:      c.FpSlotLimit,
			ConcurrencyLimit: c.ConcurrencyLimit,
		})
		if err != nil {
			e.logger.WarnContext(ctx, "eligibility check failed",
				"credential_id", c.CredentialID,
				"error", err)
			result.Skipped = append(result.Skipped, SkippedCandidate{
				Candidate: c,
				Reason:    "eligibility_check_error",
			})
			continue
		}

		pressure, _ := e.resource.CalculatePressure(ctx, c.CredentialID)
		result.Pressure[c.CredentialID] = pressure

		if !eligResult.Eligible {
			result.Skipped = append(result.Skipped, SkippedCandidate{
				Candidate: c,
				Reason:    eligResult.RecommendedAction,
			})
			continue
		}

		eligible = append(eligible, c)
	}

	if len(eligible) == 0 {
		return result, fmt.Errorf("no eligible candidates")
	}

	scoring := make([]decision.ScoringCandidate, 0, len(eligible))
	for _, c := range eligible {
		pressure := result.Pressure[c.CredentialID]
		scoring = append(scoring, decision.ScoringCandidate{
			CredentialID:      c.CredentialID,
			ProviderID:        c.ProviderID,
			Model:             c.Model,
			PriceInPer1M:      c.PriceInPer1M,
			PriceOutPer1M:     c.PriceOutPer1M,
			BillingMode:       c.BillingMode,
			P95LatencyMs:      c.P95LatencyMs,
			SuccessRate:       c.SuccessRate,
			RecentSuccessRate: c.RecentSuccessRate,
			RecentSamples:     c.RecentSamples,
			ResourcePressure:  pressure,
			Tier:              c.Tier,
			Weight:            c.Weight,
		})
	}

	scored, err := e.scorer.BatchScore(ctx, scoring)
	if err != nil {
		return result, fmt.Errorf("scoring failed: %w", err)
	}

	if req.SessionPreferred != nil {
		scored = applySessionPreference(scored, *req.SessionPreferred)
	} else if req.StickyCredential != nil {
		scored = applyStickyPreference(scored, *req.StickyCredential)
	}

	if len(scored) == 0 {
		return result, fmt.Errorf("no scored candidates")
	}

	result.Selected = &scored[0]
	result.Alternatives = scored[1:]
	return result, nil
}

// ReportResult reports the outcome of a request.
//
// This is the "状态回送" entry point. The flow:
//  1. Classify the error (if any)
//  2. Build a state event
//  3. Process through state manager
func (e *Engine) ReportResult(ctx context.Context, outcome RequestOutcome) error {
	if outcome.Error == nil {
		event := state.NewSuccessEvent(outcome.CredentialID, outcome.Model, outcome.RequestID)
		return e.stateMgr.ProcessEvent(ctx, event)
	}

	classified, err := e.classifier.Classify(tracking.ClassifyInput{
		StatusCode:   outcome.StatusCode,
		ErrorMessage: outcome.Error.Error(),
		Upstream:     fmt.Sprintf("provider-%d", outcome.ProviderID),
	})
	if err != nil {
		e.logger.WarnContext(ctx, "classification failed", "error", err)
		classified = &tracking.ClassifiedError{
			Kind:      "unknown",
			Level:     tracking.RequestLevel,
			Cooldown:  30 * time.Second,
			Retryable: false,
		}
	}

	var eventType state.EventType
	if classified.Level == tracking.CredentialLevel {
		eventType = mapToCredentialEvent(classified.Kind)
	} else {
		eventType = mapToModelEvent(classified.Kind)
	}

	var errorKind errorsx.ErrorKind
	switch classified.Kind {
	case "auth":
		errorKind = errorsx.KindAuth
	case "quota":
		errorKind = errorsx.KindQuota
	case "rate_limit":
		errorKind = errorsx.KindRateLimit
	case "timeout":
		errorKind = errorsx.KindTimeout
	case "upstream_down":
		errorKind = errorsx.KindUpstreamDown
	default:
		errorKind = errorsx.KindNetwork
	}

	event := state.StateEvent{
		Type:         eventType,
		CredentialID: outcome.CredentialID,
		Model:        outcome.Model,
		RequestID:    outcome.RequestID,
		ErrorKind:    errorKind,
		ErrorDetail:  classified.Detail,
		RetryAfter:   classified.Cooldown,
		Timestamp:    time.Now(),
	}

	return e.stateMgr.ProcessEvent(ctx, event)
}

// RequestOutcome represents the result of a request.
type RequestOutcome struct {
	RequestID    string
	CredentialID int
	ProviderID   int
	Model        string
	StatusCode   int
	Duration     time.Duration
	Error        error
}

func applySessionPreference(scored []decision.ScoredCandidate, preferredID int) []decision.ScoredCandidate {
	if preferredID == 0 {
		return scored
	}
	preferred := []decision.ScoredCandidate{}
	rest := []decision.ScoredCandidate{}
	for _, s := range scored {
		if s.Candidate.CredentialID == preferredID {
			preferred = append(preferred, s)
		} else {
			rest = append(rest, s)
		}
	}
	return append(preferred, rest...)
}

func applyStickyPreference(scored []decision.ScoredCandidate, stickyID int) []decision.ScoredCandidate {
	return applySessionPreference(scored, stickyID)
}

func mapToCredentialEvent(kind string) state.EventType {
	switch kind {
	case "auth":
		return state.EventFailureAuth
	case "quota":
		return state.EventFailureQuota
	default:
		return state.EventFailureNetwork
	}
}

func mapToModelEvent(kind string) state.EventType {
	switch kind {
	case "rate_limit":
		return state.EventFailureRateLimit
	case "timeout":
		return state.EventFailureTimeout
	case "upstream_down":
		return state.EventFailureUpstreamDown
	default:
		return state.EventFailureNetwork
	}
}
