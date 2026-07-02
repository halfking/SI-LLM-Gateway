package relay

import (
	"context"
	"encoding/json"
	"log/slog"
)

// CCRToolInterceptor intercepts headroom_retrieve tool calls in client requests
// (specifically in tool_result / tool_use blocks) and executes them server-side,
// replacing the tool call with the actual retrieved data from CCR storage.
//
// This makes CCR retrieval transparent to clients when they're in a conversation
// loop where:
//  1. LLM responds with tool_use calling headroom_retrieve(hash="...")
//  2. Client sends next request with tool_result block containing the hash
//  3. Interceptor detects the tool_result, executes retrieval, replaces with data
//  4. LLM receives expanded data instead of hash reference
//
// Workflow:
//   Client → Gateway: messages=[..., {role:"user", content:[{type:"tool_result", tool_use_id:"...", content:"<<retrieve hash=ABC>>"}]}]
//   Interceptor: Detects tool_result for headroom_retrieve
//   Interceptor: Calls CCRRetrievalTool.Execute(hash="ABC", session_id="...")
//   Interceptor: Replaces content with retrieved JSON array
//   Gateway → LLM: messages=[..., {role:"user", content:[{type:"tool_result", tool_use_id:"...", content:[...actual data...]}]}]
type CCRToolInterceptor struct {
	tool *CCRRetrievalTool
}

// NewCCRToolInterceptor creates a new CCR tool call interceptor.
func NewCCRToolInterceptor(tool *CCRRetrievalTool) *CCRToolInterceptor {
	return &CCRToolInterceptor{
		tool: tool,
	}
}

// InterceptRequest scans the client request for tool_result blocks that reference
// headroom_retrieve and executes them server-side, replacing the hash reference
// with the actual retrieved data.
//
// Returns:
//   - (modified, true, nil)   — tool_result intercepted and replaced
//   - (original, false, nil)  — no headroom_retrieve tool_result found
//   - (original, false, err)  — parse error (non-fatal, continue with original)
//
// Note: Retrieval failures are logged but don't fail the request — we pass through
// the original tool_result so the LLM can see the error.
func (i *CCRToolInterceptor) InterceptRequest(ctx context.Context, body []byte, sessionID, protocol string) ([]byte, bool, error) {
	if i.tool == nil || sessionID == "" {
		return body, false, nil
	}

	var req map[string]interface{}
	if err := json.Unmarshal(body, &req); err != nil {
		// Not JSON or malformed — pass through
		return body, false, nil
	}

	// Different protocols have different request structures
	switch protocol {
	case "anthropic-messages":
		return i.interceptAnthropicRequest(ctx, req, sessionID)
	default: // OpenAI
		return i.interceptOpenAIRequest(ctx, req, sessionID)
	}
}

// interceptAnthropicRequest handles Anthropic Messages API format:
// {
//   "messages": [
//     ...,
//     {
//       "role": "user",
//       "content": [
//         {"type": "tool_result", "tool_use_id": "toolu_xxx", "content": "<<retrieve hash=ABC123>>"}
//       ]
//     }
//   ]
// }
func (i *CCRToolInterceptor) interceptAnthropicRequest(ctx context.Context, req map[string]interface{}, sessionID string) ([]byte, bool, error) {
	messagesRaw, ok := req["messages"]
	if !ok {
		body, err := json.Marshal(req)
		return body, false, err
	}

	messages, ok := messagesRaw.([]interface{})
	if !ok || len(messages) == 0 {
		body, err := json.Marshal(req)
		return body, false, err
	}

	modified := false
	for _, msgRaw := range messages {
		msg, ok := msgRaw.(map[string]interface{})
		if !ok {
			continue
		}

		contentRaw, ok := msg["content"]
		if !ok {
			continue
		}

		// Content can be string or array
		contentArr, ok := contentRaw.([]interface{})
		if !ok {
			continue
		}

		for j, blockRaw := range contentArr {
			block, ok := blockRaw.(map[string]interface{})
			if !ok {
				continue
			}

			// Check if this is a tool_result block
			blockType, _ := block["type"].(string)
			if blockType != "tool_result" {
				continue
			}

			// Check if content contains CCR hash reference
			contentVal, ok := block["content"]
			if !ok {
				continue
			}

			// Content might be string with hash marker
			contentStr, ok := contentVal.(string)
			if !ok {
				continue
			}

			// Parse hash from marker format: "<<retrieve hash=ABC123>>"
			hash := i.extractHashFromMarker(contentStr)
			if hash == "" {
				continue
			}

			// Execute retrieval
			args := map[string]interface{}{
				"hash":       hash,
				"session_id": sessionID,
			}
			result, err := i.tool.Execute(ctx, args)
			if err != nil {
				slog.Warn("ccr: tool_result interception failed", "hash", hash, "error", err)
				continue // Leave tool_result intact
			}

			// Replace content with retrieved data
			block["content"] = result
			contentArr[j] = block
			modified = true
		}

		if modified {
			msg["content"] = contentArr
		}
	}

	if !modified {
		body, err := json.Marshal(req)
		return body, false, err
	}

	req["messages"] = messages
	modifiedBody, err := json.Marshal(req)
	if err != nil {
		body, _ := json.Marshal(req)
		return body, false, err
	}

	return modifiedBody, true, nil
}

// interceptOpenAIRequest handles OpenAI Chat Completions API format:
// {
//   "messages": [
//     ...,
//     {
//       "role": "tool",
//       "tool_call_id": "call_xxx",
//       "content": "<<retrieve hash=ABC123>>"
//     }
//   ]
// }
func (i *CCRToolInterceptor) interceptOpenAIRequest(ctx context.Context, req map[string]interface{}, sessionID string) ([]byte, bool, error) {
	messagesRaw, ok := req["messages"]
	if !ok {
		body, err := json.Marshal(req)
		return body, false, err
	}

	messages, ok := messagesRaw.([]interface{})
	if !ok || len(messages) == 0 {
		body, err := json.Marshal(req)
		return body, false, err
	}

	modified := false
	for _, msgRaw := range messages {
		msg, ok := msgRaw.(map[string]interface{})
		if !ok {
			continue
		}

		// Check if this is a tool role message
		role, _ := msg["role"].(string)
		if role != "tool" {
			continue
		}

		contentRaw, ok := msg["content"]
		if !ok {
			continue
		}

		contentStr, ok := contentRaw.(string)
		if !ok {
			continue
		}

		// Parse hash from marker
		hash := i.extractHashFromMarker(contentStr)
		if hash == "" {
			continue
		}

		// Execute retrieval
		args := map[string]interface{}{
			"hash":       hash,
			"session_id": sessionID,
		}
		result, err := i.tool.Execute(ctx, args)
		if err != nil {
			slog.Warn("ccr: tool message interception failed", "hash", hash, "error", err)
			continue
		}

		// Replace content with retrieved data (as JSON string)
		resultJSON, _ := json.Marshal(result)
		msg["content"] = string(resultJSON)
		modified = true
	}

	if !modified {
		body, err := json.Marshal(req)
		return body, false, err
	}

	req["messages"] = messages
	modifiedBody, err := json.Marshal(req)
	if err != nil {
		body, _ := json.Marshal(req)
		return body, false, err
	}

	return modifiedBody, true, nil
}

// extractHashFromMarker parses "<<retrieve hash=ABC123>>" → "ABC123"
// Returns empty string if not a valid marker.
func (i *CCRToolInterceptor) extractHashFromMarker(content string) string {
	// Simple parser for <<retrieve hash=HASH>>
	// TODO: Make this more robust if format evolves
	if len(content) < 20 {
		return ""
	}

	// Check for marker prefix
	if content[:11] != "<<retrieve " {
		return ""
	}

	// Find hash= and extract
	hashStart := 11 + 5 // "<<retrieve hash="
	if len(content) < hashStart+24+2 { // hash + ">>"
		return ""
	}

	hashEnd := hashStart + 24
	if content[hashEnd:hashEnd+2] != ">>" {
		return ""
	}

	return content[hashStart:hashEnd]
}
