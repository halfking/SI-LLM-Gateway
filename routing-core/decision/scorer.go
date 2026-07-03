package decision

import (
	"context"
	"math"
	"sort"
	"strings"
)

type CompositeScorer interface {
	Score(ctx context.Context, candidate ScoringCandidate) (float64, error)
	BatchScore(ctx context.Context, candidates []ScoringCandidate) ([]ScoredCandidate, error)
	UpdateWeights(weights ScorerWeights)
}

type ScoringCandidate struct {
	CredentialID      int
	ProviderID        int
	Model             string
	PriceInPer1M      *float64
	PriceOutPer1M     *float64
	BillingMode       string
	P95LatencyMs      int
	SuccessRate       float64
	RecentSuccessRate *float64
	RecentSamples     int
	ResourcePressure  float64
	Tier              int
	Weight            int
	ManualPriority    int
}

type ScoredCandidate struct {
	Candidate      ScoringCandidate
	CompositeScore float64
	Breakdown      ScoreBreakdown
}

type ScoreBreakdown struct {
	PriceScore     float64
	SpeedScore     float64
	StabilityScore float64
	ResourceScore  float64
	TierBonus      float64
	WeightBonus    float64
}

type ScorerWeights struct {
	Price           float64
	Speed           float64
	Stability       float64
	PressurePenalty float64
}

type defaultScorer struct {
	weights ScorerWeights
}

func NewCompositeScorer() CompositeScorer {
	return &defaultScorer{
		weights: ScorerWeights{
			Price:           0.3,
			Speed:           0.4,
			Stability:       0.3,
			PressurePenalty: 2.0,
		},
	}
}

func (s *defaultScorer) UpdateWeights(weights ScorerWeights) {
	s.weights = weights
}

func (s *defaultScorer) Score(ctx context.Context, candidate ScoringCandidate) (float64, error) {
	breakdown := s.calculateBreakdown(candidate)
	return s.compositeScore(breakdown), nil
}

func (s *defaultScorer) BatchScore(ctx context.Context, candidates []ScoringCandidate) ([]ScoredCandidate, error) {
	results := make([]ScoredCandidate, 0, len(candidates))

	for _, candidate := range candidates {
		breakdown := s.calculateBreakdown(candidate)
		score := s.compositeScore(breakdown)

		results = append(results, ScoredCandidate{
			Candidate:      candidate,
			CompositeScore: score,
			Breakdown:      breakdown,
		})
	}

	sort.Slice(results, func(i, j int) bool {
		return results[i].CompositeScore > results[j].CompositeScore
	})

	return results, nil
}

func (s *defaultScorer) calculateBreakdown(candidate ScoringCandidate) ScoreBreakdown {
	priceScore := s.calculatePriceScore(candidate)
	speedScore := s.calculateSpeedScore(candidate)
	stabilityScore := s.calculateStabilityScore(candidate)
	resourceScore := s.calculateResourceScore(candidate)
	tierBonus := s.calculateTierBonus(candidate)
	weightBonus := s.calculateWeightBonus(candidate)

	return ScoreBreakdown{
		PriceScore:     priceScore,
		SpeedScore:     speedScore,
		StabilityScore: stabilityScore,
		ResourceScore:  resourceScore,
		TierBonus:      tierBonus,
		WeightBonus:    weightBonus,
	}
}

func (s *defaultScorer) calculatePriceScore(candidate ScoringCandidate) float64 {
	cost := 0.0
	if candidate.PriceInPer1M != nil {
		cost += *candidate.PriceInPer1M
	}
	if candidate.PriceOutPer1M != nil {
		cost += *candidate.PriceOutPer1M
	}

	if cost == 0.0 {
		return 10.0
	}

	return 1.0 / cost
}

func (s *defaultScorer) calculateSpeedScore(candidate ScoringCandidate) float64 {
	return 1.0 / float64(candidate.P95LatencyMs+1)
}

func (s *defaultScorer) calculateStabilityScore(candidate ScoringCandidate) float64 {
	if candidate.RecentSuccessRate != nil && candidate.RecentSamples >= 10 {
		return *candidate.RecentSuccessRate
	}

	if candidate.SuccessRate > 0 {
		return candidate.SuccessRate
	}

	return 0.5
}

func (s *defaultScorer) calculateResourceScore(candidate ScoringCandidate) float64 {
	pressure := math.Max(0.0, math.Min(1.0, candidate.ResourcePressure))
	return 1.0 / (1.0 + s.weights.PressurePenalty*pressure)
}

func (s *defaultScorer) calculateTierBonus(candidate ScoringCandidate) float64 {
	switch candidate.Tier {
	case 1:
		return 0.10
	case 2:
		return 0.05
	default:
		return 0.0
	}
}

func (s *defaultScorer) calculateWeightBonus(candidate ScoringCandidate) float64 {
	if candidate.Weight > 0 {
		return float64(candidate.Weight) / 100.0
	}
	return 0.0
}

func (s *defaultScorer) compositeScore(breakdown ScoreBreakdown) float64 {
	baseScore := (s.weights.Price * breakdown.PriceScore) +
		(s.weights.Speed * breakdown.SpeedScore) +
		(s.weights.Stability * breakdown.StabilityScore)

	baseScore *= breakdown.ResourceScore

	baseScore *= (1.0 + breakdown.TierBonus)

	baseScore *= (1.0 + breakdown.WeightBonus)

	return baseScore
}

func (s *defaultScorer) calculateBillingModeBonus(candidate ScoringCandidate) float64 {
	billingLower := strings.ToLower(candidate.BillingMode)
	if strings.Contains(billingLower, "plan") || strings.Contains(billingLower, "free") {
		return 0.20
	}
	return 0.0
}
