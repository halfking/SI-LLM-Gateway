// Package headroom implements the Headroom token compression algorithm.
// It provides intelligent compression for JSON arrays in LLM tool outputs,
// using lossless-first strategies and CCR (Compress-Cache-Retrieve) for
// zero information loss.
package headroom

import "encoding/json"

// CrushArrayResult is the result of crushing a JSON array.
type CrushArrayResult struct {
	// Items are the kept items after compression.
	// For lossless path: full original (nothing dropped).
	// For lossy path: surviving subset; rest is retrievable via CCRHash.
	Items []json.RawMessage

	// StrategyInfo is the strategy debug string.
	// Examples: "lossless:table", "smart_sample", "skip:too_small"
	StrategyInfo string

	// CCRHash is the 24-char BLAKE3 hash of the full original input.
	// Populated when lossy path dropped rows; nil when nothing dropped.
	CCRHash *string

	// DroppedSummary is the marker text for CCR pointer.
	// Format: "<<ccr:abc123def456789012345678 42_rows_offloaded>>"
	DroppedSummary string

	// Compacted is the rendered bytes from lossless compaction.
	// Populated only when lossless path won.
	Compacted *string

	// CompactionKind is the compaction variant: "table", "buckets", "ccr".
	CompactionKind *string

	// DidCompress indicates whether any compression was applied.
	DidCompress bool

	// DroppedCount is the number of items dropped (lossy path only).
	DroppedCount int

	// CompressionRatio is the size ratio: output_size / input_size.
	CompressionRatio float64
}

// SmartCrusherConfig configures the SmartCrusher behavior.
type SmartCrusherConfig struct {
	// MaxItemsAfterCrush is the maximum number of items to keep (default: 15).
	MaxItemsAfterCrush int

	// MinItemsToAnalyze is the minimum array size to consider (default: 5).
	MinItemsToAnalyze int

	// LosslessMinSavingsRatio is the minimum compression ratio for lossless
	// strategies to be accepted (default: 0.30 = 30% savings).
	LosslessMinSavingsRatio float64

	// FactorOutConstants enables extracting constant fields (default: true).
	FactorOutConstants bool

	// EnableCCRMarker enables CCR marker injection (default: true).
	EnableCCRMarker bool

	// LosslessOnly skips lossy compression (default: false).
	LosslessOnly bool

	// Bias is the k multiplier for adaptive sizing (default: 1.0).
	// >1.0 keeps more items, <1.0 compresses more aggressively.
	Bias float64
}

// DefaultSmartCrusherConfig returns the default configuration.
func DefaultSmartCrusherConfig() SmartCrusherConfig {
	return SmartCrusherConfig{
		MaxItemsAfterCrush:      15,
		MinItemsToAnalyze:       5,
		LosslessMinSavingsRatio: 0.30,
		FactorOutConstants:      true,
		EnableCCRMarker:         true,
		LosslessOnly:            false,
		Bias:                    1.0,
	}
}

// ArrayType classifies the type of JSON array.
type ArrayType int

const (
	ArrayTypeUnknown ArrayType = iota
	ArrayTypeObjects           // Array of JSON objects
	ArrayTypeStrings           // Array of strings
	ArrayTypeNumbers           // Array of numbers
	ArrayTypeMixed             // Mixed types
)

func (t ArrayType) String() string {
	switch t {
	case ArrayTypeObjects:
		return "objects"
	case ArrayTypeStrings:
		return "strings"
	case ArrayTypeNumbers:
		return "numbers"
	case ArrayTypeMixed:
		return "mixed"
	default:
		return "unknown"
	}
}
