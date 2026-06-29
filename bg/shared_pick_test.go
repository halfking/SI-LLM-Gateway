package bg

// shared_pick_test.go — unit tests for the credential probe model picker.
//
// Scope: the two pure functions extracted from PickProbeModelForCredential,
//   - pickFeaturedModelName (Priority 3a, 2026-06-29 featured-first)
//   - pickRandomCandidate   (Priority 3b, legacy random fallback)
//
// The DB-bound behaviour (manual pin, request_logs most-used, providers.domestic
// gating) is covered indirectly via end-to-end curl tests; this file only
// guarantees the algorithm is correct in isolation.
//
// 2026-06-29 audit: written to lock the featured-first contract so future
// refactors cannot regress the fix that avoids cold-model false negatives
// on the credential probe cycle.

import (
	"reflect"
	"sort"
	"testing"
)

func TestPickFeaturedModelName_EmptyInputs(t *testing.T) {
	if got := pickFeaturedModelName(nil, []string{"gpt-4o"}); got != "" {
		t.Errorf("empty available should yield \"\", got %q", got)
	}
	if got := pickFeaturedModelName([]featuredRow{
		{probeModel: "gpt-4o", candidateName: "gpt-4o"},
	}, nil); got != "" {
		t.Errorf("empty featured should yield \"\", got %q", got)
	}
	if got := pickFeaturedModelName([]featuredRow{}, []string{}); got != "" {
		t.Errorf("both empty should yield \"\", got %q", got)
	}
}

// Standardized-name happy path: candidate's standardized_name matches
// an entry in featured_models → return that candidate's probe_model.
func TestPickFeaturedModelName_StandardizedNameMatch(t *testing.T) {
	available := []featuredRow{
		{probeModel: "gpt-4o-2024-08-06", candidateName: "gpt-4o"},
		{probeModel: "gpt-4o-latest", candidateName: "gpt-4o"}, // duplicate name
		{probeModel: "deepseek-chat-pro", candidateName: "deepseek-chat"},
		{probeModel: "qwen-plus-latest", candidateName: "qwen-plus"},
	}
	featured := []string{"gpt-4o", "claude-3-5-sonnet-20241022", "deepseek-chat", "qwen-plus"}
	got := pickFeaturedModelName(available, featured)
	if got != "gpt-4o-2024-08-06" {
		t.Errorf("highest-priority featured match: got %q want \"gpt-4o-2024-08-06\" (lowest index wins, first occurrence on tie)", got)
	}
}

// Priority is driven by the position inside featured_models (lower = higher
// priority), not by the candidate's available order.
func TestPickFeaturedModelName_PriorityIsFeaturedOrder(t *testing.T) {
	available := []featuredRow{
		// qwen-plus is in the available list BEFORE gpt-4o, but
		// gpt-4o is earlier in the featured list.
		{probeModel: "qwen-plus-latest", candidateName: "qwen-plus"},
		{probeModel: "gpt-4o-2024-08-06", candidateName: "gpt-4o"},
	}
	featured := []string{"gpt-4o", "qwen-plus"}
	got := pickFeaturedModelName(available, featured)
	if got != "gpt-4o-2024-08-06" {
		t.Errorf("featured-list order should win over available order: got %q want \"gpt-4o-2024-08-06\"", got)
	}
}

// When no candidate_name is in featured_models, return "" so the caller
// falls back to the random Priority 3b path.
func TestPickFeaturedModelName_NoMatchReturnsEmpty(t *testing.T) {
	available := []featuredRow{
		{probeModel: "cold-model-A", candidateName: "cold-model-A"},
		{probeModel: "cold-model-B", candidateName: "cold-model-B"},
		{probeModel: "old-model-C", candidateName: "old-model-C"},
	}
	featured := []string{"gpt-4o", "claude-3-5-sonnet-20241022", "gemini-2.0-flash"}
	got := pickFeaturedModelName(available, featured)
	if got != "" {
		t.Errorf("no match: got %q want \"\" (caller will fall through to 3b random)", got)
	}
}

// Mixed scenario: only one of the available models is featured. The
// non-featured models must not influence the choice.
func TestPickFeaturedModelName_FiltersOutNonFeatured(t *testing.T) {
	available := []featuredRow{
		{probeModel: "cold-A", candidateName: "cold-A"},
		{probeModel: "deepseek-pro", candidateName: "deepseek-chat"},
		{probeModel: "cold-B", candidateName: "cold-B"},
		{probeModel: "cold-C", candidateName: "cold-C"},
	}
	featured := []string{"gpt-4o", "deepseek-chat", "qwen-plus"}
	got := pickFeaturedModelName(available, featured)
	if got != "deepseek-pro" {
		t.Errorf("only the featured candidate should win: got %q want \"deepseek-pro\"", got)
	}
}

// Defensive: duplicate names in featured_models should not produce duplicate
// priority entries (the first occurrence wins).
func TestPickFeaturedModelName_DuplicateFeaturedNames_HandledGracefully(t *testing.T) {
	available := []featuredRow{
		{probeModel: "gpt-4o-2024", candidateName: "gpt-4o"},
		{probeModel: "qwen-plus-latest", candidateName: "qwen-plus"},
	}
	// "gpt-4o" appears twice — the helper should still pick it (lowest
	// position index), not panic or loop.
	featured := []string{"gpt-4o", "qwen-plus", "gpt-4o"}
	got := pickFeaturedModelName(available, featured)
	if got != "gpt-4o-2024" {
		t.Errorf("duplicate featured name: got %q want \"gpt-4o-2024\" (first occurrence wins)", got)
	}
}

// pickRandomCandidate must return a member of the input slice.
func TestPickRandomCandidate_ReturnsMemberOfInput(t *testing.T) {
	cands := []string{"alpha", "beta", "gamma", "delta", "epsilon"}
	for _, salt := range []int64{0, 1, 2, 3, 4, 5, 17, 99, 1_000_000} {
		got := pickRandomCandidate(cands, salt)
		// Linear scan; the slice is tiny in tests.
		found := false
		for _, c := range cands {
			if c == got {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("salt=%d: got %q not in candidates %v", salt, got, cands)
		}
	}
}

// pickRandomCandidate must be deterministic for a given salt.
func TestPickRandomCandidate_DeterministicBySalt(t *testing.T) {
	cands := []string{"alpha", "beta", "gamma", "delta", "epsilon"}
	salts := []int64{0, 1, 2, 3, 4, 5, 17, 99, 1_000_000}
	for _, salt := range salts {
		first := pickRandomCandidate(cands, salt)
		second := pickRandomCandidate(cands, salt)
		if first != second {
			t.Errorf("salt=%d: pickRandomCandidate is non-deterministic (%q vs %q)", salt, first, second)
		}
	}
}

// pickRandomCandidate covers the slice evenly: for salts 0..N-1 the outputs
// are a permutation of the input. This guards against off-by-one modulo
// regressions (e.g. using len-1 in the divisor).
func TestPickRandomCandidate_FullCoverage(t *testing.T) {
	cands := []string{"alpha", "beta", "gamma", "delta", "epsilon"}
	seen := make(map[string]bool)
	for i := int64(0); i < int64(len(cands)); i++ {
		seen[pickRandomCandidate(cands, i)] = true
	}
	got := make([]string, 0, len(seen))
	for k := range seen {
		got = append(got, k)
	}
	sort.Strings(got)
	want := []string{"alpha", "beta", "delta", "epsilon", "gamma"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("full coverage: got %v want %v (every input should appear for salts 0..N-1)", got, want)
	}
}

func TestPickRandomCandidate_Empty(t *testing.T) {
	if got := pickRandomCandidate(nil, 42); got != "" {
		t.Errorf("empty candidates: got %q want \"\"", got)
	}
	if got := pickRandomCandidate([]string{}, 42); got != "" {
		t.Errorf("empty candidates (slice): got %q want \"\"", got)
	}
}

// Realistic production snapshot: the credential has 30+ models, of which
// exactly 3 are featured. The picker must always return one of the 3
// featured probe_models, never a cold one — the property the audit
// (2026-06-29) is meant to guarantee.
func TestPickFeaturedModelName_RealisticSnapshot(t *testing.T) {
	available := []featuredRow{
		// 3 featured
		{probeModel: "gpt-4o-2024", candidateName: "gpt-4o"},
		{probeModel: "claude-3-5-sonnet", candidateName: "claude-3-5-sonnet-20241022"},
		{probeModel: "deepseek-chat-pro", candidateName: "deepseek-chat"},
		// 27 cold
		{probeModel: "ft:gpt-4o:internal-A", candidateName: "ft:gpt-4o:internal-A"},
		{probeModel: "ft:gpt-4o:internal-B", candidateName: "ft:gpt-4o:internal-B"},
		{probeModel: "internal-eval-1", candidateName: "internal-eval-1"},
		{probeModel: "internal-eval-2", candidateName: "internal-eval-2"},
		{probeModel: "old-gpt-3.5-turbo", candidateName: "old-gpt-3.5-turbo"},
		// ... (truncated in this snapshot, but the pattern is clear)
		{probeModel: "embed-small", candidateName: "text-embedding-3-small"},
		{probeModel: "embed-large", candidateName: "text-embedding-3-large"},
		{probeModel: "whisper-1", candidateName: "whisper-1"},
		{probeModel: "dall-e-3", candidateName: "dall-e-3"},
		{probeModel: "ft:gpt-3.5:legacy-1", candidateName: "ft:gpt-3.5:legacy-1"},
		{probeModel: "ft:gpt-3.5:legacy-2", candidateName: "ft:gpt-3.5:legacy-2"},
		{probeModel: "ft:gpt-3.5:legacy-3", candidateName: "ft:gpt-3.5:legacy-3"},
		{probeModel: "moderation-stable", candidateName: "text-moderation-stable"},
		{probeModel: "moderation-latest", candidateName: "text-moderation-latest"},
		{probeModel: "babbage-002", candidateName: "babbage-002"},
		{probeModel: "davinci-002", candidateName: "davinci-002"},
		{probeModel: "ft:davinci:legacy-X", candidateName: "ft:davinci:legacy-X"},
		{probeModel: "ft:curie:legacy-Y", candidateName: "ft:curie:legacy-Y"},
		{probeModel: "summarization-1", candidateName: "summarization-1"},
		{probeModel: "search-query-1", candidateName: "search-query-1"},
		{probeModel: "search-doc-1", candidateName: "search-doc-1"},
		{probeModel: "search-babbage-1", candidateName: "search-babbage-1"},
		{probeModel: "code-search-babbage-1", candidateName: "code-search-babbage-1"},
		{probeModel: "code-search-babbage-001", candidateName: "code-search-babbage-001"},
		{probeModel: "gpt-3.5-turbo-instruct", candidateName: "gpt-3.5-turbo-instruct"},
		{probeModel: "gpt-3.5-turbo-0613", candidateName: "gpt-3.5-turbo-0613"},
		{probeModel: "ft:gpt-3.5:turbo-0613-Z", candidateName: "ft:gpt-3.5:turbo-0613-Z"},
	}
	featured := []string{"gpt-4o", "claude-3-5-sonnet-20241022", "deepseek-chat"}

	// Allowed set: the 3 featured probe_models.
	allowed := map[string]bool{
		"gpt-4o-2024":          true,
		"claude-3-5-sonnet":    true,
		"deepseek-chat-pro":    true,
	}
	// Run many trials; the picker should never return a cold model.
	for i := 0; i < 100; i++ {
		got := pickFeaturedModelName(available, featured)
		if !allowed[got] {
			t.Fatalf("trial %d: pickFeaturedModelName returned cold model %q (must be one of %v)",
				i, got, allowed)
		}
	}
}
