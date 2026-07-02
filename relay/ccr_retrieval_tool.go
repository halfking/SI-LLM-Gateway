package relay

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/kaixuan/llm-gateway-go/compressor/ccr"
)

// CCRRetrievalTool handles headroom_retrieve tool calls.
// It retrieves compressed data from CCR storage by hash, scoped to the
// caller's sessionID so a session cannot retrieve data from another
// session just by guessing the 24-char hash.
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
	return "Retrieve compressed data by CCR hash. Use when you see <<ccr:HASH>> markers in the conversation. The hash is a 24-character hexadecimal string. Retrieval is automatically scoped to the calling session."
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

// Execute retrieves data from CCR storage for the given sessionID.
// The sessionID MUST be supplied by the caller (the chat handler knows
// the session); passing an empty string returns ErrUnauthorized so we
// never serve data without an explicit session binding.
//
// Returns:
//   - ([]json.RawMessage, nil)            — JSON array
//   - (json.RawMessage, nil)             — any other JSON value, returned as-is
//   - (nil, ccr.ErrNotFound)              — hash unknown or owned by a different session
//   - (nil, ccr.ErrUnauthorized)          — caller did not provide a sessionID
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

	// Extract sessionID — required. The chat handler injects the calling
	// session into the args before calling Execute. If absent, refuse to
	// serve any data (defence in depth against IDOR).
	sessionID, _ := args["session_id"].(string)
	if sessionID == "" {
		return nil, fmt.Errorf("session_id is required (refusing unscoped lookup)")
	}

	// Session-scoped retrieval — returns ErrNotFound for both "no such hash"
	// and "hash belongs to another session" so we never leak existence.
	data, err := t.ccrManager.GetForSession(ctx, hash, sessionID)
	if err != nil {
		// Map domain errors to tool-friendly messages; do NOT leak which
		// session owns the hash.
		if errors.Is(err, ccr.ErrNotFound) || errors.Is(err, ccr.ErrUnauthorized) {
			return nil, fmt.Errorf("CCR hash not found for this session")
		}
		return nil, fmt.Errorf("failed to retrieve CCR data: %w", err)
	}

	// Parse as JSON array; fall back to passthrough if not an array.
	var items []json.RawMessage
	if err := json.Unmarshal(data, &items); err != nil {
		return json.RawMessage(data), nil
	}
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