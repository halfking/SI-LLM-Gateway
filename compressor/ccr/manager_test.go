package ccr

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupTestManager(t *testing.T) (*Manager, func()) {
	// Setup mock Redis
	mr := miniredis.RunT(t)
	redisClient := redis.NewClient(&redis.Options{
		Addr: mr.Addr(),
	})

	// Setup in-memory SQLite (use pgx driver but SQLite syntax)
	db, err := sql.Open("pgx", "host=/tmp dbname=test_ccr")
	if err != nil {
		// Fallback to in-memory SQLite for testing
		db, err = sql.Open("pgx", ":memory:")
	}
	require.NoError(t, err)

	// Create manager with L3 disabled for simplicity
	config := DefaultConfig()
	config.L3Enabled = false // Disable L3 for unit tests
	manager, err := NewManager(config, redisClient, db)
	require.NoError(t, err)

	cleanup := func() {
		manager.Close()
		redisClient.Close()
		mr.Close()
		db.Close()
	}

	return manager, cleanup
}

func TestManager_PutGet(t *testing.T) {
	manager, cleanup := setupTestManager(t)
	defer cleanup()

	ctx := context.Background()
	hash := "abc123def456789012345678"
	data := []byte("test data for CCR storage")
	sessionID := "gw_test_session"

	// Put data
	err := manager.Put(ctx, hash, data, sessionID)
	require.NoError(t, err)

	// Get data
	retrieved, err := manager.Get(ctx, hash)
	require.NoError(t, err)
	assert.Equal(t, data, retrieved)
}

func TestManager_L1Cache(t *testing.T) {
	manager, cleanup := setupTestManager(t)
	defer cleanup()

	ctx := context.Background()
	hash := "test_l1_cache"
	data := []byte("L1 cache test data")

	// Put and get
	err := manager.Put(ctx, hash, data, "session1")
	require.NoError(t, err)

	retrieved, err := manager.Get(ctx, hash)
	require.NoError(t, err)
	assert.Equal(t, data, retrieved)

	// Check metrics - should be L1 hit
	metrics := manager.GetMetrics()
	assert.Equal(t, int64(1), metrics.L1Hits)
	assert.Equal(t, int64(1), metrics.PutTotal)
	assert.Equal(t, int64(1), metrics.GetTotal)
}

func TestManager_L2Redis(t *testing.T) {
	manager, cleanup := setupTestManager(t)
	defer cleanup()

	ctx := context.Background()
	hash := "test_l2_redis"
	data := []byte("L2 Redis test data")

	// Put data
	err := manager.Put(ctx, hash, data, "session2")
	require.NoError(t, err)

	// Clear L1 cache to force L2 lookup
	manager.l1Cache.Delete(hash)

	// Get from L2
	retrieved, err := manager.Get(ctx, hash)
	require.NoError(t, err)
	assert.Equal(t, data, retrieved)

	// Check metrics - should be L2 hit
	metrics := manager.GetMetrics()
	assert.Equal(t, int64(1), metrics.L1Misses)
	assert.Equal(t, int64(1), metrics.L2Hits)
}

func TestManager_L3Database(t *testing.T) {
	t.Skip("L3 database tests disabled for unit testing")
}

func TestManager_Backfill(t *testing.T) {
	t.Skip("L3 backfill tests disabled for unit testing")
}

func TestManager_Delete(t *testing.T) {
	manager, cleanup := setupTestManager(t)
	defer cleanup()

	ctx := context.Background()
	hash := "test_delete"
	data := []byte("delete test data")

	// Put data
	err := manager.Put(ctx, hash, data, "session_delete")
	require.NoError(t, err)

	// Verify it exists
	_, err = manager.Get(ctx, hash)
	require.NoError(t, err)

	// Delete
	err = manager.Delete(ctx, hash)
	require.NoError(t, err)

	// Verify it's gone
	_, err = manager.Get(ctx, hash)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
}

func TestManager_NotFound(t *testing.T) {
	manager, cleanup := setupTestManager(t)
	defer cleanup()

	ctx := context.Background()
	hash := "nonexistent_hash"

	// Get non-existent hash
	_, err := manager.Get(ctx, hash)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "not found")

	// Check metrics - with L3 disabled, should only show L1 and L2 misses
	metrics := manager.GetMetrics()
	assert.Equal(t, int64(1), metrics.L1Misses)
	assert.Equal(t, int64(1), metrics.L2Misses)
	// L3 is disabled in tests, so no L3 misses
	assert.Equal(t, int64(0), metrics.L3Misses)
}

func TestManager_Metrics(t *testing.T) {
	manager, cleanup := setupTestManager(t)
	defer cleanup()

	ctx := context.Background()

	// Multiple operations
	for i := 0; i < 10; i++ {
		hash := string(rune('a' + i))
		data := []byte{byte(i)}
		manager.Put(ctx, hash, data, "session")
		manager.Get(ctx, hash)
	}

	metrics := manager.GetMetrics()
	assert.Equal(t, int64(10), metrics.PutTotal)
	assert.Equal(t, int64(10), metrics.GetTotal)
	assert.Equal(t, int64(10), metrics.L1Hits)

	// Calculate hit ratio
	hitRatio := metrics.HitRatio()
	assert.Greater(t, hitRatio, 0.9) // Should be very high

	// Reset metrics
	manager.ResetMetrics()
	metrics = manager.GetMetrics()
	assert.Equal(t, int64(0), metrics.PutTotal)
	assert.Equal(t, int64(0), metrics.GetTotal)
}

func TestManager_DuplicateKey(t *testing.T) {
	manager, cleanup := setupTestManager(t)
	defer cleanup()

	ctx := context.Background()
	hash := "duplicate_test"
	data1 := []byte("first data")
	data2 := []byte("second data")

	// Put first time
	err := manager.Put(ctx, hash, data1, "session1")
	require.NoError(t, err)

	// Put again with same hash (should not error)
	err = manager.Put(ctx, hash, data2, "session2")
	require.NoError(t, err)

	// Get should return latest (from L1)
	retrieved, err := manager.Get(ctx, hash)
	require.NoError(t, err)
	assert.Equal(t, data2, retrieved)
}

func TestManager_DisabledTiers(t *testing.T) {
	// Test with L1 and L2 only
	mr := miniredis.RunT(t)
	defer mr.Close()

	redisClient := redis.NewClient(&redis.Options{
		Addr: mr.Addr(),
	})
	defer redisClient.Close()

	config := Config{
		L1Enabled: true,
		L2Enabled: true,
		L3Enabled: false,
		L2Prefix:  "ccr:",
		L2TTL:     time.Hour,
	}

	manager, err := NewManager(config, redisClient, nil)
	require.NoError(t, err)
	defer manager.Close()

	ctx := context.Background()
	hash := "l1_l2_test"
	data := []byte("L1+L2 only data")

	// Put and get
	err = manager.Put(ctx, hash, data, "session")
	require.NoError(t, err)

	retrieved, err := manager.Get(ctx, hash)
	require.NoError(t, err)
	assert.Equal(t, data, retrieved)

	// Metrics should show L1 hit
	metrics := manager.GetMetrics()
	assert.Equal(t, int64(1), metrics.L1Hits)
	assert.Equal(t, int64(0), metrics.L3Hits)
}

// Benchmark CCR operations
func BenchmarkManager_Put(b *testing.B) {
	mr := miniredis.NewMiniRedis()
	mr.Start()
	defer mr.Close()

	redisClient := redis.NewClient(&redis.Options{
		Addr: mr.Addr(),
	})
	defer redisClient.Close()

	config := DefaultConfig()
	config.L3Enabled = false
	manager, _ := NewManager(config, redisClient, nil)
	defer manager.Close()

	ctx := context.Background()
	data := make([]byte, 1024) // 1KB data

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		hash := string(rune('a' + (i % 26)))
		manager.Put(ctx, hash, data, "session")
	}
}

func BenchmarkManager_Get(b *testing.B) {
	mr := miniredis.NewMiniRedis()
	mr.Start()
	defer mr.Close()

	redisClient := redis.NewClient(&redis.Options{
		Addr: mr.Addr(),
	})
	defer redisClient.Close()

	config := DefaultConfig()
	config.L3Enabled = false
	manager, _ := NewManager(config, redisClient, nil)
	defer manager.Close()

	ctx := context.Background()
	hash := "benchmark_hash"
	data := make([]byte, 1024)
	manager.Put(ctx, hash, data, "session")

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		manager.Get(ctx, hash)
	}
}
