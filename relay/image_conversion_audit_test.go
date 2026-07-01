package relay

import (
	"encoding/json"
	"strings"
	"testing"
)

// TestAnthropicBase64ImagePreserved verifies that the audit fix for the
// "image lost on anthropic→openai conversion" bug works: a base64 image
// block must be converted to an OpenAI image_url block carrying the full
// data URL, NOT the "[Image: base64 data]" placeholder that used to be
// emitted.
func TestAnthropicBase64ImagePreserved(t *testing.T) {
	// A tiny but valid 1x1 red PNG.
	const red1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
	in := []byte(`{
        "model":"gpt-4o",
        "max_tokens":100,
        "messages":[{
            "role":"user",
            "content":[
                {"type":"text","text":"what is this?"},
                {"type":"image","source":{"type":"base64","media_type":"image/png","data":"` + red1x1 + `"}}
            ]
        }]
    }`)
	out, err := ConvertAnthropicRequestToChat(in)
	if err != nil {
		t.Fatalf("convert: %v", err)
	}

	var v map[string]any
	if err := json.Unmarshal(out, &v); err != nil {
		t.Fatalf("unmarshal output: %v", err)
	}
	msgs := v["messages"].([]any)
	if len(msgs) != 1 {
		t.Fatalf("messages len = %d, want 1", len(msgs))
	}
	msg := msgs[0].(map[string]any)
	content, ok := msg["content"].([]any)
	if !ok {
		t.Fatalf("content is %T, want []any (multi-modal). Body: %s", msg["content"], out)
	}
	var foundImage bool
	for _, part := range content {
		p, _ := part.(map[string]any)
		if p["type"] != "image_url" {
			continue
		}
		foundImage = true
		iu, _ := p["image_url"].(map[string]any)
		url, _ := iu["url"].(string)
		if !strings.HasPrefix(url, "data:image/png;base64,") {
			t.Errorf("image url prefix wrong: %q", url)
		}
		if !strings.HasSuffix(url, red1x1) {
			t.Errorf("base64 payload dropped from image url; got %d chars", len(url))
		}
	}
	if !foundImage {
		t.Fatalf("no image_url block in converted content: %s", out)
	}
}

// TestAnthropicImageURLPreserved verifies url-sourced images survive too.
func TestAnthropicImageURLPreserved(t *testing.T) {
	const want = "https://example.com/cat.png"
	in := []byte(`{
        "model":"gpt-4o",
        "max_tokens":10,
        "messages":[{
            "role":"user",
            "content":[
                {"type":"image","source":{"type":"url","url":"` + want + `"}}
            ]
        }]
    }`)
	out, err := ConvertAnthropicRequestToChat(in)
	if err != nil {
		t.Fatalf("convert: %v", err)
	}
	if !strings.Contains(string(out), want) {
		t.Fatalf("image url %q lost in conversion: %s", want, out)
	}
	if strings.Contains(string(out), "[Image:") {
		t.Fatalf("regression: placeholder emitted instead of real url: %s", out)
	}
}

// TestChatToAnthropicDataURLDecoded verifies that an OpenAI data: URL
// image is converted into an Anthropic base64 source (not a url source,
// which the Anthropic API rejects for data URLs).
func TestChatToAnthropicDataURLDecoded(t *testing.T) {
	const payload = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
	in := []byte(`{
        "model":"claude-3-5-sonnet",
        "max_tokens":10,
        "messages":[{
            "role":"user",
            "content":[
                {"type":"text","text":"look"},
                {"type":"image_url","image_url":{"url":"data:image/png;base64,` + payload + `"}}
            ]
        }]
    }`)
	out, err := ConvertChatRequestToAnthropic(in)
	if err != nil {
		t.Fatalf("convert: %v", err)
	}
	var v map[string]any
	if err := json.Unmarshal(out, &v); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	msgs := v["messages"].([]any)
	msg := msgs[0].(map[string]any)
	content := msg["content"].([]any)
	var sawBase64Source bool
	for _, part := range content {
		p, _ := part.(map[string]any)
		if p["type"] != "image" {
			continue
		}
		src, _ := p["source"].(map[string]any)
		if src["type"] == "base64" {
			sawBase64Source = true
			if src["media_type"] != "image/png" {
				t.Errorf("media_type = %v, want image/png", src["media_type"])
			}
			if src["data"] != payload {
				t.Errorf("base64 data mismatch (got len %d, want %d)",
					len(src["data"].(string)), len(payload))
			}
		}
	}
	if !sawBase64Source {
		t.Fatalf("data URL was not decoded into a base64 source: %s", out)
	}
}
