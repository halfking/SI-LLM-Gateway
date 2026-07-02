package headroom

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
)

// SmartCrusher is the top-level JSON array compressor.
// It implements lossless-first compression with adaptive sizing.
type SmartCrusher struct {
	config SmartCrusherConfig
}

// NewSmartCrusher creates a new SmartCrusher with the given config.
func NewSmartCrusher(config SmartCrusherConfig) *SmartCrusher {
	return &SmartCrusher{
		config: config,
	}
}

// NewSmartCrusherWithDefaults creates a SmartCrusher with default configuration.
func NewSmartCrusherWithDefaults() *SmartCrusher {
	return NewSmartCrusher(DefaultSmartCrusherConfig())
}

// CrushArray compresses a JSON array using lossless-first strategy.
//
// Algorithm:
// 1. Skip if array too small (< MinItemsToAnalyze)
// 2. Try lossless compression (table/bucket compaction)
// 3. If lossless savings < threshold, try lossy compression
// 4. Compute optimal k using adaptive sizer
// 5. Keep top k items, store rest in CCR
// 6. Return compressed result with CCR marker
func (sc *SmartCrusher) CrushArray(items []json.RawMessage, queryContext string) CrushArrayResult {
	n := len(items)
	
	// Skip if too small
	if n < sc.config.MinItemsToAnalyze {
		return CrushArrayResult{
			Items:        items,
			StrategyInfo: fmt.Sprintf("skip:too_small (n=%d)", n),
			DidCompress:  false,
		}
	}

	// Classify array type
	arrayType := classifyArray(items)
	
	// Try lossless compression first
	if losslessResult := sc.tryLosslessCompression(items, arrayType); losslessResult != nil {
		return *losslessResult
	}

	// Lossless didn't save enough - try lossy compression
	if sc.config.LosslessOnly {
		return CrushArrayResult{
			Items:        items,
			StrategyInfo: "skip:lossless_only",
			DidCompress:  false,
		}
	}

	return sc.crushLossy(items, arrayType, queryContext)
}

// tryLosslessCompression attempts lossless compression strategies.
func (sc *SmartCrusher) tryLosslessCompression(items []json.RawMessage, arrayType ArrayType) *CrushArrayResult {
	// For now, we'll implement basic table compression for object arrays
	if arrayType != ArrayTypeObjects {
		return nil // Only compress object arrays losslessly
	}

	// Try table compaction
	if compacted, ok := sc.tryTableCompaction(items); ok {
		originalSize := estimateSize(items)
		compactedSize := len(compacted)
		ratio := float64(compactedSize) / float64(originalSize)
		
		if ratio <= (1.0 - sc.config.LosslessMinSavingsRatio) {
			return &CrushArrayResult{
				Items:            items, // Keep original for now
				StrategyInfo:     "lossless:table",
				Compacted:        &compacted,
				CompactionKind:   strPtr("table"),
				DidCompress:      true,
				CompressionRatio: ratio,
			}
		}
	}

	return nil
}

// tryTableCompaction attempts to compact object array as CSV table.
func (sc *SmartCrusher) tryTableCompaction(items []json.RawMessage) (string, bool) {
	if len(items) == 0 {
		return "", false
	}

	// Parse first item to get schema
	var firstObj map[string]interface{}
	if err := json.Unmarshal(items[0], &firstObj); err != nil {
		return "", false
	}

	// Extract column names
	columns := make([]string, 0, len(firstObj))
	for key := range firstObj {
		columns = append(columns, key)
	}

	if len(columns) == 0 {
		return "", false
	}

	// Build CSV-like table
	var sb strings.Builder
	
	// Header
	sb.WriteString(strings.Join(columns, ","))
	sb.WriteString("\n")

	// Rows
	for _, item := range items {
		var obj map[string]interface{}
		if err := json.Unmarshal(item, &obj); err != nil {
			return "", false
		}

		values := make([]string, len(columns))
		for i, col := range columns {
			if val, ok := obj[col]; ok {
				values[i] = fmt.Sprintf("%v", val)
			} else {
				values[i] = ""
			}
		}
		sb.WriteString(strings.Join(values, ","))
		sb.WriteString("\n")
	}

	return sb.String(), true
}

// crushLossy performs lossy compression with CCR caching.
func (sc *SmartCrusher) crushLossy(items []json.RawMessage, arrayType ArrayType, queryContext string) CrushArrayResult {
	n := len(items)
	
	// Convert items to strings for analysis
	itemStrings := make([]string, n)
	for i, item := range items {
		itemStrings[i] = string(item)
	}

	// Compute optimal k
	k := ComputeOptimalK(itemStrings, sc.config.Bias, 1, sc.config.MaxItemsAfterCrush)
	
	// If k >= n, no compression needed
	if k >= n {
		return CrushArrayResult{
			Items:        items,
			StrategyInfo: fmt.Sprintf("none:adaptive_at_limit (k=%d)", k),
			DidCompress:  false,
		}
	}

	// Keep top k items
	keptItems := items[:k]
	droppedItems := items[k:]
	droppedCount := len(droppedItems)

	// Compute CCR hash of full original array
	var ccrHash *string
	var droppedSummary string
	
	if sc.config.EnableCCRMarker && droppedCount > 0 {
		hash := computeCCRHash(items)
		ccrHash = &hash
		droppedSummary = fmt.Sprintf("<<ccr:%s %d_rows_offloaded>>", hash, droppedCount)
	}

	originalSize := estimateSize(items)
	compressedSize := estimateSize(keptItems)
	ratio := float64(compressedSize) / float64(originalSize)

	return CrushArrayResult{
		Items:            keptItems,
		StrategyInfo:     "smart_sample",
		CCRHash:          ccrHash,
		DroppedSummary:   droppedSummary,
		DidCompress:      true,
		DroppedCount:     droppedCount,
		CompressionRatio: ratio,
	}
}

// classifyArray determines the type of JSON array.
func classifyArray(items []json.RawMessage) ArrayType {
	if len(items) == 0 {
		return ArrayTypeUnknown
	}

	// Check first item
	var first interface{}
	if err := json.Unmarshal(items[0], &first); err != nil {
		return ArrayTypeUnknown
	}

	switch first.(type) {
	case map[string]interface{}:
		return ArrayTypeObjects
	case string:
		return ArrayTypeStrings
	case float64, int, int64:
		return ArrayTypeNumbers
	default:
		return ArrayTypeMixed
	}
}

// computeCCRHash computes a 24-character BLAKE3-style hash.
// For now we use SHA-256 as BLAKE3 is not in stdlib.
func computeCCRHash(items []json.RawMessage) string {
	// Serialize items to canonical JSON
	data, _ := json.Marshal(items)
	
	// Compute SHA-256
	hash := sha256.Sum256(data)
	
	// Return first 24 hex chars (96 bits)
	return hex.EncodeToString(hash[:])[:24]
}

// estimateSize estimates the byte size of items.
func estimateSize(items []json.RawMessage) int {
	total := 0
	for _, item := range items {
		total += len(item)
	}
	return total
}

// strPtr returns a pointer to the given string.
func strPtr(s string) *string {
	return &s
}
