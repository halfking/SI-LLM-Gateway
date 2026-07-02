package compressor

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHeadroomCompressor_CompressMessageArrays(t *testing.T) {
	hc := NewHeadroomCompressor(nil) // No CCR manager for now

	// Create test body with a tool result containing a JSON array
	body := []byte(`{
		"model": "claude-3-sonnet",
		"messages": [
			{
				"role": "user",
				"content": "Search for information"
			},
			{
				"role": "assistant",
				"content": "I'll search for that."
			}
		]
	}`)

	ctx := context.Background()
	compressed, result, err := hc.CompressMessageArrays(ctx, body, "test_session", "openai")

	// Should not compress (no arrays found), but may return original body
	require.NoError(t, err)
	if compressed == nil {
		assert.Nil(t, result)
	}
}

func TestHeadroomCompressor_FindArraysInAnthropicFormat(t *testing.T) {
	// Test with Anthropic tool_result format
	messages := []json.RawMessage{
		json.RawMessage(`{
			"role": "user",
			"content": [
				{
					"type": "tool_result",
					"tool_use_id": "toolu_123",
					"content": "[\"item1\", \"item2\", \"item3\", \"item4\", \"item5\", \"item6\"]"
				}
			]
		}`),
	}

	arrays := findJSONArraysInMessages(messages)
	assert.Len(t, arrays, 1)
	assert.Equal(t, 0, arrays[0].MessageIndex)
	assert.Len(t, arrays[0].Items, 6)
}

func TestHeadroomCompressor_SkipSmallArrays(t *testing.T) {
	// Arrays with < 5 items should not be found
	messages := []json.RawMessage{
		json.RawMessage(`{
			"role": "user",
			"content": [
				{
					"type": "tool_result",
					"content": "[\"item1\", \"item2\", \"item3\"]"
				}
			]
		}`),
	}

	arrays := findJSONArraysInMessages(messages)
	assert.Len(t, arrays, 0, "Small arrays (<5 items) should be skipped")
}

func TestHeadroomMode_String(t *testing.T) {
	tests := []struct {
		mode Mode
		want string
	}{
		{ModeHeadroom, "headroom"},
		{ModeHeadroomAggressive, "headroom_aggressive"},
	}

	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			got := tt.mode.String()
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestExtractMessagesForHeadroom(t *testing.T) {
	body := []byte(`{
		"model": "test",
		"messages": [
			{"role": "user", "content": "hello"},
			{"role": "assistant", "content": "hi"}
		]
	}`)

	messages, err := extractMessagesForHeadroom(body)
	require.NoError(t, err)
	assert.Len(t, messages, 2)
}

func TestExtractMessagesForHeadroom_InvalidJSON(t *testing.T) {
	body := []byte(`invalid json`)

	messages, err := extractMessagesForHeadroom(body)
	assert.Error(t, err)
	assert.Nil(t, messages)
}

func TestFindJSONArraysInMessages_NoArrays(t *testing.T) {
	messages := []json.RawMessage{
		json.RawMessage(`{"role": "user", "content": "just text"}`),
	}

	arrays := findJSONArraysInMessages(messages)
	assert.Len(t, arrays, 0)
}

func TestFindJSONArraysInMessages_MultipleArrays(t *testing.T) {
	messages := []json.RawMessage{
		json.RawMessage(`{
			"role": "user",
			"content": [
				{
					"type": "tool_result",
					"content": "[1, 2, 3, 4, 5, 6]"
				},
				{
					"type": "tool_result",
					"content": "[\"a\", \"b\", \"c\", \"d\", \"e\"]"
				}
			]
		}`),
	}

	arrays := findJSONArraysInMessages(messages)
	assert.Len(t, arrays, 2)
}

func TestRebuildBodyWithCompressedArrays_NoChanges(t *testing.T) {
	body := []byte(`{"messages": [{"role": "user", "content": "test"}]}`)
	arrays := []*ArrayInfo{} // No arrays

	rebuilt, err := rebuildBodyWithCompressedArrays(body, arrays)
	require.NoError(t, err)
	
	// Should return valid JSON
	var result map[string]interface{}
	err = json.Unmarshal(rebuilt, &result)
	require.NoError(t, err)
}

func TestRebuildBodyWithCompressedArrays_WithCCRMarker(t *testing.T) {
	body := []byte(`{
		"messages": [
			{"role": "user", "content": "original"}
		]
	}`)

	arrays := []*ArrayInfo{
		{
			MessageIndex:     0,
			ReplacementItems: []json.RawMessage{json.RawMessage(`"compressed"`)},
			CCRMarker:        "<<ccr:abc123 5_rows_offloaded>>",
		},
	}

	rebuilt, err := rebuildBodyWithCompressedArrays(body, arrays)
	require.NoError(t, err)

	// Should contain CCR marker
	assert.Contains(t, string(rebuilt), "ccr:abc123")
}

// Benchmark Headroom compression
func BenchmarkHeadroomCompressor_FindArrays(b *testing.B) {
	messages := []json.RawMessage{
		json.RawMessage(`{
			"role": "user",
			"content": [
				{
					"type": "tool_result",
					"content": "[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]"
				}
			]
		}`),
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		findJSONArraysInMessages(messages)
	}
}
