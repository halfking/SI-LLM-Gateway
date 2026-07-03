package tracking

import (
	"regexp"
	"testing"
	"time"
)

func TestNewErrorClassifier(t *testing.T) {
	classifier := NewErrorClassifier()
	if classifier == nil {
		t.Fatal("Expected classifier to be non-nil")
	}
}

func TestClassify_AuthError(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   401,
		ErrorMessage: "unauthorized access",
		ResponseBody: "invalid API key",
		Upstream:     "openai",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "auth" {
		t.Errorf("Expected kind 'auth', got %s", result.Kind)
	}

	if result.Level != CredentialLevel {
		t.Errorf("Expected CredentialLevel, got %v", result.Level)
	}

	if result.Cooldown != 5*time.Minute {
		t.Errorf("Expected 5min cooldown, got %v", result.Cooldown)
	}

	if result.Retryable {
		t.Error("Expected auth error to be non-retryable")
	}

	if result.Confidence <= 0 {
		t.Errorf("Expected positive confidence, got %f", result.Confidence)
	}
}

func TestClassify_QuotaError(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   429,
		ErrorMessage: "quota exceeded",
		ResponseBody: "insufficient balance",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "quota" {
		t.Errorf("Expected kind 'quota', got %s", result.Kind)
	}

	if result.Cooldown != 0 {
		t.Errorf("Expected 0 cooldown, got %v", result.Cooldown)
	}

	if result.Retryable {
		t.Error("Expected quota error to be non-retryable")
	}
}

func TestClassify_RateLimit(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   429,
		ErrorMessage: "rate limit exceeded",
		ResponseBody: "too many requests",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "rate_limit" {
		t.Errorf("Expected kind 'rate_limit', got %s", result.Kind)
	}

	if result.Level != ModelLevel {
		t.Errorf("Expected ModelLevel, got %v", result.Level)
	}

	if result.Cooldown != 15*time.Minute {
		t.Errorf("Expected 15min cooldown, got %v", result.Cooldown)
	}

	if !result.Retryable {
		t.Error("Expected rate limit to be retryable")
	}
}

func TestClassify_Timeout(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   504,
		ErrorMessage: "gateway timeout",
		ResponseBody: "request timed out",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "timeout" {
		t.Errorf("Expected kind 'timeout', got %s", result.Kind)
	}

	if result.Cooldown != 30*time.Second {
		t.Errorf("Expected 30s cooldown, got %v", result.Cooldown)
	}

	if !result.Retryable {
		t.Error("Expected timeout to be retryable")
	}
}

func TestClassify_ModelNotFound(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   404,
		ErrorMessage: "model not found",
		ResponseBody: "the model does not exist",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "model_not_found" {
		t.Errorf("Expected kind 'model_not_found', got %s", result.Kind)
	}

	if result.Cooldown != 24*time.Hour {
		t.Errorf("Expected 24h cooldown, got %v", result.Cooldown)
	}

	if result.Retryable {
		t.Error("Expected model_not_found to be non-retryable")
	}
}

func TestClassify_UpstreamDown(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   503,
		ErrorMessage: "service unavailable",
		ResponseBody: "upstream server maintenance",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "upstream_down" {
		t.Errorf("Expected kind 'upstream_down', got %s", result.Kind)
	}

	if result.Cooldown != 1*time.Minute {
		t.Errorf("Expected 1min cooldown, got %v", result.Cooldown)
	}

	if !result.Retryable {
		t.Error("Expected upstream_down to be retryable")
	}
}

func TestClassify_NetworkError(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   500,
		ErrorMessage: "internal server error",
		ResponseBody: "network connection failed",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "network" {
		t.Errorf("Expected kind 'network', got %s", result.Kind)
	}

	if result.Cooldown != 2*time.Minute {
		t.Errorf("Expected 2min cooldown, got %v", result.Cooldown)
	}

	if !result.Retryable {
		t.Error("Expected network error to be retryable")
	}
}

func TestClassify_UnknownError(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   418,
		ErrorMessage: "xyzabc qwerty foobar",
		ResponseBody: "completely unrecognized response",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "unknown" {
		t.Errorf("Expected kind 'unknown', got %s", result.Kind)
	}

	if result.Retryable {
		t.Error("Expected unknown error to be non-retryable")
	}

	if result.Confidence != 0.0 {
		t.Errorf("Expected 0 confidence, got %f", result.Confidence)
	}
}

func TestClassify_PriorityOrdering(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   429,
		ErrorMessage: "quota exceeded and rate limit",
		ResponseBody: "both quota and rate keywords",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "quota" {
		t.Errorf("Expected 'quota' (higher priority), got %s", result.Kind)
	}
}

func TestRegisterRule(t *testing.T) {
	classifier := NewErrorClassifier()

	customRule := ClassificationRule{
		Name:        "custom_error",
		Priority:    110,
		StatusCodes: []int{418},
		Keywords:    []string{"teapot"},
		Kind:        "custom",
		Level:       RequestLevel,
		Cooldown:    10 * time.Second,
		Retryable:   true,
		Suggestions: []string{"Use a coffee pot instead"},
	}

	err := classifier.RegisterRule(customRule)
	if err != nil {
		t.Fatalf("Unexpected error registering rule: %v", err)
	}

	input := ClassifyInput{
		StatusCode:   418,
		ErrorMessage: "I'm a teapot",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "custom" {
		t.Errorf("Expected kind 'custom', got %s", result.Kind)
	}
}

func TestRegisterRule_EmptyName(t *testing.T) {
	classifier := NewErrorClassifier()

	invalidRule := ClassificationRule{
		Name:     "",
		Priority: 50,
	}

	err := classifier.RegisterRule(invalidRule)
	if err == nil {
		t.Error("Expected error for empty rule name")
	}
}

func TestGetSuggestions(t *testing.T) {
	classifier := NewErrorClassifier()

	suggestions := classifier.GetSuggestions("auth")
	if len(suggestions) == 0 {
		t.Error("Expected non-empty suggestions for auth error")
	}

	found := false
	for _, s := range suggestions {
		if s == "Check API key validity" {
			found = true
			break
		}
	}

	if !found {
		t.Error("Expected 'Check API key validity' in auth suggestions")
	}
}

func TestGetSuggestions_UnknownKind(t *testing.T) {
	classifier := NewErrorClassifier()

	suggestions := classifier.GetSuggestions("nonexistent")
	if len(suggestions) != 1 || suggestions[0] != "No specific suggestions available" {
		t.Errorf("Expected default suggestion for unknown kind, got %v", suggestions)
	}
}

func TestClassify_WithRegexPattern(t *testing.T) {
	classifier := NewErrorClassifier()

	pattern := regexp.MustCompile(`(?i)api[_\s]key[_\s]invalid`)
	customRule := ClassificationRule{
		Name:        "regex_auth",
		Priority:    105,
		Pattern:     pattern,
		Kind:        "regex_auth",
		Level:       CredentialLevel,
		Cooldown:    3 * time.Minute,
		Retryable:   false,
		Suggestions: []string{"Regex matched"},
	}

	err := classifier.RegisterRule(customRule)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	input := ClassifyInput{
		StatusCode:   401,
		ErrorMessage: "API_KEY_INVALID detected",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "regex_auth" {
		t.Errorf("Expected kind 'regex_auth', got %s", result.Kind)
	}
}

func TestClassify_UpstreamHint(t *testing.T) {
	classifier := NewErrorClassifier()

	upstreamRule := ClassificationRule{
		Name:         "openai_specific",
		Priority:     120,
		StatusCodes:  []int{429},
		UpstreamHint: "openai",
		Kind:         "openai_rate",
		Level:        ModelLevel,
		Cooldown:     20 * time.Minute,
		Retryable:    true,
	}

	err := classifier.RegisterRule(upstreamRule)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	inputMatch := ClassifyInput{
		StatusCode: 429,
		Upstream:   "openai",
	}

	resultMatch, err := classifier.Classify(inputMatch)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if resultMatch.Kind != "openai_rate" {
		t.Errorf("Expected 'openai_rate', got %s", resultMatch.Kind)
	}

	inputNoMatch := ClassifyInput{
		StatusCode: 429,
		Upstream:   "anthropic",
	}

	resultNoMatch, err := classifier.Classify(inputNoMatch)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if resultNoMatch.Kind == "openai_rate" {
		t.Error("Expected different kind for non-matching upstream")
	}
}

func TestClassify_ConfidenceScoring(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   401,
		ErrorMessage: "unauthorized invalid_api_key authentication failed",
		ResponseBody: "forbidden access denied",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Confidence < 1.0 {
		t.Errorf("Expected high confidence (>= 1.0) for strong match, got %f", result.Confidence)
	}
}

func TestClassify_PartialKeywordMatch(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   429,
		ErrorMessage: "rate limit warning",
		ResponseBody: "",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "rate_limit" {
		t.Errorf("Expected 'rate_limit' with partial match, got %s", result.Kind)
	}

	if result.Confidence <= 0 {
		t.Errorf("Expected positive confidence for partial match, got %f", result.Confidence)
	}
}

func TestClassify_ContentFilter(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   400,
		ErrorMessage: "content_filter triggered",
		ResponseBody: "safety moderation policy violation",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "content_filter" {
		t.Errorf("Expected kind 'content_filter', got %s", result.Kind)
	}

	if result.Level != RequestLevel {
		t.Errorf("Expected RequestLevel, got %v", result.Level)
	}
}

func TestClassify_ContextLength(t *testing.T) {
	classifier := NewErrorClassifier()

	input := ClassifyInput{
		StatusCode:   400,
		ErrorMessage: "context_length exceeded",
		ResponseBody: "max_tokens limit reached",
	}

	result, err := classifier.Classify(input)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if result.Kind != "context_length" {
		t.Errorf("Expected kind 'context_length', got %s", result.Kind)
	}
}

func TestBuiltinRulesCount(t *testing.T) {
	rules := getBuiltinRules()

	if len(rules) < 8 {
		t.Errorf("Expected at least 8 builtin rules, got %d", len(rules))
	}

	priorityMap := make(map[int]bool)
	for _, rule := range rules {
		if priorityMap[rule.Priority] {
			t.Errorf("Duplicate priority %d found", rule.Priority)
		}
		priorityMap[rule.Priority] = true
	}
}

func TestConcurrentClassify(t *testing.T) {
	classifier := NewErrorClassifier()

	done := make(chan bool, 10)

	for i := 0; i < 10; i++ {
		go func() {
			input := ClassifyInput{
				StatusCode:   401,
				ErrorMessage: "concurrent test",
			}

			_, err := classifier.Classify(input)
			if err != nil {
				t.Errorf("Concurrent classify failed: %v", err)
			}
			done <- true
		}()
	}

	for i := 0; i < 10; i++ {
		<-done
	}
}
