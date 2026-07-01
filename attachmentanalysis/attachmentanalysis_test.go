package attachmentanalysis

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
)

// ── Classifier ───────────────────────────────────────────────────────

func TestClassifier_Code(t *testing.T) {
	cl := NewClassifier()
	ocr := "func main() {\n  fmt.Println(\"hello\")\n}\npackage main\nimport \"fmt\""
	tags := cl.Classify(ocr, "")
	if !contains(tags, "code") {
		t.Errorf("expected 'code' tag, got %v", tags)
	}
}

func TestClassifier_Document(t *testing.T) {
	cl := NewClassifier()
	// 8+ lines, 400+ chars → document.
	lines := make([]string, 12)
	for i := range lines {
		lines[i] = "This is a line of document text that is reasonably long."
	}
	ocr := strings.Join(lines, "\n")
	tags := cl.Classify(ocr, "")
	if !contains(tags, "document") {
		t.Errorf("expected 'document' tag, got %v", tags)
	}
}

func TestClassifier_TextLightShort(t *testing.T) {
	cl := NewClassifier()
	// 2 lines of text: not dense enough for 'document', but enough for
	// 'text_light'. The screenshot fallback only fires when no other tag
	// applied.
	tags := cl.Classify("hello world\nfoo bar", "")
	if !contains(tags, "text_light") {
		t.Errorf("expected 'text_light' tag for short text, got %v", tags)
	}
}

func TestClassifier_ScreenshotFallback(t *testing.T) {
	cl := NewClassifier()
	// A single short line: no document/code/UI signal → screenshot fallback.
	tags := cl.Classify("hi", "")
	if !contains(tags, "screenshot") {
		t.Errorf("expected 'screenshot' fallback tag, got %v", tags)
	}
}

func TestClassifier_Empty(t *testing.T) {
	cl := NewClassifier()
	tags := cl.Classify("", "")
	if len(tags) != 0 {
		t.Errorf("expected no tags for empty input, got %v", tags)
	}
}

func contains(slice []string, s string) bool {
	for _, v := range slice {
		if v == s {
			return true
		}
	}
	return false
}

// ── Injection ────────────────────────────────────────────────────────

// fakeLookup is a test InjectionLookup that returns a canned result for a
// specific hash.
type fakeLookup struct {
	results map[string]ContentIdentification
}

func (f fakeLookup) FindByHashDone(_ context.Context, hash, _ string) (ContentIdentification, bool, error) {
	ci, ok := f.results[hash]
	return ci, ok, nil
}

func TestMaybeInject_OpenAIImageURL(t *testing.T) {
	// A tiny 1x1 PNG.
	png := "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01"
	b64 := base64.StdEncoding.EncodeToString([]byte(png))
	dataURL := "data:image/png;base64," + b64
	hash := hashBase64(b64)

	body := map[string]any{
		"model": "gpt-4o",
		"messages": []any{
			map[string]any{
				"role": "user",
				"content": []any{
					map[string]any{"type": "text", "text": "What's this?"},
					map[string]any{"type": "image_url", "image_url": map[string]any{"url": dataURL}},
				},
			},
		},
	}
	raw, _ := json.Marshal(body)

	lookup := fakeLookup{results: map[string]ContentIdentification{
		hash: {Description: "A red square", Tags: []string{"photo"}},
	}}

	out, changed := MaybeInjectCachedDescription(context.Background(), raw, "t1", lookup, true)
	if !changed {
		t.Fatal("expected body to be changed")
	}

	var result map[string]any
	if err := json.Unmarshal(out, &result); err != nil {
		t.Fatal(err)
	}
	msgs := result["messages"].([]any)
	msg := msgs[0].(map[string]any)
	content := msg["content"].([]any)

	// Original 2 blocks + 1 injected = 3.
	if len(content) != 3 {
		t.Fatalf("expected 3 content blocks, got %d", len(content))
	}
	injected := content[2].(map[string]any)
	if injected["type"] != "text" {
		t.Errorf("expected injected block type=text, got %v", injected["type"])
	}
	text := injected["text"].(string)
	if !strings.Contains(text, "A red square") {
		t.Errorf("injected text should contain description, got: %s", text)
	}
	if !strings.HasPrefix(text, "[image context:") {
		t.Errorf("injected text should start with marker, got: %s", text)
	}
}

func TestMaybeInject_Disabled(t *testing.T) {
	body := []byte(`{"messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:image/png;base64,AAA"}}]}]}`)
	out, changed := MaybeInjectCachedDescription(context.Background(), body, "t1", fakeLookup{}, false)
	if changed {
		t.Fatal("expected no change when disabled")
	}
	if string(out) != string(body) {
		t.Fatal("expected body unchanged when disabled")
	}
}

func TestMaybeInject_Idempotent(t *testing.T) {
	b64 := base64.StdEncoding.EncodeToString([]byte("img"))
	hash := hashBase64(b64)
	dataURL := "data:image/png;base64," + b64

	// Message already has an injected block for this hash.
	body := map[string]any{
		"messages": []any{
			map[string]any{
				"role": "user",
				"content": []any{
					map[string]any{"type": "image_url", "image_url": map[string]any{"url": dataURL}},
					map[string]any{"type": "text", "text": "[image context: old]", "_injected_hash": hash},
				},
			},
		},
	}
	raw, _ := json.Marshal(body)
	lookup := fakeLookup{results: map[string]ContentIdentification{
		hash: {Description: "duplicate"},
	}}

	_, changed := MaybeInjectCachedDescription(context.Background(), raw, "t1", lookup, true)
	if changed {
		t.Fatal("expected no re-injection for already-injected hash")
	}
}

func TestMaybeInject_NoMatch(t *testing.T) {
	b64 := base64.StdEncoding.EncodeToString([]byte("unknown-img"))
	dataURL := "data:image/png;base64," + b64
	body := map[string]any{
		"messages": []any{
			map[string]any{
				"role": "user",
				"content": []any{
					map[string]any{"type": "image_url", "image_url": map[string]any{"url": dataURL}},
				},
			},
		},
	}
	raw, _ := json.Marshal(body)
	// Empty lookup → no match → no change.
	_, changed := MaybeInjectCachedDescription(context.Background(), raw, "t1", fakeLookup{}, true)
	if changed {
		t.Fatal("expected no change when no cached description exists")
	}
}

func TestParseDataURL(t *testing.T) {
	b64, mt := parseDataURL("data:image/png;base64,SGVsbG8=")
	if b64 != "SGVsbG8=" || mt != "image/png" {
		t.Errorf("unexpected parse: b64=%q mt=%q", b64, mt)
	}
	// Non-data URL.
	b64, mt = parseDataURL("https://example.com/img.png")
	if b64 != "" {
		t.Errorf("expected empty b64 for non-data URL, got %q", b64)
	}
}

// ── Config atomic ────────────────────────────────────────────────────

func TestAtomicConfig(t *testing.T) {
	var ac AtomicConfig
	// Zero value = everything disabled.
	if c := ac.Load(); c.Enabled {
		t.Error("expected zero-value config to be disabled")
	}
	ac.Store(Config{Enabled: true, OCREndpoint: "http://ocr:8080"})
	if c := ac.Load(); !c.Enabled || c.OCREndpoint != "http://ocr:8080" {
		t.Errorf("config round-trip failed: %+v", c)
	}
}

// ── Response reuse cache ─────────────────────────────────────────────

func TestResponseReuseCache(t *testing.T) {
	c := NewResponseReuseCache()
	c.SetResponseText("req-1", "t1", "a response")
	if text, ok := c.GetDescription("req-1", "t1"); !ok || text != "a response" {
		t.Errorf("expected cache hit, got ok=%v text=%q", ok, text)
	}
	// Wrong tenant.
	if _, ok := c.GetDescription("req-1", "t2"); ok {
		t.Error("expected no hit for wrong tenant")
	}
	// Miss.
	if _, ok := c.GetDescription("req-missing", "t1"); ok {
		t.Error("expected miss for unknown request")
	}
}
