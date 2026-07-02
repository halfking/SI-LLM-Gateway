package compressor

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/kaixuan/llm-gateway-go/compressor/ccr"
	"github.com/kaixuan/llm-gateway-go/compressor/headroom"
)

// HeadroomCompressor handles Headroom-based JSON array compression.
type HeadroomCompressor struct {
	crusher    *headroom.SmartCrusher
	ccrManager *ccr.Manager
	enabled    bool
	timeout    time.Duration
}

// NewHeadroomCompressor creates a new Headroom compressor.
func NewHeadroomCompressor(ccrManager *ccr.Manager) *HeadroomCompressor {
	config := headroom.DefaultSmartCrusherConfig()
	fullConfig := headroom.LoadConfigFromEnv()
	
	return &HeadroomCompressor{
		crusher:    headroom.NewSmartCrusher(config),
		ccrManager: ccrManager,
		enabled:    true,
		timeout:    fullConfig.Timeout,
	}
}

// NewHeadroomCompressorWithConfig creates a Headroom compressor with custom config.
func NewHeadroomCompressorWithConfig(config headroom.SmartCrusherConfig, ccrManager *ccr.Manager) *HeadroomCompressor {
	fullConfig := headroom.LoadConfigFromEnv()
	return &HeadroomCompressor{
		crusher:    headroom.NewSmartCrusher(config),
		ccrManager: ccrManager,
		enabled:    true,
		timeout:    fullConfig.Timeout,
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

	// Apply timeout to prevent compression from blocking indefinitely
	if hc.timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, hc.timeout)
		defer cancel()
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
		// Check context cancellation before each compression
		select {
		case <-ctx.Done():
			slog.Warn("headroom: compression timeout exceeded, returning original body",
				"session", sessionID, "timeout", hc.timeout)
			return body, nil, ctx.Err()
		default:
		}

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
// Uses ArrayPath to locate and replace the exact array field, then optionally
// appends a CCR marker. Handles both Anthropic (tool_result.content string)
// and OpenAI (tool_calls[].function.arguments string) formats.
func rebuildBodyWithCompressedArrays(body []byte, arrays []*ArrayInfo) ([]byte, error) {
	var req map[string]interface{}
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, err
	}

	messages, ok := req["messages"].([]interface{})
	if !ok {
		return body, nil
	}

	// Apply replacements by parsing ArrayPath
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

		// Parse ArrayPath: "messages[i].content[j].content" or "messages[i].tool_calls[j].function.arguments"
		// We know MessageIndex and ContentIndex, so we can directly navigate.
		// Case 1: Anthropic tool_result — content[ContentIndex].content is a JSON string
		if content, ok := msgMap["content"].([]interface{}); ok && arrayInfo.ContentIndex < len(content) {
			blockMap, ok := content[arrayInfo.ContentIndex].(map[string]interface{})
			if ok && blockMap["type"] == "tool_result" {
				// Marshal ReplacementItems back to JSON string
				replacementJSON, err := json.Marshal(arrayInfo.ReplacementItems)
				if err != nil {
					continue
				}
				blockMap["content"] = string(replacementJSON)

				// Append CCR marker if present (Anthropic allows appending to content string)
				if arrayInfo.CCRMarker != "" {
					blockMap["content"] = string(replacementJSON) + "\n\n" + arrayInfo.CCRMarker
				}
				content[arrayInfo.ContentIndex] = blockMap
				msgMap["content"] = content
			}
		}

		// Case 2: OpenAI tool_calls — tool_calls[ContentIndex].function.arguments is a JSON string
		if toolCalls, ok := msgMap["tool_calls"].([]interface{}); ok && arrayInfo.ContentIndex < len(toolCalls) {
			callMap, ok := toolCalls[arrayInfo.ContentIndex].(map[string]interface{})
			if !ok {
				continue
			}
			function, ok := callMap["function"].(map[string]interface{})
			if !ok {
				continue
			}

			// Marshal ReplacementItems back to JSON string
			replacementJSON, err := json.Marshal(arrayInfo.ReplacementItems)
			if err != nil {
				continue
			}
			function["arguments"] = string(replacementJSON)

			// OpenAI doesn't have a natural place to append CCR marker in arguments JSON,
			// so we skip it here (or could add a synthetic "__ccr_marker" field if needed).
			callMap["function"] = function
			toolCalls[arrayInfo.ContentIndex] = callMap
			msgMap["tool_calls"] = toolCalls
		}

		messages[arrayInfo.MessageIndex] = msgMap
	}

	req["messages"] = messages
	return json.Marshal(req)
}
