package state

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kaixuan/llm-gateway-go/routing"
	"github.com/redis/go-redis/v9"
)

type CompositeStateManager struct {
	credential *CredentialStateManager
	binding    *BindingStateManager
	node       *NodeStateManager
}

func NewCompositeStateManager(pool *pgxpool.Pool, redisClient *redis.Client, nodeCfg routing.RouteNodeConfig) *CompositeStateManager {
	return &CompositeStateManager{
		credential: NewCredentialStateManager(pool),
		binding:    NewBindingStateManager(pool),
		node:       NewNodeStateManager(redisClient, nodeCfg),
	}
}

func (m *CompositeStateManager) GetCredentialState(ctx context.Context, credentialID int) (*CredentialState, error) {
	return m.credential.GetCredentialState(ctx, credentialID)
}

func (m *CompositeStateManager) GetBindingState(ctx context.Context, credentialID int, model string) (*BindingState, error) {
	return m.binding.GetBindingState(ctx, credentialID, model)
}

func (m *CompositeStateManager) GetNodeState(ctx context.Context, credentialID int, model string) (*NodeState, error) {
	return m.node.GetNodeState(ctx, credentialID, model)
}

func (m *CompositeStateManager) ProcessEvent(ctx context.Context, event StateEvent) error {
	switch event.Type {
	case EventSuccess:
		if err := m.credential.ProcessSuccessEvent(ctx, event); err != nil {
			return err
		}
		if event.Model != "" {
			return m.node.RecordSuccess(ctx, event.CredentialID, event.Model, event.RequestID)
		}
		return nil

	case EventFailureAuth, EventFailureQuota, EventFailureNetwork,
		EventFailureRateLimit, EventFailureTimeout, EventFailureConcurrent,
		EventFailureUpstreamDown, EventFailureStreamTimeout:
		if err := m.credential.ProcessFailureEvent(ctx, event); err != nil {
			return err
		}
		if event.Model != "" {
			return m.node.RecordFailure(ctx, event.CredentialID, event.Model, event.RequestID, string(event.ErrorKind))
		}
		return nil

	case EventManualDisable, EventManualEnable, EventManualSuspend:
		return nil

	default:
		return nil
	}
}

func (m *CompositeStateManager) BatchProcessEvents(ctx context.Context, events []StateEvent) ([]EventResult, error) {
	results := make([]EventResult, 0, len(events))

	for _, event := range events {
		result := EventResult{
			Event:   event,
			Applied: false,
		}

		if err := m.ProcessEvent(ctx, event); err != nil {
			result.Error = err
		} else {
			result.Applied = true
		}

		results = append(results, result)
	}

	return results, nil
}
