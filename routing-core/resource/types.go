package resource

import (
	"context"
	"time"

	"github.com/kaixuan/llm-gateway-go/identity"
)

type ResourceManager interface {
	CheckEligibility(ctx context.Context, req EligibilityRequest) (*EligibilityResult, error)
	AcquireResources(ctx context.Context, req AcquireRequest) (*AcquiredResources, ReleaseFunc, error)
	GetResourceStats(ctx context.Context, credentialID int) (*ResourceStats, error)
	CalculatePressure(ctx context.Context, credentialID int) (float64, error)
}

type EligibilityRequest struct {
	CredentialID     int
	Holder           string
	FpSlotLimit      *int
	ConcurrencyLimit int
}

type EligibilityResult struct {
	Eligible          bool
	FpSlotAvailable   bool
	ConcurAvailable   bool
	FpSlotDetail      string
	ConcurDetail      string
	ResourcePressure  float64
	RecommendedAction string
}

type AcquireRequest struct {
	CredentialID     int
	ProviderID       int
	Model            string
	Holder           string
	FpSlotLimit      *int
	ConcurrencyLimit int
	IdentityHash     string
	KeyID            *int
	KeyConcurLimit   *int
}

type AcquiredResources struct {
	FpSlot      *FpSlotLease
	Concurrency *ConcurrencyToken
	AcquiredAt  time.Time
}

type FpSlotLease struct {
	SlotIndex    int
	Egress       *identity.EgressIdentity
	Unlimited    bool
	CredentialID int
}

type ConcurrencyToken struct {
	Global     bool
	Pool       bool
	Credential bool
	Identity   bool
}

type ReleaseFunc func(ctx context.Context) error

type ResourceStats struct {
	FpSlots struct {
		Limit int
		Used  int
		Free  int
	}
	Concurrency struct {
		Limit int
		Used  int
		Free  int
	}
	Pressure float64
}
