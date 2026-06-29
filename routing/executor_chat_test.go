package routing

import (
	"strings"
	"testing"

	"github.com/kaixuan/llm-gateway-go/provider"
)

func TestChatExecutor_BuildRequest(t *testing.T) {
	ce := &ChatExecutor{}
	cand := provider.Candidate{
		BaseURL:  "https://api.openai.com",
		Protocol: "openai-completions",
		APIKey:   "sk-test",
	}
	body := []byte(`{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}`)

	req, err := ce.BuildRequest(cand, body, false)
	if err != nil {
		t.Fatalf("BuildRequest: %v", err)
	}
	if req.URL.String() != "https://api.openai.com/v1/chat/completions" {
		t.Errorf("URL = %q, want https://api.openai.com/v1/chat/completions", req.URL.String())
	}
	if got := req.Header.Get("Authorization"); got != "Bearer sk-test" {
		t.Errorf("Authorization = %q, want Bearer sk-test", got)
	}
	if !strings.Contains(req.Header.Get("Content-Type"), "application/json") {
		t.Errorf("Content-Type = %q, want application/json", req.Header.Get("Content-Type"))
	}
}

func TestChatExecutor_CheckSoftMismatch_NotImplemented(t *testing.T) {
	// For OpenAI, upstream returns the same model it was asked for
	// (no silent fallback). This MUST return false.
	ce := &ChatExecutor{}
	mismatched, reason := ce.CheckSoftMismatch("gpt-4", "gpt-4")
	if mismatched {
		t.Errorf("OpenAI never silently falls back; mismatched should be false (reason=%q)", reason)
	}
}

// TestPrepareRequestBody_InjectsStreamOptionsForOpenAI pins the OpenAI
// behaviour: when params.IsStream=true and the upstream is openai-completions,
// prepareRequestBody MUST inject "stream_options":{"include_usage":true} so
// the upstream returns a final usage chunk we can attribute for billing.
func TestPrepareRequestBody_InjectsStreamOptionsForOpenAI(t *testing.T) {
	params := &ExecParams{
		BodyBytes:   []byte(`{"model":"gpt-4","stream":true,"messages":[]}`),
		ClientModel: "gpt-4",
		IsStream:    true,
	}
	cand := provider.Candidate{
		Protocol:    "openai-completions",
		CatalogCode: "openai",
		RawModel:    "gpt-4",
	}

	got := prepareRequestBody(params, cand)
	if !strings.Contains(string(got), `"stream_options"`) {
		t.Errorf("OpenAI streaming body should include stream_options, got: %s", string(got))
	}
}

// TestPrepareRequestBody_SkipsStreamOptionsForAnthropic pins the Anthropic
// guard: when params.IsStream=true and the upstream speaks anthropic-messages,
// prepareRequestBody MUST NOT inject "stream_options" because Anthropic has
// no such field (usage arrives via message_start + message_delta events).
// Injecting it would either be silently ignored or rejected by strict
// providers and complicates protocol passthrough debugging.
func TestPrepareRequestBody_SkipsStreamOptionsForAnthropic(t *testing.T) {
	params := &ExecParams{
		BodyBytes:   []byte(`{"model":"claude-3-5-sonnet","stream":true,"max_tokens":256,"messages":[]}`),
		ClientModel: "claude-3-5-sonnet",
		IsStream:    true,
	}
	cand := provider.Candidate{
		Protocol:    "anthropic-messages",
		CatalogCode: "anthropic",
		RawModel:    "claude-3-5-sonnet",
	}

	got := prepareRequestBody(params, cand)
	if strings.Contains(string(got), `"stream_options"`) {
		t.Errorf("Anthropic streaming body should NOT include stream_options, got: %s", string(got))
	}
	if !strings.Contains(string(got), `"stream":true`) {
		t.Errorf("Anthropic body should keep stream:true, got: %s", string(got))
	}
}

// TestExtractOpenAIUsageFromBody_CacheRead covers the 2026-06-30 fix
// to extractOpenAIUsageFromBody: when upstream reports
// prompt_tokens_details.cached_tokens (the OpenAI variant of
// Anthropic's cache_read_input_tokens), the function must surface it
// in the third return value. Before the fix, this field was dropped
// and request_logs.cache_read_tokens stayed NULL even for OpenAI
// cached-prompt calls.
func TestExtractOpenAIUsageFromBody_CacheRead(t *testing.T) {
	body := []byte(`{
		"id": "chatcmpl-1",
		"object": "chat.completion",
		"model": "gpt-4o",
		"choices": [],
		"usage": {
			"prompt_tokens": 100,
			"completion_tokens": 50,
			"total_tokens": 150,
			"prompt_tokens_details": {
				"cached_tokens": 80
			}
		}
	}`)
	pt, ct, cr, cw := extractOpenAIUsageFromBody(body)
	if pt == nil || *pt != 100 {
		t.Errorf("prompt_tokens = %v, want pointer to 100", pt)
	}
	if ct == nil || *ct != 50 {
		t.Errorf("completion_tokens = %v, want pointer to 50", ct)
	}
	if cr == nil || *cr != 80 {
		t.Errorf("cache_read = %v, want pointer to 80", cr)
	}
	// OpenAI Chat Completions does not have a public "create cache"
	// surface, so cache_write stays nil.
	if cw != nil {
		t.Errorf("cache_write = %v, want nil for OpenAI", *cw)
	}
}

// TestExtractOpenAIUsageFromBody_NoCacheDetails confirms cache_read
// is nil when the upstream omits prompt_tokens_details.
func TestExtractOpenAIUsageFromBody_NoCacheDetails(t *testing.T) {
	body := []byte(`{
		"id": "chatcmpl-1",
		"object": "chat.completion",
		"model": "gpt-4o",
		"choices": [],
		"usage": {
			"prompt_tokens": 100,
			"completion_tokens": 50,
			"total_tokens": 150
		}
	}`)
	pt, ct, cr, cw := extractOpenAIUsageFromBody(body)
	if pt == nil || *pt != 100 {
		t.Errorf("prompt_tokens = %v, want pointer to 100", pt)
	}
	if ct == nil || *ct != 50 {
		t.Errorf("completion_tokens = %v, want pointer to 50", ct)
	}
	if cr != nil {
		t.Errorf("cache_read = %v, want nil when prompt_tokens_details missing", *cr)
	}
	if cw != nil {
		t.Errorf("cache_write = %v, want nil for OpenAI", *cw)
	}
}
