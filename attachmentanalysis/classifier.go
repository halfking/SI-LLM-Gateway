package attachmentanalysis

import (
	"encoding/base64"
	"regexp"
	"strings"
)

func base64Encode(data []byte) string {
	return base64.StdEncoding.EncodeToString(data)
}

// Classifier assigns human-readable tags to an attachment based on the
// OCR text and/or vision description. It is purely rule-based (local, zero
// cost) — no LLM call. The rules are deliberately conservative: a tag is
// only applied when there's clear evidence, so the absence of tags means
// "unknown", not "no content".
//
// Tag vocabulary (kept short and distinct):
//
//	code        - source code, stack traces, logs
//	document    - dense text content (articles, docs, PDFs)
//	chart       - data visualization (charts, graphs, plots)
//	ui          - application screenshots (dialogs, windows, web pages)
//	screenshot  - generic screen capture (fallback for UI-like content)
//	photo       - natural / photographic image
//	avatar      - small portrait/icon-like image
//	text_light  - some text but not enough to be a "document"
type Classifier struct{}

// NewClassifier returns the default rule-based classifier.
func NewClassifier() *Classifier { return &Classifier{} }

// Classify implements ClassifierSource.
func (cl *Classifier) Classify(ocrText, description string) []string {
	combined := ocrText + "\n" + description
	lower := strings.ToLower(combined)
	var tags []string
	seen := map[string]bool{}
	add := func(t string) {
		if !seen[t] {
			seen[t] = true
			tags = append(tags, t)
		}
	}

	// ── code / logs ───────────────────────────────────────────────
	if hasCodeSignatures(lower) {
		add("code")
	}

	// ── chart / data viz ──────────────────────────────────────────
	if matched, _ := regexp.MatchString(`(chart|graph|plot|柱状图|折线图|饼图|散点图|数据图)`, lower); matched {
		add("chart")
	}

	// ── document (dense text) ─────────────────────────────────────
	// Heuristic: OCR produced a lot of text relative to image area is a
	// strong document signal. We can't measure area here, so use line count.
	ocrLines := strings.Count(ocrText, "\n") + 1
	if ocrText != "" && ocrLines >= 8 && len(ocrText) > 400 {
		add("document")
	} else if ocrText != "" && ocrLines >= 2 {
		add("text_light")
	}

	// ── UI / screenshot ───────────────────────────────────────────
	if matched, _ := regexp.MatchString(`(screenshot|截图|界面|窗口|button|click|菜单|toolbar|对话框|dialog)`, lower); matched {
		add("screenshot")
	}
	// "ui" is a subset of screenshot — add when UI-element language present.
	if matched, _ := regexp.MatchString(`(menu|button|toolbar|navbar|sidebar|dropdown|tab |modal|dialog|登录|设置|search)`, lower); matched {
		add("ui")
	}

	// ── photo ─────────────────────────────────────────────────────
	if matched, _ := regexp.MatchString(`(photo|photograph|照片|camera|selfie|风景|landscape)`, lower); matched {
		add("photo")
	}

	// ── avatar ────────────────────────────────────────────────────
	if matched, _ := regexp.MatchString(`(avatar|头像|profile picture|portrait|人像)`, lower); matched {
		add("avatar")
	}

	// Fallback: if nothing matched but we have some text, call it a
	// generic screenshot (most common case for images sent to an LLM).
	if len(tags) == 0 && ocrText != "" {
		add("screenshot")
	}

	return tags
}

// hasCodeSignatures detects common source-code / log / stack-trace markers.
func hasCodeSignatures(s string) bool {
	// Function definitions across languages.
	if regexp.MustCompile(`func |def |class |public |private |import |require |package `).MatchString(s) {
		return true
	}
	// Stack traces.
	if strings.Contains(s, "traceback") || strings.Contains(s, "at line") || strings.Contains(s, ".go:") {
		return true
	}
	// Common code punctuation density: lots of braces / semicolons / arrows.
	braces := strings.Count(s, "{") + strings.Count(s, "}") + strings.Count(s, ";") + strings.Count(s, "->") + strings.Count(s, "=>")
	return braces >= 5
}
