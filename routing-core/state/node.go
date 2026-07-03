package state

import (
	"context"
	"fmt"

	"github.com/kaixuan/llm-gateway-go/routing"
	"github.com/redis/go-redis/v9"
)

type NodeStateManager struct {
	store *routing.RouteNodeStore
}

func NewNodeStateManager(redisClient *redis.Client, cfg routing.RouteNodeConfig) *NodeStateManager {
	return &NodeStateManager{
		store: routing.NewRouteNodeStore(redisClient, cfg),
	}
}

func (m *NodeStateManager) GetNodeState(ctx context.Context, credentialID int, model string) (*NodeState, error) {
	if m.store == nil {
		return nil, fmt.Errorf("route node store not configured")
	}

	routeState, found, err := m.store.Get(ctx, credentialID, model)
	if err != nil {
		return nil, fmt.Errorf("failed to get route node state: %w", err)
	}

	if !found {
		return nil, nil
	}

	state := &NodeState{
		CredentialID:   routeState.CredentialID,
		Model:          routeState.Model,
		SuccessCount:   routeState.SuccessCount,
		FailureCount:   routeState.FailureCount,
		LastSuccessAt:  routeState.LastSuccessAt,
		LastFailureAt:  routeState.LastFailureAt,
		Disabled:       routeState.Disabled,
		DisabledUntil:  routeState.DisabledUntil,
		DisabledReason: routeState.DisabledReason,
	}

	state.SlideWindow = make([]NodeRecord, len(routeState.SlideWindow))
	for i, rec := range routeState.SlideWindow {
		state.SlideWindow[i] = NodeRecord{
			RequestID: rec.RequestID,
			Success:   rec.Success,
			ErrorKind: rec.ErrorKind,
			Timestamp: rec.Timestamp,
		}
	}

	return state, nil
}

func (m *NodeStateManager) RecordSuccess(ctx context.Context, credentialID int, model, requestID string) error {
	if m.store == nil {
		return fmt.Errorf("route node store not configured")
	}

	_, err := m.store.RecordSuccess(ctx, credentialID, model, requestID)
	return err
}

func (m *NodeStateManager) RecordFailure(ctx context.Context, credentialID int, model, requestID, errorKind string) error {
	if m.store == nil {
		return fmt.Errorf("route node store not configured")
	}

	_, _, err := m.store.RecordFailure(ctx, credentialID, model, requestID, errorKind)
	return err
}

func (m *NodeStateManager) IsUsable(ctx context.Context, credentialID int, model string) bool {
	if m.store == nil {
		return true
	}
	return m.store.IsUsable(ctx, credentialID, model)
}
