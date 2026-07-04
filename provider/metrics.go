package provider

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// qualityGateFallbackTotal counts how many times the routing quality gate
	// had to fall back to a relaxed threshold because no candidates passed
	// the strict threshold.
	qualityGateFallbackTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "llm_gateway_routing_quality_gate_fallback_total",
			Help: "Total number of times routing quality gate used fallback threshold",
		},
		[]string{"model", "threshold"},
	)

	// qualityGateCandidatesFiltered counts candidates filtered by quality gate
	qualityGateCandidatesFiltered = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "llm_gateway_routing_quality_gate_filtered_total",
			Help: "Total number of candidates filtered by quality gate threshold",
		},
		[]string{"model", "threshold"},
	)

	// routingCandidatesTotal tracks the distribution of candidate counts
	routingCandidatesTotal = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "llm_gateway_routing_candidates_count",
			Help:    "Distribution of candidate counts returned by routing",
			Buckets: []float64{0, 1, 2, 3, 5, 10, 20, 50},
		},
		[]string{"model"},
	)

	// autoDiscoveredModelTotal counts models that hit the auto_discovered fallback path
	// (no canonical/alias match, "ghost" canonical created). High counts indicate missing
	// model_offers registration for upstream-supported models (e.g. claude-fable-5 incident).
	autoDiscoveredModelTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "llm_gateway_model_auto_discovered_total",
			Help: "Total number of times a model hit the auto_discovered fallback (unregistered model)",
		},
		[]string{"model"},
	)
)

// RecordQualityGateFallback records when the quality gate had to use a relaxed threshold
func RecordQualityGateFallback(model string, threshold float64) {
	qualityGateFallbackTotal.WithLabelValues(model, formatThreshold(threshold)).Inc()
}

// RecordQualityGateFiltered records candidates filtered by quality gate
func RecordQualityGateFiltered(model string, threshold float64, count int) {
	qualityGateCandidatesFiltered.WithLabelValues(model, formatThreshold(threshold)).Add(float64(count))
}

// RecordRoutingCandidates records the number of candidates returned
func RecordRoutingCandidates(model string, count int) {
	routingCandidatesTotal.WithLabelValues(model).Observe(float64(count))
}

// RecordAutoDiscoveredModel records when a model hits the auto_discovered fallback path.
// Added 2026-07-05 to detect unregistered-but-upstream-available models (claude-fable-5 incident).
func RecordAutoDiscoveredModel(model string) {
	autoDiscoveredModelTotal.WithLabelValues(model).Inc()
}

func formatThreshold(t float64) string {
	if t == 0.0 {
		return "0.0_relaxed"
	} else if t == 0.3 {
		return "0.3_strict"
	}
	return "custom"
}
