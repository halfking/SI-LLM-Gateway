package ccr

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Prometheus metrics for CCR (Columnar Content Repository) three-tier cache.
var (
	// Cache operations counters
	ccrCacheHits = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "llm_gateway_ccr_cache_hits_total",
		Help: "Total number of CCR cache hits by tier (L1/L2/L3).",
	}, []string{"tier"})

	ccrCacheMisses = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "llm_gateway_ccr_cache_misses_total",
		Help: "Total number of CCR cache misses by tier (L1/L2/L3).",
	}, []string{"tier"})

	ccrPutsTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "llm_gateway_ccr_puts_total",
		Help: "Total number of CCR Put operations (store compressed data).",
	})

	ccrGetsTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "llm_gateway_ccr_gets_total",
		Help: "Total number of CCR Get operations (retrieve compressed data).",
	})

	ccrErrorsTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "llm_gateway_ccr_errors_total",
		Help: "Total number of CCR errors (L2/L3 failures, unauthorized access, etc.).",
	})

	// Cache hit ratio gauge (computed periodically)
	ccrHitRatio = promauto.NewGaugeVec(prometheus.GaugeOpts{
		Name: "llm_gateway_ccr_hit_ratio",
		Help: "CCR cache hit ratio by tier (0.0 to 1.0).",
	}, []string{"tier"})

	ccrOverallHitRatio = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "llm_gateway_ccr_hit_ratio_overall",
		Help: "CCR overall cache hit ratio across all tiers (0.0 to 1.0).",
	})
)

// RecordCacheHit increments the cache hit counter for the specified tier.
func RecordCacheHit(tier string) {
	ccrCacheHits.WithLabelValues(tier).Inc()
}

// RecordCacheMiss increments the cache miss counter for the specified tier.
func RecordCacheMiss(tier string) {
	ccrCacheMisses.WithLabelValues(tier).Inc()
}

// RecordPut increments the Put operation counter.
func RecordPut() {
	ccrPutsTotal.Inc()
}

// RecordGet increments the Get operation counter.
func RecordGet() {
	ccrGetsTotal.Inc()
}

// RecordError increments the error counter.
func RecordError() {
	ccrErrorsTotal.Inc()
}

// UpdateMetrics updates Prometheus gauges with current metrics snapshot.
// This should be called periodically (e.g., every 10s) by a background goroutine.
func (m *Manager) UpdateMetrics() {
	metrics := m.getMetrics()

	// Update hit ratio gauges
	l1Total := metrics.L1Hits + metrics.L1Misses
	if l1Total > 0 {
		ccrHitRatio.WithLabelValues("L1").Set(float64(metrics.L1Hits) / float64(l1Total))
	}

	l2Total := metrics.L2Hits + metrics.L2Misses
	if l2Total > 0 {
		ccrHitRatio.WithLabelValues("L2").Set(float64(metrics.L2Hits) / float64(l2Total))
	}

	l3Total := metrics.L3Hits + metrics.L3Misses
	if l3Total > 0 {
		ccrHitRatio.WithLabelValues("L3").Set(float64(metrics.L3Hits) / float64(l3Total))
	}

	ccrOverallHitRatio.Set(metrics.HitRatio())
}
