package credentialstate

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store handles database persistence for credential+model states.
type Store struct {
	db *pgxpool.Pool
}

// NewStore creates a new Store instance.
func NewStore(db *pgxpool.Pool) *Store {
	return &Store{db: db}
}

// Get retrieves a state from the database.
func (s *Store) Get(ctx context.Context, credentialID int64, model string) (*State, error) {
	query := `
		SELECT 
			credential_id, model, state, available,
			total_requests, success_count, failure_count,
			consecutive_failures, consecutive_successes, success_rate,
			last_error_kind, last_error_at,
			last_success_at, last_latency_ms,
			last_probe_at, last_probe_success, last_probe_latency_ms,
			probe_consecutive_failures, probe_consecutive_successes,
			next_probe_at, probe_interval_sec,
			transient_failure_count, transient_failure_window_start,
			pending_verification, verification_scheduled_at,
			degraded_at, degraded_reason,
			unavailable_at, unavailable_reason, unavailable_until,
			created_at, updated_at
		FROM credential_model_state
		WHERE credential_id = $1 AND model = $2
	`

	state := &State{}
	var successRate sql.NullFloat64
	var lastErrorKind, lastErrorAt, lastSuccessAt sql.NullString
	var lastLatencyMs, lastProbeLatencyMs sql.NullInt32
	var lastProbeAt, nextProbeAt sql.NullString
	var lastProbeSuccess sql.NullBool
	var transientWindowStart, verificationScheduledAt sql.NullString
	var degradedAt, degradedReason sql.NullString
	var unavailableAt, unavailableReason, unavailableUntil sql.NullString

	err := s.db.QueryRow(ctx, query, credentialID, model).Scan(
		&state.CredentialID, &state.Model, &state.Status, &state.Available,
		&state.TotalRequests, &state.SuccessCount, &state.FailureCount,
		&state.ConsecutiveFailures, &state.ConsecutiveSuccesses, &successRate,
		&lastErrorKind, &lastErrorAt,
		&lastSuccessAt, &lastLatencyMs,
		&lastProbeAt, &lastProbeSuccess, &lastProbeLatencyMs,
		&state.ProbeConsecutiveFailures, &state.ProbeConsecutiveSuccesses,
		&nextProbeAt, &state.ProbeIntervalSec,
		&state.TransientFailureCount, &transientWindowStart,
		&state.PendingVerification, &verificationScheduledAt,
		&degradedAt, &degradedReason,
		&unavailableAt, &unavailableReason, &unavailableUntil,
		&state.CreatedAt, &state.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("query state: %w", err)
	}

	// Handle nullable fields
	if successRate.Valid {
		state.SuccessRate = successRate.Float64
	}
	if lastErrorKind.Valid {
		state.LastErrorKind = lastErrorKind.String
	}
	if lastErrorAt.Valid {
		if t, err := time.Parse(time.RFC3339, lastErrorAt.String); err == nil {
			state.LastErrorAt = t
		}
	}
	if lastSuccessAt.Valid {
		if t, err := time.Parse(time.RFC3339, lastSuccessAt.String); err == nil {
			state.LastSuccessAt = t
		}
	}
	if lastLatencyMs.Valid {
		state.LastLatencyMs = int(lastLatencyMs.Int32)
	}
	if lastProbeAt.Valid {
		if t, err := time.Parse(time.RFC3339, lastProbeAt.String); err == nil {
			state.LastProbeAt = t
		}
	}
	if lastProbeSuccess.Valid {
		state.LastProbeSuccess = lastProbeSuccess.Bool
	}
	if lastProbeLatencyMs.Valid {
		state.LastProbeLatencyMs = int(lastProbeLatencyMs.Int32)
	}
	if nextProbeAt.Valid {
		if t, err := time.Parse(time.RFC3339, nextProbeAt.String); err == nil {
			state.NextProbeAt = t
		}
	}
	if transientWindowStart.Valid {
		if t, err := time.Parse(time.RFC3339, transientWindowStart.String); err == nil {
			state.TransientFailureWindowStart = t
		}
	}
	if verificationScheduledAt.Valid {
		if t, err := time.Parse(time.RFC3339, verificationScheduledAt.String); err == nil {
			state.VerificationScheduledAt = t
		}
	}
	if degradedAt.Valid {
		if t, err := time.Parse(time.RFC3339, degradedAt.String); err == nil {
			state.DegradedAt = t
		}
	}
	if degradedReason.Valid {
		state.DegradedReason = degradedReason.String
	}
	if unavailableAt.Valid {
		if t, err := time.Parse(time.RFC3339, unavailableAt.String); err == nil {
			state.UnavailableAt = t
		}
	}
	if unavailableReason.Valid {
		state.UnavailableReason = unavailableReason.String
	}
	if unavailableUntil.Valid {
		if t, err := time.Parse(time.RFC3339, unavailableUntil.String); err == nil {
			state.UnavailableUntil = t
		}
	}

	return state, nil
}

// Upsert inserts or updates a state in the database.
func (s *Store) Upsert(ctx context.Context, state *State) error {
	query := `
		INSERT INTO credential_model_state (
			credential_id, model, state, available,
			total_requests, success_count, failure_count,
			consecutive_failures, consecutive_successes, success_rate,
			last_error_kind, last_error_at,
			last_success_at, last_latency_ms,
			last_probe_at, last_probe_success, last_probe_latency_ms,
			probe_consecutive_failures, probe_consecutive_successes,
			next_probe_at, probe_interval_sec,
			transient_failure_count, transient_failure_window_start,
			pending_verification, verification_scheduled_at,
			degraded_at, degraded_reason,
			unavailable_at, unavailable_reason, unavailable_until
		) VALUES (
			$1, $2, $3, $4,
			$5, $6, $7,
			$8, $9, $10,
			$11, $12,
			$13, $14,
			$15, $16, $17,
			$18, $19,
			$20, $21,
			$22, $23,
			$24, $25,
			$26, $27,
			$28, $29, $30
		)
		ON CONFLICT (credential_id, model)
		DO UPDATE SET
			state = EXCLUDED.state,
			available = EXCLUDED.available,
			total_requests = EXCLUDED.total_requests,
			success_count = EXCLUDED.success_count,
			failure_count = EXCLUDED.failure_count,
			consecutive_failures = EXCLUDED.consecutive_failures,
			consecutive_successes = EXCLUDED.consecutive_successes,
			success_rate = EXCLUDED.success_rate,
			last_error_kind = EXCLUDED.last_error_kind,
			last_error_at = EXCLUDED.last_error_at,
			last_success_at = EXCLUDED.last_success_at,
			last_latency_ms = EXCLUDED.last_latency_ms,
			last_probe_at = EXCLUDED.last_probe_at,
			last_probe_success = EXCLUDED.last_probe_success,
			last_probe_latency_ms = EXCLUDED.last_probe_latency_ms,
			probe_consecutive_failures = EXCLUDED.probe_consecutive_failures,
			probe_consecutive_successes = EXCLUDED.probe_consecutive_successes,
			next_probe_at = EXCLUDED.next_probe_at,
			probe_interval_sec = EXCLUDED.probe_interval_sec,
			transient_failure_count = EXCLUDED.transient_failure_count,
			transient_failure_window_start = EXCLUDED.transient_failure_window_start,
			pending_verification = EXCLUDED.pending_verification,
			verification_scheduled_at = EXCLUDED.verification_scheduled_at,
			degraded_at = EXCLUDED.degraded_at,
			degraded_reason = EXCLUDED.degraded_reason,
			unavailable_at = EXCLUDED.unavailable_at,
			unavailable_reason = EXCLUDED.unavailable_reason,
			unavailable_until = EXCLUDED.unavailable_until,
			updated_at = NOW()
	`

	// Convert nullable fields
	var lastErrorKind, lastErrorAt, lastSuccessAt interface{}
	var lastLatencyMs, lastProbeLatencyMs interface{}
	var lastProbeAt, nextProbeAt interface{}
	var lastProbeSuccess interface{}
	var transientWindowStart, verificationScheduledAt interface{}
	var degradedAt, degradedReason interface{}
	var unavailableAt, unavailableReason, unavailableUntil interface{}

	if state.LastErrorKind != "" {
		lastErrorKind = state.LastErrorKind
	}
	if !state.LastErrorAt.IsZero() {
		lastErrorAt = state.LastErrorAt
	}
	if !state.LastSuccessAt.IsZero() {
		lastSuccessAt = state.LastSuccessAt
	}
	if state.LastLatencyMs > 0 {
		lastLatencyMs = state.LastLatencyMs
	}
	if !state.LastProbeAt.IsZero() {
		lastProbeAt = state.LastProbeAt
	}
	lastProbeSuccess = state.LastProbeSuccess
	if state.LastProbeLatencyMs > 0 {
		lastProbeLatencyMs = state.LastProbeLatencyMs
	}
	if !state.NextProbeAt.IsZero() {
		nextProbeAt = state.NextProbeAt
	}
	if !state.TransientFailureWindowStart.IsZero() {
		transientWindowStart = state.TransientFailureWindowStart
	}
	if !state.VerificationScheduledAt.IsZero() {
		verificationScheduledAt = state.VerificationScheduledAt
	}
	if !state.DegradedAt.IsZero() {
		degradedAt = state.DegradedAt
	}
	if state.DegradedReason != "" {
		degradedReason = state.DegradedReason
	}
	if !state.UnavailableAt.IsZero() {
		unavailableAt = state.UnavailableAt
	}
	if state.UnavailableReason != "" {
		unavailableReason = state.UnavailableReason
	}
	if !state.UnavailableUntil.IsZero() {
		unavailableUntil = state.UnavailableUntil
	}

	_, err := s.db.Exec(ctx, query,
		state.CredentialID, state.Model, state.Status, state.Available,
		state.TotalRequests, state.SuccessCount, state.FailureCount,
		state.ConsecutiveFailures, state.ConsecutiveSuccesses, state.SuccessRate,
		lastErrorKind, lastErrorAt,
		lastSuccessAt, lastLatencyMs,
		lastProbeAt, lastProbeSuccess, lastProbeLatencyMs,
		state.ProbeConsecutiveFailures, state.ProbeConsecutiveSuccesses,
		nextProbeAt, state.ProbeIntervalSec,
		state.TransientFailureCount, transientWindowStart,
		state.PendingVerification, verificationScheduledAt,
		degradedAt, degradedReason,
		unavailableAt, unavailableReason, unavailableUntil,
	)

	if err != nil {
		return fmt.Errorf("upsert state: %w", err)
	}

	return nil
}

// ListAvailable returns all available states for a given model.
func (s *Store) ListAvailable(ctx context.Context, model string) ([]*State, error) {
	query := `
		SELECT credential_id, model, state, available, success_rate,
		       last_success_at, last_probe_at, last_probe_success
		FROM credential_model_state
		WHERE model = $1 AND available = true
		ORDER BY success_rate DESC NULLS LAST, last_success_at DESC
		LIMIT 100
	`

	rows, err := s.db.Query(ctx, query, model)
	if err != nil {
		return nil, fmt.Errorf("list available: %w", err)
	}
	defer rows.Close()

	var states []*State
	for rows.Next() {
		state := &State{}
		var successRate sql.NullFloat64
		var lastSuccessAt, lastProbeAt sql.NullString
		var lastProbeSuccess sql.NullBool

		err := rows.Scan(
			&state.CredentialID, &state.Model, &state.Status, &state.Available,
			&successRate, &lastSuccessAt, &lastProbeAt, &lastProbeSuccess,
		)
		if err != nil {
			return nil, fmt.Errorf("scan row: %w", err)
		}

		if successRate.Valid {
			state.SuccessRate = successRate.Float64
		}
		if lastSuccessAt.Valid {
			if t, err := time.Parse(time.RFC3339, lastSuccessAt.String); err == nil {
				state.LastSuccessAt = t
			}
		}
		if lastProbeAt.Valid {
			if t, err := time.Parse(time.RFC3339, lastProbeAt.String); err == nil {
				state.LastProbeAt = t
			}
		}
		if lastProbeSuccess.Valid {
			state.LastProbeSuccess = lastProbeSuccess.Bool
		}

		states = append(states, state)
	}

	return states, rows.Err()
}

// GetProbeTargets returns states that need probing.
func (s *Store) GetProbeTargets(ctx context.Context, limit int) ([]*State, error) {
	query := `
		SELECT credential_id, model, state, probe_interval_sec,
		       probe_consecutive_failures, next_probe_at
		FROM credential_model_state
		WHERE next_probe_at IS NOT NULL
		  AND next_probe_at <= NOW()
		  AND pending_verification = false
		ORDER BY next_probe_at ASC
		LIMIT $1
	`

	rows, err := s.db.Query(ctx, query, limit)
	if err != nil {
		return nil, fmt.Errorf("get probe targets: %w", err)
	}
	defer rows.Close()

	var states []*State
	for rows.Next() {
		state := &State{}
		var nextProbeAt sql.NullString

		err := rows.Scan(
			&state.CredentialID, &state.Model, &state.Status,
			&state.ProbeIntervalSec, &state.ProbeConsecutiveFailures,
			&nextProbeAt,
		)
		if err != nil {
			return nil, fmt.Errorf("scan probe target: %w", err)
		}

		if nextProbeAt.Valid {
			if t, err := time.Parse(time.RFC3339, nextProbeAt.String); err == nil {
				state.NextProbeAt = t
			}
		}

		states = append(states, state)
	}

	return states, rows.Err()
}

// Delete removes a state from the database (for testing/cleanup).
func (s *Store) Delete(ctx context.Context, credentialID int64, model string) error {
	query := `DELETE FROM credential_model_state WHERE credential_id = $1 AND model = $2`
	_, err := s.db.Exec(ctx, query, credentialID, model)
	return err
}

// ErrNotFound is returned when a state is not found in the database.
var ErrNotFound = fmt.Errorf("state not found")
