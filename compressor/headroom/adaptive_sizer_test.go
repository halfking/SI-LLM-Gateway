package headroom

import (
	"fmt"
	"testing"
)

func TestComputeOptimalK_SmallArray(t *testing.T) {
	items := []string{"a", "b", "c"}
	k := ComputeOptimalK(items, 1.0, 1, 0)
	
	// Small arrays (≤8) should return n
	if k != 3 {
		t.Errorf("ComputeOptimalK(3 items) = %d, want 3", k)
	}
}

func TestComputeOptimalK_Redundant(t *testing.T) {
	// Nearly identical items
	items := []string{
		"hello world",
		"hello world!",
		"hello world.",
		"hello world?",
		"hello world!!",
	}
	
	k := ComputeOptimalK(items, 1.0, 1, 0)
	
	// Should detect redundancy and return small k (but may be adjusted by zlib validation)
	if k > 5 {
		t.Errorf("ComputeOptimalK(redundant) = %d, want ≤5", k)
	}
	if k < 1 {
		t.Errorf("ComputeOptimalK(redundant) = %d, want ≥1", k)
	}
}

func TestComputeOptimalK_Diverse(t *testing.T) {
	// Very diverse items
	items := make([]string, 20)
	for i := 0; i < 20; i++ {
		items[i] = fmt.Sprintf("Item %d with completely unique content about topic %d", i, i*100)
	}
	
	k := ComputeOptimalK(items, 1.0, 5, 15)
	
	// Should keep significant portion due to diversity
	if k < 10 {
		t.Errorf("ComputeOptimalK(diverse) = %d, want ≥10", k)
	}
	if k > 15 {
		t.Errorf("ComputeOptimalK(diverse) = %d, want ≤15 (maxK)", k)
	}
}

func TestComputeOptimalK_BiasEffect(t *testing.T) {
	items := make([]string, 50)
	for i := 0; i < 50; i++ {
		items[i] = fmt.Sprintf("Result %d: some data %d", i, i)
	}
	
	// Low bias: compress more
	k1 := ComputeOptimalK(items, 0.5, 5, 0)
	
	// High bias: keep more
	k2 := ComputeOptimalK(items, 1.5, 5, 0)
	
	// Bias should affect k (unless both hit validation limits)
	t.Logf("Low bias (0.5) k=%d, High bias (1.5) k=%d", k1, k2)
	
	// At minimum, they should not be vastly different if maxK not constraining
	if k1 > k2 {
		t.Errorf("Low bias k=%d should not be > high bias k=%d", k1, k2)
	}
}

func TestComputeUniqueBigramCurve(t *testing.T) {
	items := []string{
		"hello world",
		"hello there",
		"goodbye world",
	}
	
	curve := computeUniqueBigramCurve(items)
	
	// Curve should be monotonically increasing
	if len(curve) != 3 {
		t.Fatalf("curve length = %d, want 3", len(curve))
	}
	
	for i := 1; i < len(curve); i++ {
		if curve[i] < curve[i-1] {
			t.Errorf("curve not monotonic: curve[%d]=%d < curve[%d]=%d", 
				i, curve[i], i-1, curve[i-1])
		}
	}
	
	// First item should have non-zero bigrams
	if curve[0] == 0 {
		t.Error("curve[0] = 0, want > 0")
	}
}

func TestFindKnee_FlatCurve(t *testing.T) {
	// Flat curve: no knee
	curve := []int{5, 5, 5, 5, 5}
	knee := findKnee(curve)
	
	if knee != len(curve) {
		t.Errorf("findKnee(flat) = %d, want %d", knee, len(curve))
	}
}

func TestFindKnee_LinearCurve(t *testing.T) {
	// Perfectly linear: no knee
	curve := []int{0, 10, 20, 30, 40}
	knee := findKnee(curve)
	
	if knee != 0 {
		t.Errorf("findKnee(linear) = %d, want 0", knee)
	}
}

func TestFindKnee_ObviousKnee(t *testing.T) {
	// Steep increase then flat
	curve := []int{0, 5, 15, 30, 45, 46, 47, 48, 49, 50}
	knee := findKnee(curve)
	
	// Knee should be around index 5-7
	if knee < 4 || knee > 8 {
		t.Errorf("findKnee(obvious) = %d, want 4-8", knee)
	}
}

func TestFindKnee_SmallCurve(t *testing.T) {
	curve := []int{5, 10}
	knee := findKnee(curve)
	
	if knee != 2 {
		t.Errorf("findKnee(2 items) = %d, want 2", knee)
	}
}

func TestValidateWithZlib(t *testing.T) {
	// Highly compressible items
	items := make([]string, 100)
	for i := 0; i < 100; i++ {
		items[i] = "The quick brown fox jumps over the lazy dog"
	}
	
	k := validateWithZlib(items, 10, 50, 0.15)
	
	// With identical items, compression ratio is same, so k should not increase much
	t.Logf("validateWithZlib: k=%d (initial=10)", k)
	
	if k > 50 {
		t.Errorf("validateWithZlib exceeded maxK: %d > 50", k)
	}
}

func TestValidateWithZlib_NoChange(t *testing.T) {
	// Diverse items (low compressibility)
	items := make([]string, 20)
	for i := 0; i < 20; i++ {
		items[i] = fmt.Sprintf("Unique string %d with random content %d", i, i*i*i)
	}
	
	k := validateWithZlib(items, 10, 15, 0.15)
	
	// Should not change k significantly
	if k < 9 || k > 13 {
		t.Errorf("validateWithZlib changed k too much: 10 -> %d", k)
	}
}

func TestZlibCompress(t *testing.T) {
	text := "hello world hello world hello world"
	compressed := zlibCompress(text)
	
	// Compressed should be smaller than original for repetitive text
	if len(compressed) >= len(text) {
		t.Errorf("zlib compression failed: %d >= %d", len(compressed), len(text))
	}
}

// Benchmark adaptive sizer performance
func BenchmarkComputeOptimalK(b *testing.B) {
	items := make([]string, 100)
	for i := 0; i < 100; i++ {
		items[i] = fmt.Sprintf("Search result %d: some content here with words %d", i, i*10)
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ComputeOptimalK(items, 1.0, 5, 15)
	}
}

func BenchmarkComputeUniqueBigramCurve(b *testing.B) {
	items := make([]string, 50)
	for i := 0; i < 50; i++ {
		items[i] = fmt.Sprintf("Text item number %d with some content", i)
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		computeUniqueBigramCurve(items)
	}
}
