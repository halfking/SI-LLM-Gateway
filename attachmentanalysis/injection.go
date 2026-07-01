package attachmentanalysis

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
)

// InjectionLookup is the narrow store interface the injector needs: look
// up a completed content-identification result by image content hash.
type InjectionLookup interface {
	FindByHashDone(ctx context.Context, contentHash, tenantID string) (ContentIdentification, bool, error)
}

// MaybeInjectCachedDescription scans a chat-request body for image content
// (OpenAI image_url blocks and Anthropic image blocks), looks each up by
// content hash, and — when a completed description is cached — appends a
// "[image context: ...]" text block to the SAME message that carried the
// image. This gives the model a textual hint about a previously-analyzed
// image without re-uploading the analysis on every request.
//
// Safety properties (feature #4):
//   - Additive only: never removes or modifies the original image block.
//     A bad description is at worst redundant, never destructive.
//   - Idempotent: if a message already contains an injected block for a
//     given hash, it is not re-injected.
//   - Opt-in: returns the body unchanged if injection is disabled, no
//     lookup is available, or no images are present.
//
// Returns the (possibly modified) body and whether any change was made.
func MaybeInjectCachedDescription(
	ctx context.Context,
	body []byte,
	tenantID string,
	lookup InjectionLookup,
	enabled bool,
) ([]byte, bool) {
	if !enabled || lookup == nil || len(body) == 0 {
		return body, false
	}

	var data map[string]any
	if err := json.Unmarshal(body, &data); err != nil {
		return body, false // not JSON — leave untouched
	}

	messages, ok := data["messages"].([]any)
	if !ok {
		// Could be Anthropic format (data["messages"] exists too in the
		// normalized form, but check content arrays regardless).
		return body, false
	}

	changed := false
	for _, msgRaw := range messages {
		msg, ok := msgRaw.(map[string]any)
		if !ok {
			continue
		}
		content, ok := msg["content"]
		if !ok {
			continue
		}

		// content can be a string (no images) or an array of blocks.
		blocks, ok := content.([]any)
		if !ok {
			continue
		}

		injected := injectIntoBlocks(ctx, blocks, tenantID, lookup)
		if len(injected) > 0 {
			// Append the injected text blocks after the existing content.
			msg["content"] = append(blocks, injected...)
			changed = true
		}
	}

	if !changed {
		return body, false
	}
	out, err := json.Marshal(data)
	if err != nil {
		return body, false // marshal failed — safest to return original
	}
	return out, true
}

// injectIntoBlocks scans an array of content blocks for images, looks each
// up by hash, and returns any text blocks to append. Returns nil if
// nothing to inject.
func injectIntoBlocks(ctx context.Context, blocks []any, tenantID string, lookup InjectionLookup) []any {
	var toAppend []any
	for _, blockRaw := range blocks {
		block, ok := blockRaw.(map[string]any)
		if !ok {
			continue
		}
		// OpenAI: {"type":"image_url","image_url":{"url":"data:..."}}
		// Anthropic: {"type":"image","source":{"type":"base64","data":"..."}}
		b64, mediaType := extractImageBase64(block)
		if b64 == "" {
			continue
		}
		hash := hashBase64(b64)

		// Idempotency: skip if an injection for this hash already exists
		// in the same message (avoid double-injecting on retry/replay).
		if hasInjectedBlock(blocks, hash) {
			continue
		}

		ci, found, err := lookup.FindByHashDone(ctx, hash, tenantID)
		if err != nil || !found {
			continue
		}
		text := buildInjectionText(ci)
		if text == "" {
			continue
		}
		toAppend = append(toAppend, map[string]any{
			"type": "text",
			"text": text,
			// Marker for idempotency: a hidden key the upstream model
			// ignores but we can detect to prevent re-injection.
			"_injected_hash": hash,
		})
		_ = mediaType // not needed for the text block
	}
	return toAppend
}

// extractImageBase64 pulls the base64 payload from either the OpenAI or
// Anthropic image-block shape. Returns ("", "") for non-image blocks.
func extractImageBase64(block map[string]any) (b64, mediaType string) {
	t, _ := block["type"].(string)
	switch t {
	case "image_url":
		iu, ok := block["image_url"].(map[string]any)
		if !ok {
			return "", ""
		}
		url, _ := iu["url"].(string)
		return parseDataURL(url)
	case "image":
		src, ok := block["source"].(map[string]any)
		if !ok {
			return "", ""
		}
		if st, _ := src["type"].(string); st == "base64" {
			d, _ := src["data"].(string)
			mt, _ := src["media_type"].(string)
			return d, mt
		}
	}
	return "", ""
}

// parseDataURL splits a "data:image/png;base64,XXXX" URL into (base64, mediaType).
func parseDataURL(url string) (b64, mediaType string) {
	const prefix = "data:"
	if !strings.HasPrefix(url, prefix) {
		return "", ""
	}
	rest := url[len(prefix):]
	semi := strings.Index(rest, ";")
	comma := strings.Index(rest, ",")
	if semi < 0 || comma < 0 || semi > comma {
		return "", ""
	}
	mediaType = rest[:semi]
	b64 = rest[comma+1:]
	return b64, mediaType
}

func hashBase64(b64 string) string {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		// If decoding fails, hash the string itself as a fallback so
		// lookups are still consistent for the same input.
		raw = []byte(b64)
	}
	h := sha256.Sum256(raw)
	return fmt.Sprintf("%x", h[:])
}

func hasInjectedBlock(blocks []any, hash string) bool {
	for _, bRaw := range blocks {
		b, ok := bRaw.(map[string]any)
		if !ok {
			continue
		}
		if h, _ := b["_injected_hash"].(string); h == hash {
			return true
		}
	}
	return false
}

func buildInjectionText(ci ContentIdentification) string {
	var parts []string
	if ci.Description != "" {
		parts = append(parts, ci.Description)
	}
	if ci.OCRText != "" {
		parts = append(parts, "OCR: "+truncate(ci.OCRText, 500))
	}
	if len(ci.Tags) > 0 {
		parts = append(parts, "tags: "+strings.Join(ci.Tags, ", "))
	}
	if len(parts) == 0 {
		return ""
	}
	return "[image context: " + strings.Join(parts, " | ") + "]"
}
