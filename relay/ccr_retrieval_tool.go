package relay

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/kaixuan/llm-gateway-go/compressor/ccr"
)

// CCRRetrievalTool handles headroom_retrieve tool calls.
// It retrieves compressed data from CCR storage by hash.
type CCRRetrievalTool struct {
	ccrManager *ccr.Manager
}

// NewCCRRetrievalTool creates a new CCR retrieval tool.
func NewCCRRetrievalTool(ccrManager *ccr.Manager) *CCRRetrievalTool {
	return &CCRRetrievalTool{
		ccrManager: ccrManager,
	}
}

// Name returns the tool name.
func (t *CCRRetrievalTool) Name() string {
	return "headroom_retrieve"
}

// Description returns the tool description for LLM.
func (t *CCRRetrievalTool) Description() string {
	return "Retrieve compressed data by CCR hash. Use when you see <<ccr:HASH>> markers in the conversation. The hash is a 24-character hexadecimal string."
}

// InputSchema returns the JSON schema for tool inputs.
func (t *CCRRetrievalTool) InputSchema() map[string]interface{} {
	return map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"hash": map[string]interface{}{
				"type":        "string",
				"description": "24-character CCR hash from the <<ccr:HASH>> marker",
				"pattern":     "^[a-f0-9]{24}$",
			},
		},
		"required": []string{"hash"},
	}
}

// Execute retrieves data from CCR storage.
func (t *CCRRetrievalTool) Execute(ctx context.Context, args map[string]interface{}) (interface{}, error) {
	if t.ccrManager == nil {
		return nil, fmt.Errorf("CCR manager not configured")
	}

	// Extract hash from arguments
	hash, ok := args["hash"].(string)
	if !ok || hash == "" {
		return nil, fmt.Errorf("hash parameter is required and must be a string")
	}

	// Validate hash format (24 hex characters)
	if len(hash) != 24 {
		return nil, fmt.Errorf("invalid hash format: expected 24 characters, got %d", len(hash))
	}

	// Retrieve from CCR
	data, err := t.ccrManager.Get(ctx, hash)
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve CCR data: %w", err)
	}

	// Parse as JSON array
	var items []json.RawMessage
	if err := json.Unmarshal(data, &items); err != nil {
		// If not an array, return as-is
		return json.RawMessage(data), nil
	}

	// Return the array
	return items, nil
}

// ToolDefinition returns the full tool definition for registration.
func (t *CCRRetrievalTool) ToolDefinition() map[string]interface{} {
	return map[string]interface{}{
		"name":         t.Name(),
		"description":  t.Description(),
		"input_schema": t.InputSchema(),
	}
}

// ToolDefinitionAnthropic returns the Anthropic-format tool definition.
func (t *CCRRetrievalTool) ToolDefinitionAnthropic() map[string]interface{} {
	return map[string]interface{}{
		"name":         t.Name(),
		"description":  t.Description(),
		"input_schema": t.InputSchema(),
	}
}

// ToolDefinitionOpenAI returns the OpenAI-format function definition.
func (t *CCRRetrievalTool) ToolDefinitionOpenAI() map[string]interface{} {
	return map[string]interface{}{
		"type": "function",
		"function": map[string]interface{}{
			"name":        t.Name(),
			"description": t.Description(),
			"parameters":  t.InputSchema(),
		},
	}
}
