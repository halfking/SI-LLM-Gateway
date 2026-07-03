package state

import (
	"context"
	"time"
)

type StateManager interface {
	GetCredentialState(ctx context.Context, credentialID int) (*CredentialState, error)
	GetBindingState(ctx context.Context, credentialID int, model string) (*BindingState, error)
	GetNodeState(ctx context.Context, credentialID int, model string) (*NodeState, error)
	ProcessEvent(ctx context.Context, event StateEvent) error
	BatchProcessEvents(ctx context.Context, events []StateEvent) ([]EventResult, error)
}

type CredentialState struct {
	CredentialID          int
	AvailabilityState     string
	QuotaState            string
	CircuitState          string
	LifecycleStatus       string
	AvailabilityRecoverAt *time.Time
	QuotaRecoverAt        *time.Time
	StateReasonCode       *string
	StateReasonDetail     *string
	StateUpdatedAt        time.Time
}

type BindingState struct {
	CredentialID         int
	Model                string
	Available            bool
	UnavailableReason    *string
	UnavailableAt        *time.Time
	UnavailableRecoverAt *time.Time
	AdminProtected       bool
	UpdatedAt            time.Time
}

type NodeState struct {
	CredentialID   int
	Model          string
	SuccessCount   int64
	FailureCount   int64
	SlideWindow    []NodeRecord
	LastSuccessAt  time.Time
	LastFailureAt  time.Time
	Disabled       bool
	DisabledUntil  time.Time
	DisabledReason string
}

type NodeRecord struct {
	RequestID string
	Success   bool
	ErrorKind string
	Timestamp time.Time
}

func (c *CredentialState) GetState() string {
	return c.AvailabilityState
}

func (c *CredentialState) SetState(state string) {
	c.AvailabilityState = state
}
