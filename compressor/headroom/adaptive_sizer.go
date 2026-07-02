package headroom

import (
	"bytes"
	"compress/zlib"
	"math"
	"strings"
)

// ComputeOptimalK calculates the optimal number of items to keep using
// the Kneedle algorithm on the unique bigram coverage curve.
//
// Algorithm:
// 1. Fast path: ≤8 items return n
// 2. Near-complete redundancy check via SimHash (unique ≤3)
// 3. Kneedle algorithm: find inflection point in bigram curve
// 4. Diversity ratio adjustment
// 5. Apply bias multiplier
// 6. zlib validation: ensure subset compression matches full set
func ComputeOptimalK(items []string, bias float64, minK, maxK int) int {
	n := len(items)
	
	// Fast path: small arrays
	if n <= 8 {
		return n
	}

	// Near-complete redundancy detection
	uniqueCount := CountUniqueSimHashes(items, 3)
	if uniqueCount <= 3 {
		return max(minK, uniqueCount)
	}

	// Compute unique bigram coverage curve
	curve := computeUniqueBigramCurve(items)
	
	// Find knee using Kneedle algorithm
	knee := findKnee(curve)
	if knee == 0 {
		knee = n // No clear knee, keep all
	}

	// Diversity ratio adjustment
	diversityRatio := float64(uniqueCount) / float64(n)
	if diversityRatio > 0.8 {
		// High diversity: raise floor
		knee = max(knee, int(float64(n)*0.5))
	}

	// Apply bias multiplier
	k := int(float64(knee) * bias)
	k = max(minK, min(k, n))

	// Apply maxK constraint
	if maxK > 0 && k > maxK {
		k = maxK
	}

	// zlib validation
	k = validateWithZlib(items, k, maxK, 0.15)

	return k
}

// computeUniqueBigramCurve computes the cumulative unique word-level bigram
// count after seeing each item.
func computeUniqueBigramCurve(items []string) []int {
	curve := make([]int, len(items))
	seenBigrams := make(map[string]bool)

	for i, item := range items {
		// Extract word-level bigrams
		words := strings.Fields(NormalizeText(item))
		
		// Add single-word synthetic bigrams
		for _, word := range words {
			seenBigrams[word+"_"] = true
		}
		
		// Add word pairs
		for j := 0; j < len(words)-1; j++ {
			bigram := words[j] + "_" + words[j+1]
			seenBigrams[bigram] = true
		}
		
		curve[i] = len(seenBigrams)
	}

	return curve
}

// findKnee finds the "knee" or inflection point in a monotonic curve
// using the Kneedle algorithm.
//
// Returns the index where the curve starts to flatten, or 0 if no knee found.
func findKnee(curve []int) int {
	n := len(curve)
	if n <= 2 {
		return n
	}

	// Normalize curve to [0, 1] range
	minVal := curve[0]
	maxVal := curve[n-1]
	if maxVal == minVal {
		return n // Flat curve, no knee
	}

	normalized := make([]float64, n)
	for i, val := range curve {
		normalized[i] = float64(val-minVal) / float64(maxVal-minVal)
	}

	// Compute x coordinates (normalized indices)
	xNorm := make([]float64, n)
	for i := range xNorm {
		xNorm[i] = float64(i) / float64(n-1)
	}

	// Find maximum distance from diagonal line
	maxDiff := 0.0
	kneeIdx := 0
	
	for i := 1; i < n-1; i++ {
		// Distance from diagonal: y - x
		diff := normalized[i] - xNorm[i]
		if diff > maxDiff {
			maxDiff = diff
			kneeIdx = i
		}
	}

	// Knee is significant if difference ≥ 0.05
	if maxDiff >= 0.05 {
		return kneeIdx + 1 // +1 to include the knee item
	}

	return 0 // No significant knee
}

// validateWithZlib checks if the subset compression ratio matches the full set.
// If the difference is >threshold, increase k by 20%.
func validateWithZlib(items []string, k, maxK int, threshold float64) int {
	n := len(items)
	if k >= n {
		return k
	}

	// Apply maxK constraint before validation
	if maxK > 0 && k > maxK {
		k = maxK
	}

	// Compress full set
	fullText := strings.Join(items, "\n")
	fullCompressed := zlibCompress(fullText)
	fullRatio := float64(len(fullCompressed)) / float64(len(fullText))

	// Compress subset
	subset := items[:k]
	subsetText := strings.Join(subset, "\n")
	subsetCompressed := zlibCompress(subsetText)
	subsetRatio := float64(len(subsetCompressed)) / float64(len(subsetText))

	// Check if subset loses too much information
	ratioDiff := math.Abs(subsetRatio - fullRatio)
	if ratioDiff > threshold {
		// Increase k by 20%
		newK := int(float64(k) * 1.2)
		newK = min(newK, n)
		if maxK > 0 {
			newK = min(newK, maxK)
		}
		return newK
	}

	return k
}

// zlibCompress compresses text using zlib.
func zlibCompress(text string) []byte {
	var buf bytes.Buffer
	w := zlib.NewWriter(&buf)
	w.Write([]byte(text))
	w.Close()
	return buf.Bytes()
}

// Helper functions
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
