package headroom

import (
	"crypto/md5"
	"encoding/binary"
	"strings"
)

// SimHash computes a 64-bit SimHash fingerprint for the given text.
// Uses MD5 hashing of 4-grams with bit voting aggregation.
//
// Algorithm:
// 1. Extract character 4-grams from text
// 2. Hash each 4-gram with MD5
// 3. Aggregate into 64-bit fingerprint via bit voting
// 4. Return fingerprint
func SimHash(text string) uint64 {
	if text == "" {
		return 0
	}

	// Accumulator for bit voting: +1 for each '1' bit, -1 for each '0' bit
	var bitCounts [64]int32

	// Extract 4-grams and hash
	grams := extract4Grams(text)
	for _, gram := range grams {
		hash := md5Hash4Gram(gram)
		
		// Vote on each bit position
		for i := 0; i < 64; i++ {
			if hash&(1<<uint(i)) != 0 {
				bitCounts[i]++
			} else {
				bitCounts[i]--
			}
		}
	}

	// Build final fingerprint from majority votes
	var fingerprint uint64
	for i := 0; i < 64; i++ {
		if bitCounts[i] > 0 {
			fingerprint |= 1 << uint(i)
		}
	}

	return fingerprint
}

// extract4Grams extracts all character 4-grams from text.
func extract4Grams(text string) []string {
	runes := []rune(text)
	if len(runes) < 4 {
		return []string{text}
	}

	grams := make([]string, 0, len(runes)-3)
	for i := 0; i <= len(runes)-4; i++ {
		gram := string(runes[i : i+4])
		grams = append(grams, gram)
	}
	return grams
}

// md5Hash4Gram computes a 64-bit hash from the MD5 of a 4-gram.
func md5Hash4Gram(gram string) uint64 {
	hash := md5.Sum([]byte(gram))
	// Use first 8 bytes of MD5 as uint64
	return binary.LittleEndian.Uint64(hash[:8])
}

// HammingDistance computes the Hamming distance between two SimHash fingerprints.
// Returns the number of differing bits.
func HammingDistance(a, b uint64) int {
	xor := a ^ b
	return popCount(xor)
}

// popCount counts the number of set bits (population count).
func popCount(x uint64) int {
	// Brian Kernighan's algorithm
	count := 0
	for x != 0 {
		x &= x - 1
		count++
	}
	return count
}

// CountUniqueSimHashes counts unique SimHash fingerprints with the given threshold.
// Two fingerprints are considered duplicates if their Hamming distance <= threshold.
func CountUniqueSimHashes(items []string, threshold int) int {
	if len(items) == 0 {
		return 0
	}

	// Compute fingerprints
	fingerprints := make([]uint64, len(items))
	for i, item := range items {
		fingerprints[i] = SimHash(item)
	}

	// Count unique fingerprints using greedy clustering
	seen := make([]uint64, 0, len(fingerprints))
	unique := 0

	for _, fp := range fingerprints {
		isUnique := true
		for _, seenFp := range seen {
			if HammingDistance(fp, seenFp) <= threshold {
				isUnique = false
				break
			}
		}
		if isUnique {
			seen = append(seen, fp)
			unique++
		}
	}

	return unique
}

// NormalizeText normalizes text for SimHash comparison.
// Converts to lowercase and collapses whitespace.
func NormalizeText(text string) string {
	// Lowercase
	text = strings.ToLower(text)
	
	// Collapse multiple whitespace
	fields := strings.Fields(text)
	return strings.Join(fields, " ")
}
