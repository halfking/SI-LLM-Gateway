package modelcatalog

import (
	"testing"
)

func TestPreserveManualDisable(t *testing.T) {
	manual := "manual"
	auto := "auto_probe_failed"
	deleted := "deleted"

	tests := []struct {
		name     string
		avail    bool
		reason   *string
		preserve bool
	}{
		{"manual disabled", false, &manual, true},
		{"manual prefix variant", false, strPtr("manual_admin"), true},
		{"deleted legacy soft clear", false, &deleted, false},
		{"auto disabled", false, &auto, false},
		{"available with reason", true, &manual, false},
		{"available no reason", true, nil, false},
		{"disabled no reason", false, nil, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := PreserveManualDisable(tt.avail, tt.reason)
			if got != tt.preserve {
				t.Fatalf("PreserveManualDisable(%v, %v) = %v, want %v", tt.avail, tt.reason, got, tt.preserve)
			}
		})
	}
}

func strPtr(s string) *string { return &s }

// TestUpsertCredentialModelSQL_DerivesBillingMode is a static-string
// regression test for the 2026-07-03 minimax-m3 incident follow-up
// (request a69a71a05e6610adcf55df32f2618797): a brand-new cmb row
// inserted via discovery.UpsertCredentialModel must derive its
// billing_mode from credentials.plan_type (CASE WHEN plan_type =
// 'token_plan' THEN 'token_plan' ...), instead of falling back to the
// cmb column DEFAULT 'per_token' (which would trigger the
// v_routable_credential_models plan_incompatible clause and mark the
// binding non-routable).
//
// We assert on the SQL string itself rather than a live pgxmock
// roundtrip — the SQL is the contract surface that matters here, and a
// string assertion is more robust than wiring a mock just to re-read
// the same SQL.
func TestUpsertCredentialModelSQL_DerivesBillingMode(t *testing.T) {
	for _, want := range []string{
		"'token_plan'",
		"'code_plan'",
		"'agent_plan'",
		// Non-subscription creds land on 'token' (the cmb column DEFAULT
		// 'per_token' is wrong, but per_token is also not on the view's
		// allow-list; we prefer 'token' for non-plan creds).
		"'token'",
	} {
		if !contains(upsertCredentialModelSQL, want) {
			t.Errorf("upsertCredentialModelSQL missing %q for plan-type derivation", want)
		}
	}
	if contains(upsertCredentialModelSQL, "billing_mode = 'per_token'") {
		t.Error("upsertCredentialModelSQL must NOT hardcode billing_mode='per_token'")
	}
	if !contains(upsertCredentialModelSQL, "WHEN 'token_plan' THEN 'token_plan'") {
		t.Error("upsertCredentialModelSQL must have plan_type->token_plan mapping")
	}
}

func contains(s, sub string) bool {
	return len(sub) == 0 || (len(s) >= len(sub) && indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
