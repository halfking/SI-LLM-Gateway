package discovery

import (
	"regexp"
	"strings"
)

// NormalizeModelName standardizes a model name by removing dates, vendor prefixes,
// and other non-essential parts. The goal is to produce clean, consistent names
// like "glm-5.1", "glm-4.7-flash", "gpt-4o", "claude-sonnet-4".
func NormalizeModelName(raw string) string {
	if raw == "" {
		return raw
	}

	// Remove vendor prefixes (e.g., "zai/", "openai/", "anthropic/")
	if idx := strings.LastIndex(raw, "/"); idx >= 0 {
		raw = raw[idx+1:]
	}

	// Remove date suffixes (e.g., "-20251201", "-20241022", "-20250219")
	datePattern := regexp.MustCompile(`[-_]\d{8}[-_]?`)
	raw = datePattern.ReplaceAllString(raw, "")

	// Remove version-like date patterns (e.g., "-2025-12-01")
	datePattern2 := regexp.MustCompile(`[-_]\d{4}-\d{2}-\d{2}[-_]?`)
	raw = datePattern2.ReplaceAllString(raw, "")

	// Remove preview/beta/rc suffixes that clutter names
	// But keep them if they're part of the model identity (like "gpt-4o-mini")
	suffixPattern := regexp.MustCompile(`[-_](preview|beta|rc|snapshot|latest|stable)([-_]\d+)?$`)
	raw = suffixPattern.ReplaceAllString(raw, "")

	// Clean up multiple dashes/underscores
	cleanPattern := regexp.MustCompile(`[-_]{2,}`)
	raw = cleanPattern.ReplaceAllString(raw, "-")

	// Trim leading/trailing dashes
	raw = strings.Trim(raw, "-_")

	// Normalize to lowercase
	raw = strings.ToLower(raw)

	return raw
}

// InferFamily determines the model family from a normalized model name.
func InferFamily(name string) string {
	name = strings.ToLower(name)

	familyPatterns := map[string][]string{
		"anthropic-claude": {"claude"},
		"openai-gpt":       {"gpt-4", "gpt-3", "o1", "o3", "o4"},
		"openai-dall-e":    {"dall-e"},
		"google-gemini":    {"gemini"},
		"deepseek":         {"deepseek"},
		"qwen":             {"qwen"},
		"zhipu-glm":        {"glm"},
		"doubao":           {"doubao", "seed"},
		"meta-llama":       {"llama"},
		"minimax":          {"minimax"},
		"mistral":          {"mistral", "mixtral"},
		"yi":               {"yi-"},
		"moonshot":         {"moonshot", "kimi"},
		"baichuan":         {"baichuan"},
		"internlm":         {"internlm", "intern"},
		"mimo":             {"mimo"},
	}

	for family, patterns := range familyPatterns {
		for _, p := range patterns {
			if strings.Contains(name, p) {
				return family
			}
		}
	}

	// Default: use first segment
	parts := strings.Split(name, "-")
	if len(parts) > 0 {
		return parts[0]
	}
	return "unknown"
}

// GenerateAliases produces alternative names for a model to improve matching.
func GenerateAliases(rawName, canonicalName string) []string {
	seen := make(map[string]bool)
	var aliases []string

	addAlias := func(name string) {
		name = strings.TrimSpace(name)
		if name == "" {
			return
		}
		name = strings.ToLower(name)
		if !seen[name] {
			seen[name] = true
			aliases = append(aliases, name)
		}
	}

	// Add the raw name
	addAlias(rawName)

	// Add canonical name
	addAlias(canonicalName)

	// Add without vendor prefix
	if idx := strings.LastIndex(rawName, "/"); idx >= 0 {
		addAlias(rawName[idx+1:])
	}

	// Add with underscores replaced by dashes
	addAlias(strings.ReplaceAll(rawName, "_", "-"))

	// Add with dashes replaced by underscores
	addAlias(strings.ReplaceAll(rawName, "-", "_"))

	// For GLM models, add variants
	if strings.Contains(strings.ToLower(rawName), "glm") {
		// glm-4.7 -> glm-4-7, glm47
		variant := strings.ReplaceAll(canonicalName, ".", "-")
		addAlias(variant)
		variant2 := strings.ReplaceAll(canonicalName, ".", "")
		addAlias(variant2)
		variant3 := strings.ReplaceAll(canonicalName, "-", ".")
		addAlias(variant3)
	}

	return aliases
}
