package headroom

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRecordArrayCompression(t *testing.T) {
	ResetMetrics()

	RecordArrayCompression(100, 20, 0.2, false, "smart_sample")

	metrics := GetMetrics()
	assert.Equal(t, int64(1), metrics.ArraysCompressed)
	assert.Equal(t, int64(100), metrics.ItemsBefore)
	assert.Equal(t, int64(20), metrics.ItemsAfter)
	assert.Equal(t, int64(0), metrics.LosslessCount)
	assert.Equal(t, int64(1), metrics.LossyCount)
}

func TestRecordArrayCompression_Lossless(t *testing.T) {
	ResetMetrics()

	RecordArrayCompression(50, 50, 1.0, true, "table")

	metrics := GetMetrics()
	assert.Equal(t, int64(1), metrics.ArraysCompressed)
	assert.Equal(t, int64(50), metrics.ItemsBefore)
	assert.Equal(t, int64(50), metrics.ItemsAfter)
	assert.Equal(t, int64(1), metrics.LosslessCount)
	assert.Equal(t, int64(0), metrics.LossyCount)
}

func TestRecordAdaptiveK(t *testing.T) {
	// Should not panic
	RecordAdaptiveK(10)
	RecordAdaptiveK(50)
	RecordAdaptiveK(100)
}

func TestRecordCCROperations(t *testing.T) {
	ResetMetrics()

	RecordCCRPut()
	RecordCCRPut()
	RecordCCRGet()
	RecordCCRHit("l1")
	RecordCCRMiss("l2")
	RecordCCRError()

	metrics := GetMetrics()
	assert.Equal(t, int64(2), metrics.CCRPuts)
	assert.Equal(t, int64(1), metrics.CCRGets)
	assert.Equal(t, int64(1), metrics.CCRHits)
	assert.Equal(t, int64(1), metrics.CCRMisses)
}

func TestRecordCompressionDuration(t *testing.T) {
	// Should not panic
	RecordCompressionDuration(0.001)
	RecordCompressionDuration(0.05)
	RecordCompressionDuration(0.1)
}

func TestGetMetrics(t *testing.T) {
	ResetMetrics()

	// Record some operations
	RecordArrayCompression(100, 20, 0.2, false, "smart")
	RecordArrayCompression(50, 10, 0.2, true, "table")
	RecordCCRPut()
	RecordCCRGet()

	metrics := GetMetrics()
	assert.Equal(t, int64(2), metrics.TotalCompressions)
	assert.Equal(t, int64(2), metrics.ArraysCompressed)
	assert.Equal(t, int64(150), metrics.ItemsBefore)
	assert.Equal(t, int64(30), metrics.ItemsAfter)
	assert.Equal(t, int64(1), metrics.LosslessCount)
	assert.Equal(t, int64(1), metrics.LossyCount)
	assert.Equal(t, int64(1), metrics.CCRPuts)
	assert.Equal(t, int64(1), metrics.CCRGets)
}

func TestResetMetrics(t *testing.T) {
	// Record some data
	RecordArrayCompression(100, 20, 0.2, false, "smart")
	RecordCCRPut()

	// Reset
	ResetMetrics()

	// Should be zero
	metrics := GetMetrics()
	assert.Equal(t, int64(0), metrics.ArraysCompressed)
	assert.Equal(t, int64(0), metrics.ItemsBefore)
	assert.Equal(t, int64(0), metrics.ItemsAfter)
	assert.Equal(t, int64(0), metrics.LosslessCount)
	assert.Equal(t, int64(0), metrics.LossyCount)
	assert.Equal(t, int64(0), metrics.CCRPuts)
	assert.Equal(t, int64(0), metrics.CCRGets)
	assert.Equal(t, int64(0), metrics.TotalCompressions)
}

func TestMetrics_Concurrent(t *testing.T) {
	ResetMetrics()

	// Simulate concurrent operations
	done := make(chan bool, 10)
	for i := 0; i < 10; i++ {
		go func() {
			RecordArrayCompression(10, 5, 0.5, false, "smart")
			RecordCCRPut()
			RecordCCRGet()
			done <- true
		}()
	}

	// Wait for all
	for i := 0; i < 10; i++ {
		<-done
	}

	metrics := GetMetrics()
	assert.Equal(t, int64(10), metrics.ArraysCompressed)
	assert.Equal(t, int64(100), metrics.ItemsBefore)
	assert.Equal(t, int64(50), metrics.ItemsAfter)
	assert.Equal(t, int64(10), metrics.CCRPuts)
	assert.Equal(t, int64(10), metrics.CCRGets)
}
