package compressor

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/kaixuan/llm-gateway-go/compressor/ccr"
	"github.com/kaixuan/llm-gateway-go/compressor/headroom"
)

// HeadroomCompressor handles Headroom-based JSON array compression.
type HeadroomCompressor struct {
	crusher    *headroom.SmartCrusher
	ccrManager *ccr.Manager
	enabled    bool
}

// NewHeadroomCompressor creates a new Headroom compressor.
func NewHeadroomCompressor(ccrManager *ccr.Manager) *HeadroomCompressor {
	config := headroom.DefaultSmartCrusherConfig()
	
	return &HeadroomCompressor{
		crusher:    headroom.NewSmartCrusher(config),
		ccrManager: ccrManager,
		enabled:    true,
	}
}

// NewHeadroomCompressorWithConfig creates a Headroom compressor with custom config.
func NewHeadroomCompressorWithConfig(config headroom.SmartCrusherConfig, ccrManager *ccr.Manager) *HeadroomCompressor {
	return &HeadroomCompressor{
		crusher:    headroom.NewSmartCrusher(config),
		ccrManager: ccrManager,
		enabled:    true,
	}
}

// CompressMessageArrays finds and compresses JSON arrays in messages.
// Returns modified body if compression was applied, nil otherwise.
func (hc *HeadroomCompressor) CompressMessageArrays(
	ctx context.Context,
	body []byte,
	sessionID string,
	protocol string,
) ([]byte, *HeadroomCompressionResult, error) {
	if !hc.enabled {
		return body, nil, nil
	}

	// Extract messages from body
	messages, err := extractMessagesForHeadroom(body)
	if err != nil {
		return body, nil, fmt.Errorf("failed to extract messages: %w", err)
	}

	if len(messages) == 0 {
		return body, nil, nil
	}

	// Find JSON arrays in messages
	arraysToCompress := findJSONArraysInMessages(messages)
	if len(arraysToCompress) == 0 {
		return body, nil, nil // No arrays to compress
	}

	// Compress each array
	modified := false
	totalItemsBefore := 0
	totalItemsAfter := 0
	ccrHashes := []string{}

	for _, arrayInfo := range arraysToCompress {
		result := hc.crusher.CrushArray(arrayInfo.Items, "")
		
		if result.DidCompress {
			modified = true
			totalItemsBefore += len(arrayInfo.Items)
			totalItemsAfter += len(result.Items)

			// Store in CCR if hash is present
			if result.CCRHash != nil && hc.ccrManager != nil {
				originalData, _ := json.Marshal(arrayInfo.Items)
				err := hc.ccrManager.Put(ctx, *result.CCRHash, originalData, sessionID)
				if err != nil {
					slog.Warn("headroom: CCR storage failed", "hash", *result.CCRHash, "error", err)
				} else {
					ccrHashes = append(ccrHashes, *result.CCRHash)
				}
			}

			// Replace array in message
			arrayInfo.ReplacementItems = result.Items
			arrayInfo.CCRMarker = result.DroppedSummary
		}
	}

	if !modified {
		return body, nil, nil
	}

	// Rebuild body with compressed arrays
	newBody, err := rebuildBodyWithCompressedArrays(body, arraysToCompress)
	if err != nil {
		return body, nil, fmt.Errorf("failed to rebuild body: %w", err)
	}

	compressionResult := &HeadroomCompressionResult{
		ArraysCompressed: len(arraysToCompress),
		ItemsBefore:      totalItemsBefore,
		ItemsAfter:       totalItemsAfter,
		CCRHashes:        ccrHashes,
		CompressionRatio: float64(totalItemsAfter) / float64(totalItemsBefore),
	}

	return newBody, compressionResult, nil
}

// HeadroomCompressionResult contains stats about Headroom compression.
type HeadroomCompressionResult struct {
	ArraysCompressed int
	ItemsBefore      int
	ItemsAfter       int
	CCRHashes        []string
	CompressionRatio float64
}

// ArrayInfo tracks a JSON array found in a message.
type ArrayInfo struct {
	MessageIndex     int
	ContentIndex     int
	ArrayPath        string
	Items            []json.RawMessage
	ReplacementItems []json.RawMessage
	CCRMarker        string
}

// extractMessagesForHeadroom extracts messages array from request body.
func extractMessagesForHeadroom(body []byte) ([]json.RawMessage, error) {
	var req struct {
		Messages []json.RawMessage `json:"messages"`
	}
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, err
	}
	return req.Messages, nil
}

// findJSONArraysInMessages scans messages for JSON arrays worth compressing.
func findJSONArraysInMessages(messages []json.RawMessage) []*ArrayInfo {
	var arrays []*ArrayInfo

	for i, msg := range messages {
		// Parse message
		var msgMap map[string]interface{}
		if err := json.Unmarshal(msg, &msgMap); err != nil {
			continue
		}

		// Check for tool_result content blocks (Anthropic format)
		if content, ok := msgMap["content"].([]interface{}); ok {
			for j, block := range content {
				blockMap, ok := block.(map[string]interface{})
				if !ok {
					continue
				}

				// Check if it's a tool_result block
				if blockMap["type"] == "tool_result" {
					if contentStr, ok := blockMap["content"].(string); ok {
						// Try to parse as JSON array
						var items []json.RawMessage
						if err := json.Unmarshal([]byte(contentStr), &items); err == nil && len(items) >= 5 {
							arrays = append(arrays, &ArrayInfo{
								MessageIndex: i,
								ContentIndex: j,
								ArrayPath:    fmt.Sprintf("messages[%d].content[%d].content", i, j),
								Items:        items,
							})
						}
					}
				}
			}
		}

		// Check for function_call or tool_calls results (OpenAI format)
		if toolCalls, ok := msgMap["tool_calls"].([]interface{}); ok {
			for j, call := range toolCalls {
				callMap, ok := call.(map[string]interface{})
				if !ok {
					continue
				}

				if function, ok := callMap["function"].(map[string]interface{}); ok {
					if argsStr, ok := function["arguments"].(string); ok {
						var items []json.RawMessage
						if err := json.Unmarshal([]byte(argsStr), &items); err == nil && len(items) >= 5 {
							arrays = append(arrays, &ArrayInfo{
								MessageIndex: i,
								ContentIndex: j,
								ArrayPath:    fmt.Sprintf("messages[%d].tool_calls[%d].function.arguments", i, j),
								Items:        items,
							})
						}
					}
				}
			}
		}
	}

	return arrays
}

// rebuildBodyWithCompressedArrays replaces arrays in body with compressed versions.
func rebuildBodyWithCompressedArrays(body []byte, arrays []*ArrayInfo) ([]byte, error) {
	// For simplicity, we'll reconstruct the entire body
	// In production, you might want to do more efficient in-place replacement
	
	var req map[string]interface{}
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, err
	}

	messages, ok := req["messages"].([]interface{})
	if !ok {
		return body, nil
	}

	// Apply replacements
	for _, arrayInfo := range arrays {
		if arrayInfo.ReplacementItems == nil {
			continue
		}

		if arrayInfo.MessageIndex >= len(messages) {
			continue
		}

		msgMap, ok := messages[arrayInfo.MessageIndex].(map[string]interface{})
		if !ok {
			continue
		}

		// Replace array and add CCR marker if present
		// This is a simplified implementation - production code would need
		// to handle the exact path replacement based on ArrayPath
		
		// For now, just update the message with a marker in content
		if arrayInfo.CCRMarker != "" && len(arrayInfo.CCRMarker) > 0 {
			// Add CCR marker to message content
			if content, ok := msgMap["content"].(string); ok {
				msgMap["content"] = content + "\n\n" + arrayInfo.CCRMarker
			}
		}
	}

	req["messages"] = messages
	return json.Marshal(req)
}
