package sessions

import (
	"context"
	"testing"
	"time"
)

func TestSessionManager_Create(t *testing.T) {
	rc := newTestRedis(t)
	defer rc.Close()
	sm := NewManager(NewRedisClient(redisAddr(), "", 0), 1*time.Hour)
	ctx := context.Background()

	session, err := sm.Create(ctx, 1, "default", "device-1")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	if session.SessionID == "" {
		t.Fatal("expected non-empty session_id")
	}
	if session.APIKeyID != 1 {
		t.Errorf("expected api_key_id=1, got %d", session.APIKeyID)
	}
	if session.TenantID != "default" {
		t.Errorf("expected tenant_id=default, got %s", session.TenantID)
	}

	// Cleanup
	_ = sm.Delete(ctx, session.SessionID)
}

func TestSessionManager_GetExpired(t *testing.T) {
	rc := newTestRedis(t)
	defer rc.Close()
	sm := NewManager(NewRedisClient(redisAddr(), "", 0), 2*time.Second) // Redis min TTL is 1s
	ctx := context.Background()

	session, err := sm.Create(ctx, 2, "default", "device-1")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	defer sm.Delete(ctx, session.SessionID)

	// Wait for expiry
	time.Sleep(2500 * time.Millisecond)

	_, err = sm.Get(ctx, session.SessionID)
	if err != ErrSessionExpired {
		t.Errorf("expected ErrSessionExpired, got %v", err)
	}
}

func TestSessionManager_Touch_RefreshesExpiry(t *testing.T) {
	rc := newTestRedis(t)
	defer rc.Close()
	sm := NewManager(NewRedisClient(redisAddr(), "", 0), 3*time.Second) // Redis min TTL is 1s
	ctx := context.Background()

	session, err := sm.Create(ctx, 3, "default", "device-1")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	defer sm.Delete(ctx, session.SessionID)

	// Wait 2s (before expiry at 3s)
	time.Sleep(2 * time.Second)

	// Touch to refresh expiry
	if err := sm.Touch(ctx, session.SessionID); err != nil {
		t.Fatalf("Touch failed: %v", err)
	}

	// Wait another 2s (total 4s from creation, but only 2s since Touch)
	time.Sleep(2 * time.Second)

	// Session should still be valid because Touch extended expires_at
	retrieved, err := sm.Get(ctx, session.SessionID)
	if err != nil {
		t.Fatalf("expected session to be valid after Touch, got error: %v", err)
	}
	if retrieved.SessionID != session.SessionID {
		t.Errorf("expected session_id=%s, got %s", session.SessionID, retrieved.SessionID)
	}
}

func TestSessionManager_Touch_UpdatesLastActive(t *testing.T) {
	rc := newTestRedis(t)
	defer rc.Close()
	sm := NewManager(NewRedisClient(redisAddr(), "", 0), 1*time.Hour)
	ctx := context.Background()

	session, err := sm.Create(ctx, 4, "default", "device-1")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	defer sm.Delete(ctx, session.SessionID)

	originalLastActive := session.LastActive

	time.Sleep(1100 * time.Millisecond) // Wait > 1s to ensure visible difference

	if err := sm.Touch(ctx, session.SessionID); err != nil {
		t.Fatalf("Touch failed: %v", err)
	}

	retrieved, err := sm.Get(ctx, session.SessionID)
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}

	// RFC3339 time format has second precision, so we just verify last_active moved forward
	// (allowing for rounding/truncation to the nearest second)
	if !retrieved.LastActive.After(originalLastActive) && !retrieved.LastActive.Equal(originalLastActive.Truncate(time.Second).Add(time.Second)) {
		t.Errorf("expected last_active to be updated after Touch, got %v (original: %v)",
			retrieved.LastActive, originalLastActive)
	}
}

func TestSessionManager_Migrate(t *testing.T) {
	rc := newTestRedis(t)
	defer rc.Close()
	sm := NewManager(NewRedisClient(redisAddr(), "", 0), 1*time.Hour)
	ctx := context.Background()

	session, err := sm.Create(ctx, 5, "default", "device-1")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	defer sm.Delete(ctx, session.SessionID)

	if len(session.Devices) != 1 {
		t.Fatalf("expected 1 device, got %d", len(session.Devices))
	}

	migrated, err := sm.Migrate(ctx, session.SessionID, "device-2")
	if err != nil {
		t.Fatalf("Migrate failed: %v", err)
	}

	if len(migrated.Devices) != 2 {
		t.Errorf("expected 2 devices after migration, got %d", len(migrated.Devices))
	}
}

func TestSessionManager_BindAPIKey(t *testing.T) {
	rc := newTestRedis(t)
	defer rc.Close()
	sm := NewManager(NewRedisClient(redisAddr(), "", 0), 1*time.Hour)
	ctx := context.Background()

	// Create orphan session (api_key_id=0)
	session, err := sm.Create(ctx, 0, "", "device-1")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}
	defer sm.Delete(ctx, session.SessionID)

	if err := sm.BindAPIKey(ctx, session.SessionID, 100, "tenant-bound"); err != nil {
		t.Fatalf("BindAPIKey failed: %v", err)
	}

	retrieved, err := sm.Get(ctx, session.SessionID)
	if err != nil {
		t.Fatalf("Get failed: %v", err)
	}
	if retrieved.APIKeyID != 100 {
		t.Errorf("expected api_key_id=100, got %d", retrieved.APIKeyID)
	}
	if retrieved.TenantID != "tenant-bound" {
		t.Errorf("expected tenant_id=tenant-bound, got %s", retrieved.TenantID)
	}
}

func TestSessionManager_Delete(t *testing.T) {
	rc := newTestRedis(t)
	defer rc.Close()
	sm := NewManager(NewRedisClient(redisAddr(), "", 0), 1*time.Hour)
	ctx := context.Background()

	session, err := sm.Create(ctx, 6, "default", "device-1")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}

	if err := sm.Delete(ctx, session.SessionID); err != nil {
		t.Fatalf("Delete failed: %v", err)
	}

	_, err = sm.Get(ctx, session.SessionID)
	if err != ErrSessionNotFound {
		t.Errorf("expected ErrSessionNotFound after Delete, got %v", err)
	}
}

func TestSessionManager_CreateV2(t *testing.T) {
	rc := newTestRedis(t)
	defer rc.Close()
	sm := NewManager(NewRedisClient(redisAddr(), "", 0), 1*time.Hour)
	ctx := context.Background()

	session, err := sm.CreateV2(ctx, 10, "tenant-v2", "device-1", "task-abc")
	if err != nil {
		t.Fatalf("CreateV2 failed: %v", err)
	}
	defer sm.Delete(ctx, session.SessionID)

	if session.Namespace != "gw" {
		t.Errorf("expected namespace=gw, got %s", session.Namespace)
	}
	if session.TaskID != "task-abc" {
		t.Errorf("expected task_id=task-abc, got %s", session.TaskID)
	}
	if session.SessionID == "" || session.SessionID[:3] != "gw_" {
		t.Errorf("expected session_id to start with gw_, got %s", session.SessionID)
	}
}
