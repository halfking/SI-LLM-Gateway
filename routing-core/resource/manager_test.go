package resource

import (
	"context"
	"testing"

	"github.com/kaixuan/llm-gateway-go/credentialfpslot"
	"github.com/kaixuan/llm-gateway-go/limiter"
)

func TestResourceManager_CheckEligibility(t *testing.T) {
	fpSlot := credentialfpslot.New(credentialfpslot.Config{
		Enabled:      true,
		DefaultLimit: 10,
	}, nil)
	lim := limiter.New()
	defer lim.Stop()

	rm := NewResourceManager(fpSlot, lim)

	req := EligibilityRequest{
		CredentialID:     1,
		Holder:           "test-holder",
		FpSlotLimit:      intPtr(10),
		ConcurrencyLimit: 50,
	}

	result, err := rm.CheckEligibility(context.Background(), req)
	if err != nil {
		t.Fatalf("CheckEligibility failed: %v", err)
	}

	if !result.FpSlotAvailable {
		t.Errorf("expected FpSlotAvailable=true, got false")
	}

	if !result.ConcurAvailable {
		t.Errorf("expected ConcurAvailable=true, got false")
	}

	if !result.Eligible {
		t.Errorf("expected Eligible=true, got false")
	}
}

func TestResourceManager_AcquireResources(t *testing.T) {
	fpSlot := credentialfpslot.New(credentialfpslot.Config{
		Enabled:      true,
		DefaultLimit: 10,
	}, nil)
	lim := limiter.New()
	defer lim.Stop()

	rm := NewResourceManager(fpSlot, lim)

	req := AcquireRequest{
		CredentialID:     1,
		ProviderID:       1,
		Model:            "gpt-4",
		Holder:           "test-holder",
		FpSlotLimit:      intPtr(10),
		ConcurrencyLimit: 50,
		IdentityHash:     "test-identity",
	}

	resources, release, err := rm.AcquireResources(context.Background(), req)
	if err != nil {
		t.Fatalf("AcquireResources failed: %v", err)
	}

	if resources == nil {
		t.Fatal("expected resources, got nil")
	}

	if resources.FpSlot == nil {
		t.Error("expected FpSlot, got nil")
	}

	if resources.Concurrency == nil {
		t.Error("expected Concurrency, got nil")
	}

	if release == nil {
		t.Fatal("expected release func, got nil")
	}

	if err := release(context.Background()); err != nil {
		t.Errorf("release failed: %v", err)
	}
}

func TestResourceManager_GetResourceStats(t *testing.T) {
	fpSlot := credentialfpslot.New(credentialfpslot.Config{
		Enabled:      true,
		DefaultLimit: 10,
	}, nil)
	lim := limiter.New()
	defer lim.Stop()

	rm := NewResourceManager(fpSlot, lim)

	stats, err := rm.GetResourceStats(context.Background(), 1)
	if err != nil {
		t.Fatalf("GetResourceStats failed: %v", err)
	}

	if stats == nil {
		t.Fatal("expected stats, got nil")
	}
}

func TestResourceManager_CalculatePressure(t *testing.T) {
	fpSlot := credentialfpslot.New(credentialfpslot.Config{
		Enabled:      true,
		DefaultLimit: 10,
	}, nil)
	lim := limiter.New()
	defer lim.Stop()

	rm := NewResourceManager(fpSlot, lim)

	pressure, err := rm.CalculatePressure(context.Background(), 1)
	if err != nil {
		t.Fatalf("CalculatePressure failed: %v", err)
	}

	if pressure < 0.0 || pressure > 1.0 {
		t.Errorf("expected pressure in [0,1], got %f", pressure)
	}
}

func intPtr(n int) *int {
	return &n
}
