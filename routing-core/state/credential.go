package state

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kaixuan/llm-gateway-go/credentialstate"
)

type CredentialStateManager struct {
	writer *credentialstate.Writer
	pool   *pgxpool.Pool
}

func NewCredentialStateManager(pool *pgxpool.Pool) *CredentialStateManager {
	return &CredentialStateManager{
		writer: credentialstate.NewWriter(pool),
		pool:   pool,
	}
}

func (m *CredentialStateManager) GetCredentialState(ctx context.Context, credentialID int) (*CredentialState, error) {
	if m.pool == nil {
		return nil, fmt.Errorf("database pool not configured")
	}

	row := m.pool.QueryRow(ctx, `
		SELECT 
			id,
			availability_state,
			quota_state,
			circuit_state,
			lifecycle_status,
			availability_recover_at,
			quota_recover_at,
			state_reason_code,
			state_reason_detail,
			state_updated_at
		FROM credentials
		WHERE id = $1
	`, credentialID)

	var state CredentialState
	err := row.Scan(
		&state.CredentialID,
		&state.AvailabilityState,
		&state.QuotaState,
		&state.CircuitState,
		&state.LifecycleStatus,
		&state.AvailabilityRecoverAt,
		&state.QuotaRecoverAt,
		&state.StateReasonCode,
		&state.StateReasonDetail,
		&state.StateUpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to query credential state: %w", err)
	}

	return &state, nil
}

func (m *CredentialStateManager) ProcessSuccessEvent(ctx context.Context, event StateEvent) error {
	if m.writer == nil {
		return fmt.Errorf("credential state writer not configured")
	}
	return m.writer.RestoreOnSuccess(ctx, event.CredentialID, event.Model)
}

func (m *CredentialStateManager) ProcessFailureEvent(ctx context.Context, event StateEvent) error {
	if m.writer == nil {
		return fmt.Errorf("credential state writer not configured")
	}

	failure := credentialstate.Failure{
		Kind:       event.ErrorKind,
		Detail:     event.ErrorDetail,
		RetryAfter: event.RetryAfter,
	}

	return m.writer.WriteOnError(ctx, event.CredentialID, event.Model, failure)
}
