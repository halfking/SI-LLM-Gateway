package tracking

import (
	"fmt"
	"regexp"
	"strings"
	"sync"
	"time"
)

type ErrorLevel int

const (
	CredentialLevel ErrorLevel = iota
	ModelLevel
	RequestLevel
)

type ErrorClassifier interface {
	Classify(input ClassifyInput) (*ClassifiedError, error)
	RegisterRule(rule ClassificationRule) error
	GetSuggestions(errorKind string) []string
}

type ClassifyInput struct {
	StatusCode   int
	ErrorMessage string
	ResponseBody string
	Headers      map[string]string
	Upstream     string
}

type ClassifiedError struct {
	Kind        string
	Level       ErrorLevel
	Cooldown    time.Duration
	Retryable   bool
	Detail      string
	Suggestions []string
	Confidence  float64
}

type ClassificationRule struct {
	Name         string
	Priority     int
	Pattern      *regexp.Regexp
	StatusCodes  []int
	Keywords     []string
	UpstreamHint string
	Kind         string
	Level        ErrorLevel
	Cooldown     time.Duration
	Retryable    bool
	Suggestions  []string
}

type classifier struct {
	rules []ClassificationRule
	mu    sync.RWMutex
}

func NewErrorClassifier() ErrorClassifier {
	c := &classifier{
		rules: make([]ClassificationRule, 0),
	}
	c.loadBuiltinRules()
	return c
}

func (c *classifier) Classify(input ClassifyInput) (*ClassifiedError, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	var bestMatch *ClassificationRule
	var confidence float64

	for i := range c.rules {
		rule := &c.rules[i]

		if rule.UpstreamHint != "" && rule.UpstreamHint != input.Upstream {
			continue
		}

		score := c.matchRule(rule, input)
		if score > confidence {
			confidence = score
			bestMatch = rule
		}
	}

	if bestMatch == nil {
		return &ClassifiedError{
			Kind:        "unknown",
			Level:       RequestLevel,
			Cooldown:    0,
			Retryable:   false,
			Detail:      "No matching classification rule",
			Suggestions: []string{"Check error logs for details"},
			Confidence:  0.0,
		}, nil
	}

	return &ClassifiedError{
		Kind:        bestMatch.Kind,
		Level:       bestMatch.Level,
		Cooldown:    bestMatch.Cooldown,
		Retryable:   bestMatch.Retryable,
		Detail:      c.buildDetail(bestMatch, input),
		Suggestions: bestMatch.Suggestions,
		Confidence:  confidence,
	}, nil
}

func (c *classifier) matchRule(rule *ClassificationRule, input ClassifyInput) float64 {
	score := 0.0
	maxScore := 0.0

	statusMatch := false
	if len(rule.StatusCodes) > 0 {
		maxScore += 1.0
		for _, code := range rule.StatusCodes {
			if code == input.StatusCode {
				score += 1.0
				statusMatch = true
				break
			}
		}
	}

	keywordMatch := false
	if len(rule.Keywords) > 0 {
		maxScore += 1.0
		matchedKeywords := 0
		searchText := strings.ToLower(input.ErrorMessage + " " + input.ResponseBody)

		for _, keyword := range rule.Keywords {
			if strings.Contains(searchText, strings.ToLower(keyword)) {
				matchedKeywords++
			}
		}

		if matchedKeywords > 0 {
			score += float64(matchedKeywords) / float64(len(rule.Keywords))
			keywordMatch = true
		}
	}

	patternMatch := false
	if rule.Pattern != nil {
		maxScore += 1.0
		searchText := input.ErrorMessage + " " + input.ResponseBody
		if rule.Pattern.MatchString(searchText) {
			score += 1.0
			patternMatch = true
		}
	}

	if maxScore == 0 {
		return 0.0
	}

	if !statusMatch && !keywordMatch && !patternMatch {
		return 0.0
	}

	priorityBoost := float64(rule.Priority) / 100.0
	return (score / maxScore) + priorityBoost
}

func (c *classifier) buildDetail(rule *ClassificationRule, input ClassifyInput) string {
	return fmt.Sprintf("Matched rule: %s, Status: %d", rule.Name, input.StatusCode)
}

func (c *classifier) RegisterRule(rule ClassificationRule) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if rule.Name == "" {
		return fmt.Errorf("rule name cannot be empty")
	}

	c.rules = append(c.rules, rule)
	c.sortRulesByPriority()
	return nil
}

func (c *classifier) sortRulesByPriority() {
	for i := 0; i < len(c.rules)-1; i++ {
		for j := i + 1; j < len(c.rules); j++ {
			if c.rules[j].Priority > c.rules[i].Priority {
				c.rules[i], c.rules[j] = c.rules[j], c.rules[i]
			}
		}
	}
}

func (c *classifier) GetSuggestions(errorKind string) []string {
	c.mu.RLock()
	defer c.mu.RUnlock()

	for _, rule := range c.rules {
		if rule.Kind == errorKind {
			return rule.Suggestions
		}
	}

	return []string{"No specific suggestions available"}
}

func (c *classifier) loadBuiltinRules() {
	builtinRules := getBuiltinRules()
	c.rules = append(c.rules, builtinRules...)
	c.sortRulesByPriority()
}
