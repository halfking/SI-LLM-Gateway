package provider

import "testing"

// 2026-07-03 v738 regression guard.
//
// Bug history:
//   The 2026-07-02 commit 45f4d791 wired InvalidateAllCandidateCache() into
//   the admin disable handlers so the candCache (5s TTL) drops on toggle.
//   That fix prevented stale-candidate routing for at most 5s after a
//   disable — but the underlying SQL (provider/client.go
//   loadCandidatesDBWithThreshold) and the underlying view
//   (v_routable_credential_models.is_routable) were not in sync with each
//   other on the manual_disabled flag. The view did not JOIN providers and
//   the SQL relied solely on v.is_routable = TRUE, so a manually-disabled
//   provider's credentials kept showing as routable in cold-cache reads
//   (the v733 cache invalidation only addressed the *cache* staleness,
//   not the source-of-truth bug).
//
// This file locks in the v738 fix at the Go struct level so any future
// regression that silently flips ProviderManualDisabled off the Candidate
// struct, or reorders the UnavailableReason branches, is caught here.

// TestCandidate_UnavailableReason_ProviderManualDisabled asserts the
// provider-level gate is the dominant reason, ordered before the
// credential-level gate, and before the generic v.is_routable block.
// Matches admin/routing.go handleRoutingResolve BlockReason precedence
// at routing.go:324 ("provider_manual_disabled" first, then
// "credential_manual_disabled", then "not_in_routable_view").
func TestCandidate_UnavailableReason_ProviderManualDisabled(t *testing.T) {
	c := Candidate{
		Routable:                true, // view might still report true if the view migration is missing
		LifecycleStatus:         "active",
		AvailabilityState:       "ready",
		QuotaState:              "ok",
		ProviderManualDisabled:  true,
		CredentialManualDisabled: false,
	}
	if got := c.UnavailableReason(); got != "routing_blocked:provider_manual_disabled" {
		t.Fatalf("provider_manual_disabled: expected routing_blocked:provider_manual_disabled, got %q", got)
	}
	if c.IsAvailable() {
		t.Fatalf("provider_manual_disabled candidate must NOT be IsAvailable()")
	}
}

// TestCandidate_UnavailableReason_CredentialManualDisabled asserts the
// credential-level gate fires when the provider is fine but the
// credential itself was disabled.
func TestCandidate_UnavailableReason_CredentialManualDisabled(t *testing.T) {
	c := Candidate{
		Routable:                true,
		LifecycleStatus:         "active",
		AvailabilityState:       "ready",
		QuotaState:              "ok",
		ProviderManualDisabled:  false,
		CredentialManualDisabled: true,
	}
	if got := c.UnavailableReason(); got != "routing_blocked:credential_manual_disabled" {
		t.Fatalf("credential_manual_disabled: expected routing_blocked:credential_manual_disabled, got %q", got)
	}
	if c.IsAvailable() {
		t.Fatalf("credential_manual_disabled candidate must NOT be IsAvailable()")
	}
}

// TestCandidate_UnavailableReason_BothDisabled_ProviderWins locks in the
// precedence: when both flags are set, the provider reason wins. Mirrors
// admin/routing.go handleRoutingResolve BlockReason ordering. A
// regression that flips the order would surface to operators as
// "credential_manual_disabled" even when the provider is the dominant
// reason, hiding the real fix action.
func TestCandidate_UnavailableReason_BothDisabled_ProviderWins(t *testing.T) {
	c := Candidate{
		Routable:                 true,
		LifecycleStatus:          "active",
		AvailabilityState:        "ready",
		QuotaState:               "ok",
		ProviderManualDisabled:   true,
		CredentialManualDisabled: true,
	}
	if got := c.UnavailableReason(); got != "routing_blocked:provider_manual_disabled" {
		t.Fatalf("both disabled: expected provider reason first, got %q", got)
	}
}

// TestCandidate_UnavailableReason_HealthyUnaffected asserts the v738
// patches do not regress the healthy path: a candidate with no flags
// and an active lifecycle must still report "" (available) so the
// router picks it.
func TestCandidate_UnavailableReason_HealthyUnaffected(t *testing.T) {
	c := Candidate{
		Routable:                true,
		LifecycleStatus:         "active",
		AvailabilityState:       "ready",
		QuotaState:              "ok",
		ProviderManualDisabled:  false,
		CredentialManualDisabled: false,
	}
	if got := c.UnavailableReason(); got != "" {
		t.Fatalf("healthy candidate: expected empty reason, got %q", got)
	}
	if !c.IsAvailable() {
		t.Fatalf("healthy candidate must be IsAvailable()")
	}
}

// TestCandidate_UnavailableReason_ProviderManualDisabledBeatsNotRoutable
// asserts the manual_disabled branches win over the v.is_routable=FALSE
// fallback path. A regression that reorders the branches so the generic
// "routing_blocked:not_in_routable_view" is returned for a
// provider_manual_disabled candidate would mask the real reason in
// admin/credentials-monitor alerts.
func TestCandidate_UnavailableReason_ProviderManualDisabledBeatsNotRoutable(t *testing.T) {
	c := Candidate{
		Routable:               false, // view also reports false (consistent state)
		BlockReason:            stringPtrForTest("not_in_routable_view"),
		LifecycleStatus:        "active",
		ProviderManualDisabled: true,
	}
	if got := c.UnavailableReason(); got != "routing_blocked:provider_manual_disabled" {
		t.Fatalf("manual_disabled must beat generic not_in_routable_view; got %q", got)
	}
}

func stringPtrForTest(s string) *string { return &s }