package state

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

type BindingStateManager struct {
	pool *pgxpool.Pool
}

func NewBindingStateManager(pool *pgxpool.Pool) *BindingStateManager {
	return &BindingStateManager{
		pool: pool,
	}
}

func (m *BindingStateManager) GetBindingState(ctx context.Context, credentialID int, model string) (*BindingState, error) {
	if m.pool == nil {
		return nil, fmt.Errorf("database pool not configured")
	}

	row := m.pool.QueryRow(ctx, `
		SELECT 
			cmb.credential_id,
			COALESCE(pm.outbound_model_name, pm.raw_model_name) AS model,
			cmb.available,
			cmb.unavailable_reason,
			cmb.unavailable_at,
			cmb.unavailable_recover_at,
			COALESCE(cmb.admin_protected, FALSE) AS admin_protected,
			cmb.updated_at
		FROM credential_model_bindings cmb
		JOIN provider_models pm ON pm.id = cmb.provider_model_id
		WHERE cmb.credential_id = $1
		  AND COALESCE(pm.outbound_model_name, pm.raw_model_name) = $2
		LIMIT 1
	`, credentialID, model)

	var state BindingState
	err := row.Scan(
		&state.CredentialID,
		&state.Model,
		&state.Available,
		&state.UnavailableReason,
		&state.UnavailableAt,
		&state.UnavailableRecoverAt,
		&state.AdminProtected,
		&state.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to query binding state: %w", err)
	}

	return &state, nil
}
