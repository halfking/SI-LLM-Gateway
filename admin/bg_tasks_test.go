package admin

import (
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// helper to make a *int64 from a literal
func i64ptr(v int64) *int64 { return &v }

func TestDetectBackgroundTaskIDMismatch_Match(t *testing.T) {
	req := map[string]any{
		"provider_id":   float64(14),
		"credential_id": float64(6),
	}
	topPID := i64ptr(int64(14))
	topCID := i64ptr(int64(6))
	if m, ok := detectBackgroundTaskIDMismatch(40, "health_check", topPID, topCID, req); ok {
		t.Fatalf("expected no mismatch, got %+v", m)
	}
}

func TestDetectBackgroundTaskIDMismatch_ProviderMismatch(t *testing.T) {
	// Reproduces the user-reported scenario: top-level says provider=32,
	// request_json says provider=32 but credential_id differs.
	req := map[string]any{
		"provider_id":   float64(32),
		"credential_id": float64(2),
	}
	topPID := i64ptr(int64(32))
	topCID := i64ptr(int64(7))
	m, ok := detectBackgroundTaskIDMismatch(40, "health_check", topPID, topCID, req)
	if !ok {
		t.Fatalf("expected a mismatch to be detected")
	}
	if m["top_credential_id"].(*int64) == nil || *m["top_credential_id"].(*int64) != 7 {
		t.Errorf("top_credential_id not echoed correctly: %+v", m["top_credential_id"])
	}
	if m["request_credential_id"].(*int64) == nil || *m["request_credential_id"].(*int64) != 2 {
		t.Errorf("request_credential_id not echoed correctly: %+v", m["request_credential_id"])
	}
	if m["task_id"].(int64) != 40 || m["task_type"].(string) != "health_check" {
		t.Errorf("task metadata missing: %+v", m)
	}
}

func TestDetectBackgroundTaskIDMismatch_BothMismatch(t *testing.T) {
	req := map[string]any{
		"provider_id":   float64(14),
		"credential_id": float64(6),
	}
	topPID := i64ptr(int64(32))
	topCID := i64ptr(int64(7))
	if _, ok := detectBackgroundTaskIDMismatch(99, "health_check", topPID, topCID, req); !ok {
		t.Fatalf("expected mismatch when both IDs differ")
	}
}

func TestDetectBackgroundTaskIDMismatch_MissingKeys(t *testing.T) {
	// request_json doesn't have provider_id/credential_id at all (e.g. a
	// diagnose row) — we don't fabricate a mismatch, we just pass.
	req := map[string]any{"source": "auto_on_create"}
	topPID := i64ptr(int64(14))
	topCID := i64ptr(int64(6))
	if _, ok := detectBackgroundTaskIDMismatch(1, "health_check", topPID, topCID, req); ok {
		t.Fatalf("expected no mismatch when keys are missing")
	}
}

func TestDetectBackgroundTaskIDMismatch_NilTopButPresentReq(t *testing.T) {
	// A diagnose task has top-level credential_id = NULL. If request_json
	// somehow has a credential_id we should NOT flag that as a mismatch
	// (NULL is "unknown", not "definitely different").
	req := map[string]any{"provider_id": float64(14), "credential_id": float64(99)}
	if _, ok := detectBackgroundTaskIDMismatch(1, "diagnose", i64ptr(int64(14)), nil, req); ok {
		t.Fatalf("expected no mismatch when top-level credential_id is NULL")
	}
}

func TestDetectBackgroundTaskIDMismatch_Int64Typed(t *testing.T) {
	// Some JSON libraries decode numbers into int64 instead of float64.
	req := map[string]any{
		"provider_id":   int64(14),
		"credential_id": int64(6),
	}
	topPID := i64ptr(int64(14))
	topCID := i64ptr(int64(6))
	if _, ok := detectBackgroundTaskIDMismatch(40, "health_check", topPID, topCID, req); ok {
		t.Fatalf("expected no mismatch for int64-typed numbers")
	}
}

func TestDetectBackgroundTaskIDMismatch_IntTyped(t *testing.T) {
	req := map[string]any{
		"provider_id":   int(14),
		"credential_id": int(7),
	}
	topPID := i64ptr(int64(14))
	topCID := i64ptr(int64(7))
	if m, ok := detectBackgroundTaskIDMismatch(40, "health_check", topPID, topCID, req); ok {
		t.Fatalf("expected no mismatch for int-typed matching values, got %+v", m)
	}
}

// TestIsBackgroundTasksPKConflict exercises the discriminator used by
// insertBackgroundTask's self-heal path. Only SQLSTATE 23505 on the
// background_tasks_pkey constraint should trigger a sequence resync;
// other unique-violations (e.g. a hypothetical future index) must not.
func TestIsBackgroundTasksPKConflict(t *testing.T) {
	pkErr := &pgconn.PgError{
		Code:           "23505",
		ConstraintName: "background_tasks_pkey",
		Message:        `duplicate key value violates unique constraint "background_tasks_pkey"`,
	}
	if !isBackgroundTasksPKConflict(pkErr) {
		t.Fatalf("expected background_tasks_pkey conflict to be detected")
	}

	otherPKErr := &pgconn.PgError{
		Code:           "23505",
		ConstraintName: "credentials_pkey",
		Message:        `duplicate key value violates unique constraint "credentials_pkey"`,
	}
	if isBackgroundTasksPKConflict(otherPKErr) {
		t.Fatalf("expected non-background_tasks 23505 to NOT trigger self-heal")
	}

	otherErr := &pgconn.PgError{Code: "23502", Message: "not null violation"}
	if isBackgroundTasksPKConflict(otherErr) {
		t.Fatalf("expected non-23505 errors to NOT trigger self-heal")
	}

	if isBackgroundTasksPKConflict(errors.New("plain text error")) {
		t.Fatalf("expected plain error to NOT trigger self-heal")
	}

	if isBackgroundTasksPKConflict(nil) {
		t.Fatalf("nil error must not be a conflict")
	}

	// Fallback path: when the error isn't typed as *pgconn.PgError, fall
	// back to substring matching on the textual message. This is what
	// happens when the error was wrapped/lost its type information.
	if !isBackgroundTasksPKConflict(errors.New(`ERROR: duplicate key value violates unique constraint "background_tasks_pkey" (SQLSTATE 23505)`)) {
		t.Fatalf("expected substring fallback to detect background_tasks_pkey")
	}
}