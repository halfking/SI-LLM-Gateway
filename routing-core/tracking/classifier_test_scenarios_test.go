package tracking

import (
	"testing"
	"time"
)

func TestScenario_OpenAI_AuthFailure(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   401,
		ErrorMessage: "Incorrect API key provided",
		ResponseBody: `{"error":{"message":"Incorrect API key provided: sk-xxxxx","type":"invalid_request_error"}}`,
		Upstream:     "openai",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "auth" {
		t.Errorf("Expected 'auth', got %s", result.Kind)
	}

	if result.Level != CredentialLevel {
		t.Error("Auth error should affect entire credential")
	}

	if result.Retryable {
		t.Error("Auth error should not be retryable")
	}

	if result.Cooldown != 5*time.Minute {
		t.Errorf("Expected 5min cooldown for quick re-probe, got %v", result.Cooldown)
	}
}

func TestScenario_Anthropic_QuotaExhausted(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   429,
		ErrorMessage: "Your credit balance is too low",
		ResponseBody: `{"error":{"type":"quota_exceeded","message":"insufficient credits remaining"}}`,
		Upstream:     "anthropic",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "quota" {
		t.Errorf("Expected 'quota', got %s", result.Kind)
	}

	if result.Cooldown != 0 {
		t.Error("Quota error should have 0 cooldown (needs manual intervention)")
	}

	if result.Retryable {
		t.Error("Quota error should not be retryable without manual action")
	}
}

func TestScenario_Azure_RateLimit(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   429,
		ErrorMessage: "Rate limit is exceeded",
		ResponseBody: `{"error":{"code":"429","message":"Requests to the ChatCompletions API have exceeded the rate limit"}}`,
		Headers: map[string]string{
			"Retry-After": "60",
		},
		Upstream: "azure",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "rate_limit" {
		t.Errorf("Expected 'rate_limit', got %s", result.Kind)
	}

	if result.Level != ModelLevel {
		t.Error("Rate limit should affect model level")
	}

	if !result.Retryable {
		t.Error("Rate limit should be retryable after cooldown")
	}

	if result.Cooldown != 15*time.Minute {
		t.Errorf("Expected 15min cooldown, got %v", result.Cooldown)
	}
}

func TestScenario_Timeout_SlowUpstream(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   504,
		ErrorMessage: "Gateway Timeout",
		ResponseBody: "upstream request timeout",
		Upstream:     "gemini",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "timeout" {
		t.Errorf("Expected 'timeout', got %s", result.Kind)
	}

	if !result.Retryable {
		t.Error("Timeout should be retryable")
	}

	if result.Cooldown != 30*time.Second {
		t.Errorf("Expected 30s cooldown, got %v", result.Cooldown)
	}
}

func TestScenario_ModelNotAvailable(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   404,
		ErrorMessage: "Model not found",
		ResponseBody: `{"error":"The model 'gpt-5' does not exist or you do not have access"}`,
		Upstream:     "openai",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "model_not_found" {
		t.Errorf("Expected 'model_not_found', got %s", result.Kind)
	}

	if result.Cooldown != 24*time.Hour {
		t.Errorf("Expected 24h cooldown, got %v", result.Cooldown)
	}

	if result.Retryable {
		t.Error("Model not found should not be retryable")
	}
}

func TestScenario_UpstreamMaintenance(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   503,
		ErrorMessage: "Service Temporarily Unavailable",
		ResponseBody: "The service is undergoing maintenance",
		Upstream:     "openai",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "upstream_down" {
		t.Errorf("Expected 'upstream_down', got %s", result.Kind)
	}

	if result.Cooldown != 1*time.Minute {
		t.Errorf("Expected 1min cooldown, got %v", result.Cooldown)
	}

	if !result.Retryable {
		t.Error("Upstream down should be retryable")
	}
}

func TestScenario_ContentPolicyViolation(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   400,
		ErrorMessage: "Content policy violation",
		ResponseBody: `{"error":{"message":"Your request was rejected as a result of our safety system","type":"content_filter"}}`,
		Upstream:     "openai",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "content_filter" {
		t.Errorf("Expected 'content_filter', got %s", result.Kind)
	}

	if result.Level != RequestLevel {
		t.Error("Content filter should only affect request level")
	}

	if result.Retryable {
		t.Error("Content filter error should not be retryable")
	}
}

func TestScenario_ContextLengthExceeded(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   400,
		ErrorMessage: "This model's maximum context length is 16385 tokens",
		ResponseBody: `{"error":{"message":"context_length_exceeded","type":"invalid_request_error"}}`,
		Upstream:     "openai",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "context_length" {
		t.Errorf("Expected 'context_length', got %s", result.Kind)
	}

	if result.Level != RequestLevel {
		t.Error("Context length should only affect request level")
	}

	if result.Retryable {
		t.Error("Context length error should not be retryable without modification")
	}
}

func TestScenario_TransientNetworkError(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   502,
		ErrorMessage: "Bad Gateway",
		ResponseBody: "Error connecting to upstream",
		Upstream:     "azure",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "upstream_down" {
		t.Errorf("Expected 'upstream_down', got %s", result.Kind)
	}

	if !result.Retryable {
		t.Error("Network error should be retryable")
	}
}

func TestScenario_InvalidParameter(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   400,
		ErrorMessage: "Invalid parameter: temperature must be between 0 and 2",
		ResponseBody: `{"error":{"message":"temperature: must be >= 0.0","type":"invalid_request_error"}}`,
		Upstream:     "openai",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "invalid_request" {
		t.Errorf("Expected 'invalid_request', got %s", result.Kind)
	}

	if result.Level != RequestLevel {
		t.Error("Invalid parameter should only affect request level")
	}
}

func TestScenario_MultipleErrorKeywords(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   429,
		ErrorMessage: "Rate limit exceeded, insufficient quota remaining",
		ResponseBody: "Your account balance is low and rate throttling is active",
		Upstream:     "openai",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "quota" {
		t.Errorf("Expected 'quota' (higher priority), got %s", result.Kind)
	}
}

func TestScenario_UnknownProvider500(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   500,
		ErrorMessage: "Internal Server Error",
		ResponseBody: "An unexpected error occurred",
		Upstream:     "unknown_provider",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "network" {
		t.Errorf("Expected 'network', got %s", result.Kind)
	}

	if !result.Retryable {
		t.Error("500 error should be retryable")
	}
}

func TestScenario_StateManagerIntegration(t *testing.T) {
	classifier := NewErrorClassifier()

	testCases := []struct {
		name          string
		input         ClassifyInput
		expectedKind  string
		expectedLevel ErrorLevel
	}{
		{
			name: "Auth affects credential",
			input: ClassifyInput{
				StatusCode:   401,
				ErrorMessage: "invalid api key",
			},
			expectedKind:  "auth",
			expectedLevel: CredentialLevel,
		},
		{
			name: "Rate limit affects model",
			input: ClassifyInput{
				StatusCode:   429,
				ErrorMessage: "rate limit",
			},
			expectedKind:  "rate_limit",
			expectedLevel: ModelLevel,
		},
		{
			name: "Invalid request affects request only",
			input: ClassifyInput{
				StatusCode:   400,
				ErrorMessage: "invalid parameter",
			},
			expectedKind:  "invalid_request",
			expectedLevel: RequestLevel,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result, err := classifier.Classify(tc.input)
			if err != nil {
				t.Fatalf("Unexpected error: %v", err)
			}

			if result.Kind != tc.expectedKind {
				t.Errorf("Expected kind %s, got %s", tc.expectedKind, result.Kind)
			}

			if result.Level != tc.expectedLevel {
				t.Errorf("Expected level %v, got %v", tc.expectedLevel, result.Level)
			}
		})
	}
}
