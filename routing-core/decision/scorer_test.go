package decision

import (
	"context"
	"testing"
)

func TestNewCompositeScorer(t *testing.T) {
	scorer := NewCompositeScorer()
	if scorer == nil {
		t.Fatal("NewCompositeScorer returned nil")
	}

	ds, ok := scorer.(*defaultScorer)
	if !ok {
		t.Fatal("NewCompositeScorer did not return *defaultScorer")
	}

	if ds.weights.Price != 0.3 {
		t.Errorf("Expected Price weight 0.3, got %f", ds.weights.Price)
	}
	if ds.weights.Speed != 0.4 {
		t.Errorf("Expected Speed weight 0.4, got %f", ds.weights.Speed)
	}
	if ds.weights.Stability != 0.3 {
		t.Errorf("Expected Stability weight 0.3, got %f", ds.weights.Stability)
	}
	if ds.weights.PressurePenalty != 2.0 {
		t.Errorf("Expected PressurePenalty 2.0, got %f", ds.weights.PressurePenalty)
	}
}

func TestUpdateWeights(t *testing.T) {
	scorer := NewCompositeScorer()
	newWeights := ScorerWeights{
		Price:           0.5,
		Speed:           0.3,
		Stability:       0.2,
		PressurePenalty: 1.5,
	}

	scorer.UpdateWeights(newWeights)

	ds := scorer.(*defaultScorer)
	if ds.weights.Price != 0.5 {
		t.Errorf("Expected Price weight 0.5, got %f", ds.weights.Price)
	}
	if ds.weights.Speed != 0.3 {
		t.Errorf("Expected Speed weight 0.3, got %f", ds.weights.Speed)
	}
	if ds.weights.Stability != 0.2 {
		t.Errorf("Expected Stability weight 0.2, got %f", ds.weights.Stability)
	}
	if ds.weights.PressurePenalty != 1.5 {
		t.Errorf("Expected PressurePenalty 1.5, got %f", ds.weights.PressurePenalty)
	}
}

func TestCalculatePriceScore(t *testing.T) {
	scorer := NewCompositeScorer().(*defaultScorer)

	tests := []struct {
		name      string
		candidate ScoringCandidate
		expected  float64
	}{
		{
			name: "free candidate",
			candidate: ScoringCandidate{
				PriceInPer1M:  nil,
				PriceOutPer1M: nil,
			},
			expected: 10.0,
		},
		{
			name: "zero prices",
			candidate: ScoringCandidate{
				PriceInPer1M:  ptrFloat64(0),
				PriceOutPer1M: ptrFloat64(0),
			},
			expected: 10.0,
		},
		{
			name: "normal prices",
			candidate: ScoringCandidate{
				PriceInPer1M:  ptrFloat64(0.5),
				PriceOutPer1M: ptrFloat64(1.5),
			},
			expected: 1.0 / 2.0,
		},
		{
			name: "input only",
			candidate: ScoringCandidate{
				PriceInPer1M:  ptrFloat64(2.0),
				PriceOutPer1M: nil,
			},
			expected: 1.0 / 2.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := scorer.calculatePriceScore(tt.candidate)
			if result != tt.expected {
				t.Errorf("Expected %f, got %f", tt.expected, result)
			}
		})
	}
}

func TestCalculateSpeedScore(t *testing.T) {
	scorer := NewCompositeScorer().(*defaultScorer)

	tests := []struct {
		name           string
		latencyMs      int
		expectedApprox float64
	}{
		{
			name:           "very fast",
			latencyMs:      100,
			expectedApprox: 1.0 / 101.0,
		},
		{
			name:           "moderate",
			latencyMs:      500,
			expectedApprox: 1.0 / 501.0,
		},
		{
			name:           "zero latency",
			latencyMs:      0,
			expectedApprox: 1.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			candidate := ScoringCandidate{P95LatencyMs: tt.latencyMs}
			result := scorer.calculateSpeedScore(candidate)
			if result != tt.expectedApprox {
				t.Errorf("Expected %f, got %f", tt.expectedApprox, result)
			}
		})
	}
}

func TestCalculateStabilityScore(t *testing.T) {
	scorer := NewCompositeScorer().(*defaultScorer)

	tests := []struct {
		name      string
		candidate ScoringCandidate
		expected  float64
	}{
		{
			name: "recent success rate with enough samples",
			candidate: ScoringCandidate{
				RecentSuccessRate: ptrFloat64(0.95),
				RecentSamples:     10,
				SuccessRate:       0.80,
			},
			expected: 0.95,
		},
		{
			name: "recent success rate but insufficient samples",
			candidate: ScoringCandidate{
				RecentSuccessRate: ptrFloat64(0.95),
				RecentSamples:     5,
				SuccessRate:       0.80,
			},
			expected: 0.80,
		},
		{
			name: "no recent data, use overall success rate",
			candidate: ScoringCandidate{
				RecentSuccessRate: nil,
				RecentSamples:     0,
				SuccessRate:       0.90,
			},
			expected: 0.90,
		},
		{
			name: "no data at all",
			candidate: ScoringCandidate{
				RecentSuccessRate: nil,
				RecentSamples:     0,
				SuccessRate:       0.0,
			},
			expected: 0.5,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := scorer.calculateStabilityScore(tt.candidate)
			if result != tt.expected {
				t.Errorf("Expected %f, got %f", tt.expected, result)
			}
		})
	}
}

func TestCalculateResourceScore(t *testing.T) {
	scorer := NewCompositeScorer().(*defaultScorer)

	tests := []struct {
		name     string
		pressure float64
		expected float64
	}{
		{
			name:     "no pressure",
			pressure: 0.0,
			expected: 1.0,
		},
		{
			name:     "moderate pressure",
			pressure: 0.5,
			expected: 1.0 / (1.0 + 2.0*0.5),
		},
		{
			name:     "high pressure",
			pressure: 1.0,
			expected: 1.0 / 3.0,
		},
		{
			name:     "negative pressure clamped",
			pressure: -0.5,
			expected: 1.0,
		},
		{
			name:     "over 1.0 pressure clamped",
			pressure: 1.5,
			expected: 1.0 / 3.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			candidate := ScoringCandidate{ResourcePressure: tt.pressure}
			result := scorer.calculateResourceScore(candidate)
			if result != tt.expected {
				t.Errorf("Expected %f, got %f", tt.expected, result)
			}
		})
	}
}

func TestCalculateTierBonus(t *testing.T) {
	scorer := NewCompositeScorer().(*defaultScorer)

	tests := []struct {
		name     string
		tier     int
		expected float64
	}{
		{
			name:     "tier 1",
			tier:     1,
			expected: 0.10,
		},
		{
			name:     "tier 2",
			tier:     2,
			expected: 0.05,
		},
		{
			name:     "tier 3",
			tier:     3,
			expected: 0.0,
		},
		{
			name:     "tier 0",
			tier:     0,
			expected: 0.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			candidate := ScoringCandidate{Tier: tt.tier}
			result := scorer.calculateTierBonus(candidate)
			if result != tt.expected {
				t.Errorf("Expected %f, got %f", tt.expected, result)
			}
		})
	}
}

func TestCalculateWeightBonus(t *testing.T) {
	scorer := NewCompositeScorer().(*defaultScorer)

	tests := []struct {
		name     string
		weight   int
		expected float64
	}{
		{
			name:     "no weight",
			weight:   0,
			expected: 0.0,
		},
		{
			name:     "weight 50",
			weight:   50,
			expected: 0.5,
		},
		{
			name:     "weight 100",
			weight:   100,
			expected: 1.0,
		},
		{
			name:     "weight 200",
			weight:   200,
			expected: 2.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			candidate := ScoringCandidate{Weight: tt.weight}
			result := scorer.calculateWeightBonus(candidate)
			if result != tt.expected {
				t.Errorf("Expected %f, got %f", tt.expected, result)
			}
		})
	}
}

func TestScore(t *testing.T) {
	scorer := NewCompositeScorer()
	ctx := context.Background()

	candidate := ScoringCandidate{
		CredentialID:      1,
		PriceInPer1M:      ptrFloat64(0.5),
		PriceOutPer1M:     ptrFloat64(1.5),
		P95LatencyMs:      200,
		SuccessRate:       0.95,
		RecentSuccessRate: ptrFloat64(0.98),
		RecentSamples:     20,
		ResourcePressure:  0.3,
		Tier:              1,
		Weight:            50,
	}

	score, err := scorer.Score(ctx, candidate)
	if err != nil {
		t.Fatalf("Score returned error: %v", err)
	}

	if score <= 0 {
		t.Errorf("Expected positive score, got %f", score)
	}
}

func TestBatchScore(t *testing.T) {
	scorer := NewCompositeScorer()
	ctx := context.Background()

	candidates := []ScoringCandidate{
		{
			CredentialID:     1,
			PriceInPer1M:     ptrFloat64(1.0),
			PriceOutPer1M:    ptrFloat64(2.0),
			P95LatencyMs:     300,
			SuccessRate:      0.90,
			ResourcePressure: 0.5,
			Tier:             2,
			Weight:           30,
		},
		{
			CredentialID:     2,
			PriceInPer1M:     ptrFloat64(0.5),
			PriceOutPer1M:    ptrFloat64(1.0),
			P95LatencyMs:     150,
			SuccessRate:      0.95,
			ResourcePressure: 0.2,
			Tier:             1,
			Weight:           50,
		},
		{
			CredentialID:     3,
			PriceInPer1M:     ptrFloat64(2.0),
			PriceOutPer1M:    ptrFloat64(4.0),
			P95LatencyMs:     500,
			SuccessRate:      0.85,
			ResourcePressure: 0.8,
			Tier:             3,
			Weight:           10,
		},
	}

	results, err := scorer.BatchScore(ctx, candidates)
	if err != nil {
		t.Fatalf("BatchScore returned error: %v", err)
	}

	if len(results) != 3 {
		t.Fatalf("Expected 3 results, got %d", len(results))
	}

	for i := 0; i < len(results)-1; i++ {
		if results[i].CompositeScore < results[i+1].CompositeScore {
			t.Errorf("Results not sorted descending: %f < %f at index %d",
				results[i].CompositeScore, results[i+1].CompositeScore, i)
		}
	}

	if results[0].Candidate.CredentialID != 2 {
		t.Errorf("Expected best candidate to be ID 2, got %d", results[0].Candidate.CredentialID)
	}
}

func TestBatchScoreEmptyInput(t *testing.T) {
	scorer := NewCompositeScorer()
	ctx := context.Background()

	results, err := scorer.BatchScore(ctx, []ScoringCandidate{})
	if err != nil {
		t.Fatalf("BatchScore returned error: %v", err)
	}

	if len(results) != 0 {
		t.Errorf("Expected 0 results, got %d", len(results))
	}
}

func TestCompositeScoreBreakdown(t *testing.T) {
	scorer := NewCompositeScorer()
	ctx := context.Background()

	candidate := ScoringCandidate{
		CredentialID:     1,
		PriceInPer1M:     ptrFloat64(1.0),
		PriceOutPer1M:    ptrFloat64(1.0),
		P95LatencyMs:     200,
		SuccessRate:      0.90,
		ResourcePressure: 0.3,
		Tier:             1,
		Weight:           50,
	}

	results, err := scorer.BatchScore(ctx, []ScoringCandidate{candidate})
	if err != nil {
		t.Fatalf("BatchScore returned error: %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("Expected 1 result, got %d", len(results))
	}

	breakdown := results[0].Breakdown
	if breakdown.PriceScore <= 0 {
		t.Errorf("Expected positive PriceScore, got %f", breakdown.PriceScore)
	}
	if breakdown.SpeedScore <= 0 {
		t.Errorf("Expected positive SpeedScore, got %f", breakdown.SpeedScore)
	}
	if breakdown.StabilityScore <= 0 {
		t.Errorf("Expected positive StabilityScore, got %f", breakdown.StabilityScore)
	}
	if breakdown.ResourceScore <= 0 {
		t.Errorf("Expected positive ResourceScore, got %f", breakdown.ResourceScore)
	}
	if breakdown.TierBonus != 0.10 {
		t.Errorf("Expected TierBonus 0.10, got %f", breakdown.TierBonus)
	}
	if breakdown.WeightBonus != 0.5 {
		t.Errorf("Expected WeightBonus 0.5, got %f", breakdown.WeightBonus)
	}
}

func TestScenario_HighPriceLowLatency(t *testing.T) {
	scorer := NewCompositeScorer()
	ctx := context.Background()

	expensive := ScoringCandidate{
		CredentialID:     1,
		PriceInPer1M:     ptrFloat64(10.0),
		PriceOutPer1M:    ptrFloat64(20.0),
		P95LatencyMs:     50,
		SuccessRate:      0.99,
		ResourcePressure: 0.1,
		Tier:             1,
		Weight:           0,
	}

	cheap := ScoringCandidate{
		CredentialID:     2,
		PriceInPer1M:     ptrFloat64(0.5),
		PriceOutPer1M:    ptrFloat64(1.0),
		P95LatencyMs:     500,
		SuccessRate:      0.85,
		ResourcePressure: 0.3,
		Tier:             2,
		Weight:           0,
	}

	results, err := scorer.BatchScore(ctx, []ScoringCandidate{expensive, cheap})
	if err != nil {
		t.Fatalf("BatchScore returned error: %v", err)
	}

	t.Logf("Expensive (fast): score=%f", results[0].CompositeScore)
	t.Logf("Cheap (slow): score=%f", results[1].CompositeScore)

	var expensiveScore, cheapScore float64
	for _, r := range results {
		if r.Candidate.CredentialID == 1 {
			expensiveScore = r.CompositeScore
		} else {
			cheapScore = r.CompositeScore
		}
	}

	if expensiveScore <= 0 || cheapScore <= 0 {
		t.Error("Expected both scores to be positive")
	}
}

func TestScenario_FreeTier(t *testing.T) {
	scorer := NewCompositeScorer()
	ctx := context.Background()

	free := ScoringCandidate{
		CredentialID:     1,
		PriceInPer1M:     nil,
		PriceOutPer1M:    nil,
		P95LatencyMs:     300,
		SuccessRate:      0.80,
		ResourcePressure: 0.5,
		Tier:             3,
		Weight:           0,
	}

	paid := ScoringCandidate{
		CredentialID:     2,
		PriceInPer1M:     ptrFloat64(1.0),
		PriceOutPer1M:    ptrFloat64(2.0),
		P95LatencyMs:     200,
		SuccessRate:      0.95,
		ResourcePressure: 0.2,
		Tier:             1,
		Weight:           0,
	}

	results, err := scorer.BatchScore(ctx, []ScoringCandidate{free, paid})
	if err != nil {
		t.Fatalf("BatchScore returned error: %v", err)
	}

	t.Logf("Free: score=%f", results[0].CompositeScore)
	t.Logf("Paid: score=%f", results[1].CompositeScore)

	var freeScore float64
	for _, r := range results {
		if r.Candidate.CredentialID == 1 {
			freeScore = r.CompositeScore
		}
	}

	if freeScore <= 0 {
		t.Error("Expected free tier to have positive score")
	}
}

func TestScenario_HighResourcePressure(t *testing.T) {
	scorer := NewCompositeScorer()
	ctx := context.Background()

	lowPressure := ScoringCandidate{
		CredentialID:     1,
		PriceInPer1M:     ptrFloat64(1.0),
		PriceOutPer1M:    ptrFloat64(1.0),
		P95LatencyMs:     200,
		SuccessRate:      0.90,
		ResourcePressure: 0.1,
		Tier:             2,
		Weight:           0,
	}

	highPressure := ScoringCandidate{
		CredentialID:     2,
		PriceInPer1M:     ptrFloat64(1.0),
		PriceOutPer1M:    ptrFloat64(1.0),
		P95LatencyMs:     200,
		SuccessRate:      0.90,
		ResourcePressure: 0.9,
		Tier:             2,
		Weight:           0,
	}

	results, err := scorer.BatchScore(ctx, []ScoringCandidate{lowPressure, highPressure})
	if err != nil {
		t.Fatalf("BatchScore returned error: %v", err)
	}

	if results[0].Candidate.CredentialID != 1 {
		t.Error("Expected low pressure candidate to rank higher")
	}

	scoreDiff := results[0].CompositeScore - results[1].CompositeScore
	if scoreDiff <= 0 {
		t.Errorf("Expected significant score difference, got %f", scoreDiff)
	}

	t.Logf("Low pressure: score=%f", results[0].CompositeScore)
	t.Logf("High pressure: score=%f", results[1].CompositeScore)
}

func ptrFloat64(v float64) *float64 {
	return &v
}
