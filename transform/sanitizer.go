package transform

import (
	"encoding/json"
)

var alwaysKeepFields = map[string]bool{
	"model":       true,
	"messages":    true,
	"stream":      true,
	"max_tokens":  true,
	"temperature": true,
	"top_p":       true,
	"n":           true,
	"stop":        true,
}

func ApplyRequestWhitelist(body []byte, passthroughFields, stripFields []string) []byte {
	if len(passthroughFields) == 0 && len(stripFields) == 0 {
		return body
	}

	var obj map[string]json.RawMessage
	if err := json.Unmarshal(body, &obj); err != nil {
		return body
	}

	if len(passthroughFields) > 0 {
		allowed := make(map[string]bool, len(passthroughFields)+len(alwaysKeepFields))
		for _, f := range passthroughFields {
			allowed[f] = true
		}
		for f := range alwaysKeepFields {
			allowed[f] = true
		}
		for k := range obj {
			if !allowed[k] {
				delete(obj, k)
			}
		}
	}

	for _, f := range stripFields {
		delete(obj, f)
	}

	result, err := json.Marshal(obj)
	if err != nil {
		return body
	}
	return result
}

type toolUseCapableProvider struct {
	code string
}

var toolUseCapable = map[string]bool{
	"openai":    true,
	"anthropic": true,
	"zhipu":     true,
	"minimax":   true,
}

func IsToolUseCapable(catalogCode string) bool {
	return toolUseCapable[catalogCode]
}

func NeedsToolCollapse(body []byte) bool {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(body, &obj); err != nil {
		return false
	}

	msgsRaw, ok := obj["messages"]
	if !ok {
		return false
	}

	var messages []map[string]json.RawMessage
	if err := json.Unmarshal(msgsRaw, &messages); err != nil {
		return false
	}

	for _, msg := range messages {
		var role string
		if r, ok := msg["role"]; ok {
			json.Unmarshal(r, &role)
		}
		if role == "tool" {
			return true
		}
		if _, ok := msg["tool_calls"]; ok {
			return true
		}
	}
	return false
}

func CollapseToolHistory(body []byte) []byte {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(body, &obj); err != nil {
		return body
	}

	msgsRaw, ok := obj["messages"]
	if !ok {
		return body
	}

	var messages []map[string]any
	if err := json.Unmarshal(msgsRaw, &messages); err != nil {
		return body
	}

	var systemParts []string
	var collapsed []map[string]any
	pendingToolResults := ""

	for _, msg := range messages {
		role, _ := msg["role"].(string)

		switch role {
		case "system":
			if content := extractContentText(msg); content != "" {
				systemParts = append(systemParts, content)
			}

		case "assistant":
			if toolCalls, ok := msg["tool_calls"].([]any); ok && len(toolCalls) > 0 {
				for _, tc := range toolCalls {
					tcMap, ok := tc.(map[string]any)
					if !ok {
						continue
					}
					fn, _ := tcMap["function"].(map[string]any)
					fnName := ""
					if fn != nil {
						fnName, _ = fn["name"].(string)
					}
					fnArgs := ""
					if fn != nil {
						fnArgs, _ = fn["arguments"].(string)
					}
					id, _ := tcMap["id"].(string)

					if fnName == "attempt_completion" {
						collapsed = append(collapsed, map[string]any{
							"role":    "assistant",
							"content": "[完成] " + fnArgs,
						})
					} else {
						text := "[调用工具 " + fnName
						if id != "" {
							text += " (id=" + id + ")"
						}
						text += " 参数: " + fnArgs + "]"
						collapsed = append(collapsed, map[string]any{
							"role":    "assistant",
							"content": text,
						})
					}
				}
			} else {
				content := extractContentText(msg)
				if reasoning := extractReasoning(msg); reasoning != "" {
					content = "[思考过程] " + reasoning + "\n" + content
				}
				if content != "" {
					collapsed = append(collapsed, map[string]any{
						"role":    "assistant",
						"content": content,
					})
				}
			}

		case "tool":
			content := extractContentText(msg)
			toolCallID, _ := msg["tool_call_id"].(string)
			result := "[工具结果"
			if toolCallID != "" {
				result += " (call_id=" + toolCallID + ")"
			}
			result += "]: " + content
			if pendingToolResults != "" {
				pendingToolResults += "\n"
			}
			pendingToolResults += result

		case "user":
			userContent := extractContentText(msg)
			if pendingToolResults != "" {
				userContent = pendingToolResults + "\n" + userContent
				pendingToolResults = ""
			}
			if userContent != "" {
				collapsed = append(collapsed, map[string]any{
					"role":    "user",
					"content": userContent,
				})
			}

		default:
			collapsed = append(collapsed, msg)
		}
	}

	if pendingToolResults != "" {
		collapsed = append(collapsed, map[string]any{
			"role":    "user",
			"content": pendingToolResults,
		})
	}

	if len(systemParts) > 0 {
		prefix := systemParts[0]
		for _, p := range systemParts[1:] {
			prefix += "\n" + p
		}
		finalMsgs := make([]map[string]any, 0, len(collapsed)+1)
		finalMsgs = append(finalMsgs, map[string]any{
			"role":    "system",
			"content": prefix,
		})
		finalMsgs = append(finalMsgs, dedupConsecutive(collapsed)...)
		collapsed = finalMsgs
	} else {
		collapsed = dedupConsecutive(collapsed)
	}

	msgsJSON, _ := json.Marshal(collapsed)
	obj["messages"] = msgsJSON
	delete(obj, "tools")
	delete(obj, "tool_choice")

	result, err := json.Marshal(obj)
	if err != nil {
		return body
	}
	return result
}

func extractContentText(msg map[string]any) string {
	switch c := msg["content"].(type) {
	case string:
		return c
	case []any:
		var parts []string
		for _, item := range c {
			if m, ok := item.(map[string]any); ok {
				if t, ok := m["type"].(string); ok && t == "text" {
					if text, ok := m["text"].(string); ok {
						parts = append(parts, text)
					}
				}
			}
		}
		result := ""
		for i, p := range parts {
			if i > 0 {
				result += "\n"
			}
			result += p
		}
		return result
	default:
		return ""
	}
}

func extractReasoning(msg map[string]any) string {
	switch c := msg["reasoning_content"].(type) {
	case string:
		return c
	case []any:
		return extractContentText(map[string]any{"content": c})
	default:
		return ""
	}
}

func dedupConsecutive(msgs []map[string]any) []map[string]any {
	if len(msgs) <= 1 {
		return msgs
	}
	var result []map[string]any
	result = append(result, msgs[0])
	for i := 1; i < len(msgs); i++ {
		prevRole, _ := result[len(result)-1]["role"].(string)
		curRole, _ := msgs[i]["role"].(string)
		if prevRole == curRole && (curRole == "user" || curRole == "assistant") {
			prevContent, _ := result[len(result)-1]["content"].(string)
			curContent, _ := msgs[i]["content"].(string)
			result[len(result)-1]["content"] = prevContent + "\n" + curContent
		} else {
			result = append(result, msgs[i])
		}
	}
	return result
}
