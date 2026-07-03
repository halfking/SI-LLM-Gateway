package resource

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/kaixuan/llm-gateway-go/credentialfpslot"
	"github.com/kaixuan/llm-gateway-go/limiter"
)

type resourceManager struct {
	fpSlot *credentialfpslot.Manager
	lim    *limiter.Limiter
}

func NewResourceManager(fpSlot *credentialfpslot.Manager, lim *limiter.Limiter) ResourceManager {
	return &resourceManager{
		fpSlot: fpSlot,
		lim:    lim,
	}
}

func (r *resourceManager) CheckEligibility(ctx context.Context, req EligibilityRequest) (*EligibilityResult, error) {
	result := &EligibilityResult{}

	fpAvailable := r.fpSlot.RoutingEligible(ctx, req.CredentialID, req.FpSlotLimit, req.Holder)
	result.FpSlotAvailable = fpAvailable

	if req.FpSlotLimit != nil && *req.FpSlotLimit > 0 {
		limit, used, free := r.fpSlot.Stats(ctx, req.CredentialID, req.FpSlotLimit)
		if limit != nil && used != nil && free != nil {
			result.FpSlotDetail = fmt.Sprintf("limit:%d,used:%d,free:%d", *limit, *used, *free)
		} else {
			result.FpSlotDetail = "unavailable"
		}
	} else {
		result.FpSlotDetail = "unlimited"
	}

	concurFree, concurDetail, err := r.checkConcurrency(ctx, req.CredentialID)
	if err != nil {
		slog.WarnContext(ctx, "failed to check concurrency", "error", err)
		result.ConcurAvailable = false
		result.ConcurDetail = "error"
	} else {
		result.ConcurAvailable = concurFree > 0
		result.ConcurDetail = concurDetail
	}

	result.Eligible = result.FpSlotAvailable && result.ConcurAvailable

	pressure, err := r.CalculatePressure(ctx, req.CredentialID)
	if err != nil {
		slog.WarnContext(ctx, "failed to calculate pressure", "error", err)
		pressure = 0.0
	}
	result.ResourcePressure = pressure

	if result.Eligible {
		result.RecommendedAction = "proceed"
	} else if !result.FpSlotAvailable && result.ConcurAvailable {
		result.RecommendedAction = "retry_later"
	} else if result.FpSlotAvailable && !result.ConcurAvailable {
		result.RecommendedAction = "retry_later"
	} else {
		result.RecommendedAction = "use_alternative"
	}

	return result, nil
}

func (r *resourceManager) AcquireResources(ctx context.Context, req AcquireRequest) (*AcquiredResources, ReleaseFunc, error) {
	var fpLease *FpSlotLease
	var concurToken *ConcurrencyToken
	var fpRelease func(context.Context) error
	var concurRelease limiter.ReleaseFunc

	if req.FpSlotLimit != nil && *req.FpSlotLimit > 0 {
		lease, acquired := r.fpSlot.Acquire(ctx, req.CredentialID, req.FpSlotLimit, req.Holder, "")
		if !acquired {
			return nil, nil, fmt.Errorf("failed to acquire fp slot")
		}
		fpLease = &FpSlotLease{
			SlotIndex:    lease.SlotIndex,
			Egress:       lease.Egress,
			Unlimited:    lease.Unlimited,
			CredentialID: lease.CredentialID,
		}
		fpRelease = func(ctx context.Context) error {
			r.fpSlot.Release(ctx, lease)
			return nil
		}
	}

	keyID := 0
	keyLimit := 0
	if req.KeyID != nil {
		keyID = *req.KeyID
	}
	if req.KeyConcurLimit != nil {
		keyLimit = *req.KeyConcurLimit
	}

	releaseFn, err := r.lim.AcquireAll(ctx, req.ProviderID, req.CredentialID, req.IdentityHash, keyID, keyLimit)
	if err != nil {
		if fpRelease != nil {
			fpRelease(ctx)
		}
		return nil, nil, fmt.Errorf("failed to acquire concurrency: %w", err)
	}

	concurToken = &ConcurrencyToken{
		Global:     true,
		Pool:       true,
		Credential: true,
		Identity:   req.IdentityHash != "",
	}
	concurRelease = releaseFn

	resources := &AcquiredResources{
		FpSlot:      fpLease,
		Concurrency: concurToken,
		AcquiredAt:  time.Now(),
	}

	combinedRelease := func(ctx context.Context) error {
		if fpRelease != nil {
			if err := fpRelease(ctx); err != nil {
				slog.ErrorContext(ctx, "failed to release fpslot", "error", err)
			}
		}
		if concurRelease != nil {
			concurRelease()
		}
		return nil
	}

	return resources, combinedRelease, nil
}

func (r *resourceManager) GetResourceStats(ctx context.Context, credentialID int) (*ResourceStats, error) {
	stats := &ResourceStats{}

	limit, used, free := r.fpSlot.Stats(ctx, credentialID, nil)
	if limit != nil {
		stats.FpSlots.Limit = *limit
	}
	if used != nil {
		stats.FpSlots.Used = *used
	}
	if free != nil {
		stats.FpSlots.Free = *free
	}

	pressure, err := r.CalculatePressure(ctx, credentialID)
	if err != nil {
		slog.WarnContext(ctx, "failed to calculate pressure", "error", err)
	}
	stats.Pressure = pressure

	return stats, nil
}

func (r *resourceManager) CalculatePressure(ctx context.Context, credentialID int) (float64, error) {
	limit, used, _ := r.fpSlot.Stats(ctx, credentialID, nil)

	var fpPressure float64
	if limit != nil && *limit > 0 && used != nil {
		fpPressure = float64(*used) / float64(*limit)
	}

	return fpPressure, nil
}

func (r *resourceManager) checkConcurrency(ctx context.Context, credentialID int) (int, string, error) {
	return 10, "free:10/50", nil
}
