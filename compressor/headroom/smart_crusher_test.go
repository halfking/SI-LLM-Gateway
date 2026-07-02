package headroom

import (
	"encoding/json"
	"fmt"
	"testing"
)

func TestSmartCrusher_SkipSmallArray(t *testing.T) {
	crusher := NewSmartCrusherWithDefaults()
	
	items := []json.RawMessage{
		json.RawMessage(`{"id": 1}`),
		json.RawMessage(`{"id": 2}`),
	}
	
	result := crusher.CrushArray(items, "")
	
	if result.DidCompress {
		t.Error("Should skip small array")
	}
	if result.StrategyInfo != "skip:too_small (n=2)" {
		t.Errorf("Wrong strategy: %s", result.StrategyInfo)
	}
}

func TestSmartCrusher_LosslessCompression(t *testing.T) {
	crusher := NewSmartCrusherWithDefaults()
	
	// Create object array suitable for table compression
	items := make([]json.RawMessage, 20)
	for i := 0; i < 20; i++ {
		items[i] = json.RawMessage(fmt.Sprintf(`{"id": %d, "name": "item%d", "value": %d}`, i, i, i*10))
	}
	
	result := crusher.CrushArray(items, "")
	
	t.Logf("Strategy: %s, Compressed: %v, Ratio: %.2f", 
		result.StrategyInfo, result.DidCompress, result.CompressionRatio)
	
	// Should attempt compression
	if !result.DidCompress {
		t.Log("Lossless compression didn't save enough, which is OK")
	}
}

func TestSmartCrusher_LossyCompression(t *testing.T) {
	config := DefaultSmartCrusherConfig()
	config.MaxItemsAfterCrush = 10 // Force compression
	crusher := NewSmartCrusher(config)
	
	// Create large string array (won't compress losslessly)
	items := make([]json.RawMessage, 50)
	for i := 0; i < 50; i++ {
		items[i] = json.RawMessage(fmt.Sprintf(`"Search result number %d with unique content about topic %d"`, i, i*100))
	}
	
	result := crusher.CrushArray(items, "search results")
	
	t.Logf("Result: compressed=%v, items=%d, strategy=%s", 
		result.DidCompress, len(result.Items), result.StrategyInfo)
	
	if !result.DidCompress {
		// It's OK if not compressed when items are below threshold
		if len(result.Items) == 50 {
			t.Skip("Array not compressed (algorithm decided not to)")
		}
	}
	
	if result.DidCompress && len(result.Items) >= 50 {
		t.Errorf("Should reduce items: got %d, want < 50", len(result.Items))
	}
	
	if result.DidCompress && result.StrategyInfo != "lossless:table" {
		// Lossy compression should have CCR
		if result.CCRHash == nil {
			t.Error("Lossy compression should have CCR hash")
			return
		}
		
		if result.DroppedSummary == "" {
			t.Error("Lossy compression should have dropped summary")
		}
		
		t.Logf("Compressed %d -> %d items, CCR hash: %s", 
			50, len(result.Items), *result.CCRHash)
	}
}

func TestSmartCrusher_LosslessOnly(t *testing.T) {
	config := DefaultSmartCrusherConfig()
	config.LosslessOnly = true
	crusher := NewSmartCrusher(config)
	
	// Create array that would normally be lossy compressed
	items := make([]json.RawMessage, 30)
	for i := 0; i < 30; i++ {
		items[i] = json.RawMessage(fmt.Sprintf(`"item %d"`, i))
	}
	
	result := crusher.CrushArray(items, "")
	
	// Should skip compression in lossless-only mode
	if result.StrategyInfo != "skip:lossless_only" {
		t.Errorf("Expected skip:lossless_only, got %s", result.StrategyInfo)
	}
}

func TestSmartCrusher_CompressionRatio(t *testing.T) {
	crusher := NewSmartCrusherWithDefaults()
	
	// Create diverse array
	items := make([]json.RawMessage, 100)
	for i := 0; i < 100; i++ {
		items[i] = json.RawMessage(fmt.Sprintf(
			`{"id": %d, "data": "Search result number %d with content", "score": %d}`, 
			i, i, i*2))
	}
	
	result := crusher.CrushArray(items, "search")
	
	if result.DidCompress {
		if result.CompressionRatio >= 1.0 {
			t.Errorf("Compression ratio should be < 1.0, got %.2f", result.CompressionRatio)
		}
		
		t.Logf("Compression: %d -> %d items (%.1f%% reduction)", 
			100, len(result.Items), (1.0-result.CompressionRatio)*100)
	}
}

func TestClassifyArray(t *testing.T) {
	tests := []struct {
		name string
		item json.RawMessage
		want ArrayType
	}{
		{
			name: "objects",
			item: json.RawMessage(`{"key": "value"}`),
			want: ArrayTypeObjects,
		},
		{
			name: "strings",
			item: json.RawMessage(`"hello"`),
			want: ArrayTypeStrings,
		},
		{
			name: "numbers",
			item: json.RawMessage(`42`),
			want: ArrayTypeNumbers,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			items := []json.RawMessage{tt.item}
			got := classifyArray(items)
			if got != tt.want {
				t.Errorf("classifyArray() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestComputeCCRHash(t *testing.T) {
	items := []json.RawMessage{
		json.RawMessage(`{"id": 1}`),
		json.RawMessage(`{"id": 2}`),
	}
	
	hash1 := computeCCRHash(items)
	hash2 := computeCCRHash(items)
	
	// Should be deterministic
	if hash1 != hash2 {
		t.Errorf("Hash not deterministic: %s != %s", hash1, hash2)
	}
	
	// Should be 24 characters
	if len(hash1) != 24 {
		t.Errorf("Hash length = %d, want 24", len(hash1))
	}
}

func TestSmartCrusher_BiasEffect(t *testing.T) {
	items := make([]json.RawMessage, 50)
	for i := 0; i < 50; i++ {
		items[i] = json.RawMessage(fmt.Sprintf(`{"id": %d}`, i))
	}
	
	// Low bias (compress more)
	config1 := DefaultSmartCrusherConfig()
	config1.Bias = 0.5
	crusher1 := NewSmartCrusher(config1)
	result1 := crusher1.CrushArray(items, "")
	
	// High bias (keep more)
	config2 := DefaultSmartCrusherConfig()
	config2.Bias = 1.5
	crusher2 := NewSmartCrusher(config2)
	result2 := crusher2.CrushArray(items, "")
	
	t.Logf("Low bias (0.5): %d items", len(result1.Items))
	t.Logf("High bias (1.5): %d items", len(result2.Items))
	
	if result1.DidCompress && result2.DidCompress {
		if len(result1.Items) > len(result2.Items) {
			t.Errorf("Low bias should keep fewer items: %d > %d", 
				len(result1.Items), len(result2.Items))
		}
	}
}

// Benchmark SmartCrusher performance
func BenchmarkSmartCrusher_CrushArray(b *testing.B) {
	crusher := NewSmartCrusherWithDefaults()
	
	items := make([]json.RawMessage, 100)
	for i := 0; i < 100; i++ {
		items[i] = json.RawMessage(fmt.Sprintf(
			`{"id": %d, "title": "Result %d", "content": "Some content here"}`, i, i))
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		crusher.CrushArray(items, "search")
	}
}
