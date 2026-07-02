package headroom

import (
	"sync/atomic"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	// Compression metrics
	arraysCompressedTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "headroom_arrays_compressed_total",
		Help: "Total number of JSON arrays compressed by Headroom",
	})

	itemsBeforeCompression = promauto.NewCounter(prometheus.CounterOpts{
		Name: "headroom_items_before_compression_total",
		Help: "Total number of items before Headroom compression",
	})

	itemsAfterCompression = promauto.NewCounter(prometheus.CounterOpts{
		Name: "headroom_items_after_compression_total",
		Help: "Total number of items after Headroom compression",
	})

	compressionRatioHistogram = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "headroom_compression_ratio",
		Help:    "Headroom compression ratio distribution",
		Buckets: []float64{0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0},
	})

	losslessPathTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "headroom_lossless_path_total",
		Help: "Total compressions using lossless path",
	}, []string{"strategy"})

	lossyPathTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "headroom_lossy_path_total",
		Help: "Total compressions using lossy path with CCR",
	})

	adaptiveKDistribution = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "headroom_adaptive_k_distribution",
		Help:    "Distribution of adaptive k values",
		Buckets: []float64{1, 2, 5, 10, 15, 20, 30, 50, 75, 100},
	})

	// CCR metrics
	ccrPutTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "headroom_ccr_put_total",
		Help: "Total CCR put operations",
	})

	ccrGetTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "headroom_ccr_get_total",
		Help: "Total CCR get operations",
	})

	ccrHitTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "headroom_ccr_hit_total",
		Help: "Total CCR cache hits by tier",
	}, []string{"tier"})

	ccrMissTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "headroom_ccr_miss_total",
		Help: "Total CCR cache misses by tier",
	}, []string{"tier"})

	ccrErrorTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "headroom_ccr_error_total",
		Help: "Total CCR errors",
	})

	// Compression time
	compressionDurationHistogram = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "headroom_compression_duration_seconds",
		Help:    "Headroom compression duration in seconds",
		Buckets: prometheus.ExponentialBuckets(0.001, 2, 10), // 1ms to 512ms
	})
)

// Metrics tracks Headroom compression statistics.
type Metrics struct {
	ArraysCompressed    int64
	ItemsBefore         int64
	ItemsAfter          int64
	LosslessCount       int64
	LossyCount          int64
	CCRPuts             int64
	CCRGets             int64
	CCRHits             int64
	CCRMisses           int64
	TotalCompressions   int64
	AverageK            float64
	AverageRatio        float64
}

// globalMetrics holds runtime metrics
var globalMetrics Metrics

// RecordArrayCompression records a successful array compression.
func RecordArrayCompression(itemsBefore, itemsAfter int, ratio float64, isLossless bool, strategy string) {
	arraysCompressedTotal.Inc()
	itemsBeforeCompression.Add(float64(itemsBefore))
	itemsAfterCompression.Add(float64(itemsAfter))
	compressionRatioHistogram.Observe(ratio)

	if isLossless {
		losslessPathTotal.WithLabelValues(strategy).Inc()
		atomic.AddInt64(&globalMetrics.LosslessCount, 1)
	} else {
		lossyPathTotal.Inc()
		atomic.AddInt64(&globalMetrics.LossyCount, 1)
	}

	atomic.AddInt64(&globalMetrics.ArraysCompressed, 1)
	atomic.AddInt64(&globalMetrics.ItemsBefore, int64(itemsBefore))
	atomic.AddInt64(&globalMetrics.ItemsAfter, int64(itemsAfter))
	atomic.AddInt64(&globalMetrics.TotalCompressions, 1)
}

// RecordAdaptiveK records an adaptive k-value selection.
func RecordAdaptiveK(k int) {
	adaptiveKDistribution.Observe(float64(k))
}

// RecordCCRPut records a CCR put operation.
func RecordCCRPut() {
	ccrPutTotal.Inc()
	atomic.AddInt64(&globalMetrics.CCRPuts, 1)
}

// RecordCCRGet records a CCR get operation.
func RecordCCRGet() {
	ccrGetTotal.Inc()
	atomic.AddInt64(&globalMetrics.CCRGets, 1)
}

// RecordCCRHit records a CCR cache hit.
func RecordCCRHit(tier string) {
	ccrHitTotal.WithLabelValues(tier).Inc()
	atomic.AddInt64(&globalMetrics.CCRHits, 1)
}

// RecordCCRMiss records a CCR cache miss.
func RecordCCRMiss(tier string) {
	ccrMissTotal.WithLabelValues(tier).Inc()
	atomic.AddInt64(&globalMetrics.CCRMisses, 1)
}

// RecordCCRError records a CCR error.
func RecordCCRError() {
	ccrErrorTotal.Inc()
}

// RecordCompressionDuration records compression duration.
func RecordCompressionDuration(seconds float64) {
	compressionDurationHistogram.Observe(seconds)
}

// GetMetrics returns a snapshot of current metrics.
func GetMetrics() Metrics {
	return Metrics{
		ArraysCompressed:  atomic.LoadInt64(&globalMetrics.ArraysCompressed),
		ItemsBefore:       atomic.LoadInt64(&globalMetrics.ItemsBefore),
		ItemsAfter:        atomic.LoadInt64(&globalMetrics.ItemsAfter),
		LosslessCount:     atomic.LoadInt64(&globalMetrics.LosslessCount),
		LossyCount:        atomic.LoadInt64(&globalMetrics.LossyCount),
		CCRPuts:           atomic.LoadInt64(&globalMetrics.CCRPuts),
		CCRGets:           atomic.LoadInt64(&globalMetrics.CCRGets),
		CCRHits:           atomic.LoadInt64(&globalMetrics.CCRHits),
		CCRMisses:         atomic.LoadInt64(&globalMetrics.CCRMisses),
		TotalCompressions: atomic.LoadInt64(&globalMetrics.TotalCompressions),
	}
}

// ResetMetrics resets all runtime metrics (for testing).
func ResetMetrics() {
	atomic.StoreInt64(&globalMetrics.ArraysCompressed, 0)
	atomic.StoreInt64(&globalMetrics.ItemsBefore, 0)
	atomic.StoreInt64(&globalMetrics.ItemsAfter, 0)
	atomic.StoreInt64(&globalMetrics.LosslessCount, 0)
	atomic.StoreInt64(&globalMetrics.LossyCount, 0)
	atomic.StoreInt64(&globalMetrics.CCRPuts, 0)
	atomic.StoreInt64(&globalMetrics.CCRGets, 0)
	atomic.StoreInt64(&globalMetrics.CCRHits, 0)
	atomic.StoreInt64(&globalMetrics.CCRMisses, 0)
	atomic.StoreInt64(&globalMetrics.TotalCompressions, 0)
}
