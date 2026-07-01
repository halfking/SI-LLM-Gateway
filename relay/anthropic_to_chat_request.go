package relay

import (
	"encoding/json"
	"fmt"
	"strings"
)

// ConvertAnthropicRequestToChat converts an Anthropic Messages API
// request into OpenAI Chat Completions format. Used for Q2 (anthropic
// client -> openai upstream).
//
// Supported fields:
//   - model (passthrough)
//   - messages: content blocks -> OpenAI message format
//   - max_tokens (passthrough)
//   - system -> system message (prepended)
//   - stream (passthrough)
//   - temperature, top_p (passthrough)
//   - stop_sequences -> stop
//   - tools: input_schema -> parameters
//   - tool_choice: type-based conversion
//   - metadata.user_id -> user
//
// NOT supported:
//   - top_k (OpenAI doesn't have this)
func ConvertAnthropicRequestToChat(in []byte) ([]byte, error) {
	var src struct {
		Model         string          `json:"model"`
		Messages      []any           `json:"messages"`
		MaxTokens     int             `json:"max_tokens"`
		System        string          `json:"system,omitempty"`
		Stream        bool            `json:"stream,omitempty"`
		Temperature   *float64        `json:"temperature,omitempty"`
		TopP          *float64        `json:"top_p,omitempty"`
		TopK          *int            `json:"top_k,omitempty"`
		StopSequences []string        `json:"stop_sequences,omitempty"`
		Tools         json.RawMessage `json:"tools,omitempty"`
		ToolChoice    json.RawMessage `json:"tool_choice,omitempty"`
		Metadata      struct {
			UserID string `json:"user_id,omitempty"`
		} `json:"metadata,omitempty"`
	}

	if err := json.Unmarshal(in, &src); err != nil {
		return nil, fmt.Errorf("unmarshal: %w", err)
	}

	out := map[string]any{
		"model":      src.Model,
		"max_tokens": src.MaxTokens,
	}

	if src.Stream {
		out["stream"] = true
	}

	if src.Temperature != nil {
		out["temperature"] = *src.Temperature
	}
	if src.TopP != nil {
		out["top_p"] = *src.TopP
	}
	// Note: OpenAI doesn't have top_k, silently drop it

	if len(src.StopSequences) > 0 {
		out["stop"] = src.StopSequences
	}

	// Convert messages
	chatMsgs := make([]any, 0, len(src.Messages)+1)

	// System message goes first
	if src.System != "" {
		chatMsgs = append(chatMsgs, map[string]any{
			"role":    "system",
			"content": src.System,
		})
	}

	for _, m := range src.Messages {
		chatMsg, isTool := convertAnthropicMessageToChat(m)
		if isTool {
			// tool_result becomes separate tool message
			chatMsgs = append(chatMsgs, chatMsg)
		} else {
			chatMsgs = append(chatMsgs, chatMsg)
		}
	}

	out["messages"] = chatMsgs

	// Convert tools
	if len(src.Tools) > 0 {
		var anthTools []any
		if json.Unmarshal(src.Tools, &anthTools) == nil && len(anthTools) > 0 {
			chatTools := make([]any, 0, len(anthTools))
			for _, t := range anthTools {
				if chatTool, ok := anthropicToolToOpenAI(t); ok {
					chatTools = append(chatTools, chatTool)
				}
			}
			if len(chatTools) > 0 {
				out["tools"] = chatTools
			}
		}
	}

	// Convert tool_choice
	if len(src.ToolChoice) > 0 {
		var tc map[string]any
		if json.Unmarshal(src.ToolChoice, &tc) == nil {
			if chatTC := convertAnthropicToolChoiceToChat(tc); chatTC != nil {
				out["tool_choice"] = chatTC
			}
		}
	}

	// metadata.user_id → user
	if src.Metadata.UserID != "" {
		out["user"] = src.Metadata.UserID
	}

	return json.Marshal(out)
}

// convertAnthropicMessageToChat converts a single Anthropic message to OpenAI format.
// Returns (message, isTool) where isTool indicates if this is a tool result message.
func convertAnthropicMessageToChat(m any) (map[string]any, bool) {
	mm, ok := m.(map[string]any)
	if !ok {
		return map[string]any{"role": "user", "content": ""}, false
	}

	role, _ := mm["role"].(string)
	content := mm["content"]

	msg := map[string]any{"role": role}

	// content can be string or []block
	switch c := content.(type) {
	case string:
		msg["content"] = c
		return msg, false

	case []any:
		// Parse content blocks. We preserve the multi-part shape so
		// images survive the conversion: OpenAI Chat Completions models
		// `content` as an array of {type:"text"|"image_url"} blocks.
		var contentParts []map[string]any
		var toolCalls []map[string]any
		var toolResult *map[string]any

		for _, block := range c {
			b, _ := block.(map[string]any)
			blockType, _ := b["type"].(string)

			switch blockType {
			case "text":
				if text, ok := b["text"].(string); ok && text != "" {
					contentParts = append(contentParts, map[string]any{
						"type": "text",
						"text": text,
					})
				}
			case "tool_use":
				toolID, _ := b["id"].(string)
				name, _ := b["name"].(string)
				input := b["input"]
				argsJSON, _ := json.Marshal(input)
				toolCalls = append(toolCalls, map[string]any{
					"id":   toolID,
					"type": "function",
					"function": map[string]any{
						"name":      name,
						"arguments": string(argsJSON),
					},
				})
			case "tool_result":
				// Anthropic tool_result → OpenAI tool role message
				toolUseID, _ := b["tool_use_id"].(string)

				// content can be string or array
				var resultContent string
				switch rc := b["content"].(type) {
				case string:
					resultContent = rc
				case []any:
					// If content is array of blocks, extract text
					var parts []string
					for _, blk := range rc {
						if tb, ok := blk.(map[string]any); ok {
							if tb["type"] == "text" {
								if text, ok := tb["text"].(string); ok {
									parts = append(parts, text)
								}
							}
						}
					}
					resultContent = strings.Join(parts, "\n")
				}

				toolResult = &map[string]any{
					"role":         "tool",
					"tool_call_id": toolUseID,
					"content":      resultContent,
				}
			case "image":
				// Anthropic image → OpenAI image_url. Preserve the
				// full base64 payload so the upstream vision model can
				// actually see the image. (Previously this dropped the
				// data and emitted a "[Image: base64 data]" placeholder,
				// which was the root cause of image loss on the
				// anthropic→openai conversion path.)
				if source, ok := b["source"].(map[string]any); ok {
					sourceType, _ := source["type"].(string)
					switch sourceType {
					case "url":
						if url, ok := source["url"].(string); ok && url != "" {
							contentParts = append(contentParts, map[string]any{
								"type":      "image_url",
								"image_url": map[string]any{"url": url},
							})
						}
					case "base64":
						mediaType, _ := source["media_type"].(string)
						if mediaType == "" {
							mediaType = "image/png"
						}
						if data, ok := source["data"].(string); ok && data != "" {
							url := fmt.Sprintf("data:%s;base64,%s", mediaType, data)
							contentParts = append(contentParts, map[string]any{
								"type":      "image_url",
								"image_url": map[string]any{"url": url},
							})
						}
					}
				}
			}
		}

		// If this is a tool_result block, return tool message
		if toolResult != nil {
			return *toolResult, true
		}

		// Build content: array when we have image parts (multi-modal),
		// otherwise a plain string for text-only messages (keeps the
		// wire shape identical to legacy non-image requests).
		if len(contentParts) > 0 {
			// If every part is text, collapse back to a string.
			allText := true
			for _, p := range contentParts {
				if p["type"] != "text" {
					allText = false
					break
				}
			}
			if allText {
				var texts []string
				for _, p := range contentParts {
					texts = append(texts, p["text"].(string))
				}
				msg["content"] = strings.Join(texts, "\n")
			} else {
				parts := make([]any, len(contentParts))
				for i, p := range contentParts {
					parts[i] = p
				}
				msg["content"] = parts
			}
		} else {
			msg["content"] = ""
		}

		if len(toolCalls) > 0 {
			msg["tool_calls"] = toolCalls
		}

		return msg, false

	default:
		msg["content"] = ""
		return msg, false
	}
}

// anthropicToolToOpenAI converts Anthropic tool definition to OpenAI format
func anthropicToolToOpenAI(tool any) (map[string]any, bool) {
	t, ok := tool.(map[string]any)
	if !ok {
		return nil, false
	}

	name, _ := t["name"].(string)
	if name == "" {
		return nil, false
	}

	fn := map[string]any{"name": name}

	if desc, ok := t["description"].(string); ok && desc != "" {
		fn["description"] = desc
	}

	// input_schema → parameters
	if schema, ok := t["input_schema"]; ok {
		fn["parameters"] = schema
	} else {
		fn["parameters"] = map[string]any{
			"type":       "object",
			"properties": map[string]any{},
		}
	}

	return map[string]any{
		"type":     "function",
		"function": fn,
	}, true
}

// convertAnthropicToolChoiceToChat converts Anthropic tool_choice to OpenAI format
func convertAnthropicToolChoiceToChat(tc map[string]any) any {
	tcType, _ := tc["type"].(string)

	switch tcType {
	case "auto":
		return "auto"
	case "none":
		return "none"
	case "any":
		return "required"
	case "tool":
		if name, ok := tc["name"].(string); ok && name != "" {
			return map[string]any{
				"type": "function",
				"function": map[string]any{
					"name": name,
				},
			}
		}
	}

	return nil
}
