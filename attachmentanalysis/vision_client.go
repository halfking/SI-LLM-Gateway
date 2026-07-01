package attachmentanalysis

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

// VisionClient generates an image description by posting back to the
// gateway's own /v1/chat/completions endpoint with a vision-capable model.
// This mirrors admin.postAdminLLMChat (admin/admin_llm_task.go) — the
// self-loopback pattern — but carries image_url content blocks instead of
// plain text. The request body uses the OpenAI multimodal shape:
//
//	{ "model":"auto", "messages":[
//	    {"role":"system","content":"..."},
//	    {"role":"user","content":[
//	      {"type":"text","text":"..."},
//	      {"type":"image_url","image_url":{"url":"data:image/png;base64,..."}}
//	    ]}
//	  ]}
//
// The X-Gw-Task-Hint: vision header steers auto-route to a vision-capable
// model, so no separate credential management is needed.
type VisionClient struct {
	endpoint   string // gateway base URL, e.g. http://127.0.0.1:8080
	apiKey     string // admin/internal API key for loopback auth
	model      string // "" = use auto-route
	httpClient *http.Client
}

// NewVisionClient builds a vision loopback client. endpoint should be the
// gateway's own base URL (loopback). model="" means use "auto" + the
// vision task hint.
func NewVisionClient(endpoint, apiKey, model string, timeout time.Duration) *VisionClient {
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	return &VisionClient{
		endpoint:   strings.TrimRight(endpoint, "/"),
		apiKey:     apiKey,
		model:      model,
		httpClient: &http.Client{Timeout: timeout},
	}
}

// Describe implements VisionSource. It encodes the image as a base64 data
// URL inside an image_url content block and asks the model for a concise
// description.
func (c *VisionClient) Describe(ctx context.Context, imageData []byte, mediaType string) (string, error) {
	if c == nil || c.endpoint == "" {
		return "", fmt.Errorf("attachmentanalysis: vision client not configured")
	}
	if mediaType == "" {
		mediaType = "image/png"
	}

	dataURL := "data:" + mediaType + ";base64," + base64.StdEncoding.EncodeToString(imageData)

	model := c.model
	if model == "" {
		model = "auto"
	}

	// NOTE: messages use []map[string]any (not []map[string]string) so the
	// user message can carry a content array of typed blocks. This is the
	// key difference from the text-only admin loopback caller.
	payload := map[string]any{
		"model": model,
		"messages": []map[string]any{
			{
				"role": "system",
				"content": "You are an image analysis assistant. Describe the " +
					"image content concisely in 1-3 sentences. Cover: what the " +
					"image shows (screenshot, photo, chart, document, UI, code), " +
					"key visible text, and notable elements. Reply in the same " +
					"language as any text visible in the image.",
			},
			{
				"role": "user",
				"content": []map[string]any{
					{"type": "text", "text": "Describe this image concisely."},
					{"type": "image_url", "image_url": map[string]string{"url": dataURL}},
				},
			},
		},
		"max_tokens":  300,
		"temperature": 0.1,
	}

	body, _ := json.Marshal(payload)
	url := c.endpoint + "/v1/chat/completions"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
	}
	// Steer auto-route to a vision-capable model.
	req.Header.Set("X-Gw-Task-Hint", "vision")
	req.Header.Set("X-Gw-Work-Type", "attachment_analysis")
	req.Header.Set("X-Gw-Auto-Profile", "cost_first")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("vision loopback request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if err != nil {
		return "", fmt.Errorf("vision loopback read body: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("vision loopback HTTP %d: %s", resp.StatusCode, truncate(string(respBody), 500))
	}

	// Parse choices[0].message.content.
	var parsed struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return "", fmt.Errorf("vision loopback parse response: %w", err)
	}
	if len(parsed.Choices) == 0 {
		return "", fmt.Errorf("vision loopback: empty choices")
	}
	desc := strings.TrimSpace(parsed.Choices[0].Message.Content)
	if desc == "" {
		return "", fmt.Errorf("vision loopback: empty description")
	}
	slog.Debug("attachmentanalysis: vision describe ok",
		"desc_len", len(desc),
		"resolved_model", resp.Header.Get("X-Gw-Auto-Decision"))
	return desc, nil
}
