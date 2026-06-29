package credentialfpslot

import (
	"context"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func TestBatchStats(t *testing.T) {
	mr := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	m := New(Config{DefaultLimit: 5, Enabled: true}, client)
	ctx := context.Background()

	// Setup: 3 credentials with different limits
	cred1, cred2, cred3 := 100, 200, 300
	limit1, limit2, limit3 := 3, 5, 2

	// Acquire some slots to create occupancy
	// cred1: 2/3 used
	m.Acquire(ctx, cred1, &limit1, "holder-a", "tenant1")
	m.Acquire(ctx, cred1, &limit1, "holder-b", "tenant1")

	// cred2: 1/5 used
	m.Acquire(ctx, cred2, &limit2, "holder-c", "tenant1")

	// cred3: 0/2 used (empty)

	// Test BatchStats
	credLimits := map[int]*int{
		cred1: &limit1,
		cred2: &limit2,
		cred3: &limit3,
	}

	results := m.BatchStats(ctx, credLimits)

	// Verify cred1: 2 used, 1 free
	if stats, ok := results[cred1]; !ok {
		t.Errorf("cred1 missing from results")
	} else {
		if stats.SlotLimit == nil || *stats.SlotLimit != 3 {
			t.Errorf("cred1 limit: got %v, want 3", stats.SlotLimit)
		}
		if stats.Used == nil || *stats.Used != 2 {
			t.Errorf("cred1 used: got %v, want 2", stats.Used)
		}
		if stats.Free == nil || *stats.Free != 1 {
			t.Errorf("cred1 free: got %v, want 1", stats.Free)
		}
	}

	// Verify cred2: 1 used, 4 free
	if stats, ok := results[cred2]; !ok {
		t.Errorf("cred2 missing from results")
	} else {
		if stats.SlotLimit == nil || *stats.SlotLimit != 5 {
			t.Errorf("cred2 limit: got %v, want 5", stats.SlotLimit)
		}
		if stats.Used == nil || *stats.Used != 1 {
			t.Errorf("cred2 used: got %v, want 1", stats.Used)
		}
		if stats.Free == nil || *stats.Free != 4 {
			t.Errorf("cred2 free: got %v, want 4", stats.Free)
		}
	}

	// Verify cred3: 0 used, 2 free
	if stats, ok := results[cred3]; !ok {
		t.Errorf("cred3 missing from results")
	} else {
		if stats.SlotLimit == nil || *stats.SlotLimit != 2 {
			t.Errorf("cred3 limit: got %v, want 2", stats.SlotLimit)
		}
		if stats.Used == nil || *stats.Used != 0 {
			t.Errorf("cred3 used: got %v, want 0", stats.Used)
		}
		if stats.Free == nil || *stats.Free != 2 {
			t.Errorf("cred3 free: got %v, want 2", stats.Free)
		}
	}
}

func TestBatchStats_EmptyInput(t *testing.T) {
	mr := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	m := New(Config{DefaultLimit: 5, Enabled: true}, client)
	ctx := context.Background()

	results := m.BatchStats(ctx, map[int]*int{})
	if len(results) != 0 {
		t.Errorf("expected empty results for empty input, got %d items", len(results))
	}
}

func TestBatchStats_UnlimitedCredentials(t *testing.T) {
	mr := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	m := New(Config{DefaultLimit: 5, Enabled: true}, client)
	ctx := context.Background()

	cred1 := 400
	zeroLimit := 0
	nilLimit := (*int)(nil)

	credLimits := map[int]*int{
		cred1: &zeroLimit, // 0 = unlimited
		500:   nilLimit,   // nil = use default
	}

	results := m.BatchStats(ctx, credLimits)

	// Unlimited credentials should be skipped
	if _, ok := results[cred1]; ok {
		t.Errorf("unlimited credential should not appear in results")
	}
	if _, ok := results[500]; !ok {
		t.Errorf("nil-limit credential should use default and appear in results")
	}
}

func TestBatchStats_Consistency(t *testing.T) {
	// Verify BatchStats returns same results as individual Stats calls
	mr := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	m := New(Config{DefaultLimit: 5, Enabled: true}, client)
	ctx := context.Background()

	cred1, cred2 := 600, 700
	limit1, limit2 := 4, 3

	// Acquire some slots
	m.Acquire(ctx, cred1, &limit1, "h1", "t1")
	m.Acquire(ctx, cred2, &limit2, "h2", "t1")

	// Get batch results
	batchResults := m.BatchStats(ctx, map[int]*int{
		cred1: &limit1,
		cred2: &limit2,
	})

	// Get individual results
	l1, u1, f1 := m.Stats(ctx, cred1, &limit1)
	l2, u2, f2 := m.Stats(ctx, cred2, &limit2)

	// Compare
	if b1, ok := batchResults[cred1]; !ok {
		t.Errorf("cred1 missing from batch results")
	} else {
		if !intsEqual(b1.SlotLimit, l1) || !intsEqual(b1.Used, u1) || !intsEqual(b1.Free, f1) {
			t.Errorf("cred1 batch vs individual mismatch: batch=(%v,%v,%v) individual=(%v,%v,%v)",
				b1.SlotLimit, b1.Used, b1.Free, l1, u1, f1)
		}
	}

	if b2, ok := batchResults[cred2]; !ok {
		t.Errorf("cred2 missing from batch results")
	} else {
		if !intsEqual(b2.SlotLimit, l2) || !intsEqual(b2.Used, u2) || !intsEqual(b2.Free, f2) {
			t.Errorf("cred2 batch vs individual mismatch: batch=(%v,%v,%v) individual=(%v,%v,%v)",
				b2.SlotLimit, b2.Used, b2.Free, l2, u2, f2)
		}
	}
}

func intsEqual(a, b *int) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return *a == *b
}
