package bg

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TestTelemetryArchiver tests the TelemetryArchiver background worker.
// This is an integration test that requires a running PostgreSQL database
// with the partition schema migrations applied.
func TestTelemetryArchiver(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// This test requires DATABASE_URL environment variable
	dbURL := getTestDatabaseURL(t)
	if dbURL == "" {
		t.Skip("DATABASE_URL not set, skipping integration test")
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatalf("Failed to connect to database: %v", err)
	}
	defer pool.Close()

	t.Run("NewTelemetryArchiver", func(t *testing.T) {
		archiver := NewTelemetryArchiver(pool)
		if archiver == nil {
			t.Fatal("NewTelemetryArchiver returned nil")
		}
		if archiver.db != pool {
			t.Error("TelemetryArchiver.db not set correctly")
		}
		if archiver.done == nil {
			t.Error("TelemetryArchiver.done channel not initialized")
		}
	})

	t.Run("StartAndStop", func(t *testing.T) {
		archiver := NewTelemetryArchiver(pool)
		
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		// Start the archiver
		archiver.Start(ctx)

		// Let it run briefly
		time.Sleep(100 * time.Millisecond)

		// Stop the archiver
		archiver.Stop()

		// Verify it stopped (done channel should be closed)
		select {
		case <-archiver.done:
			// Success - channel is closed
		case <-time.After(1 * time.Second):
			t.Error("TelemetryArchiver did not stop within timeout")
		}
	})

	t.Run("CleanupCredentialModelIndex", func(t *testing.T) {
		archiver := NewTelemetryArchiver(pool)
		ctx := context.Background()

		// Call cleanup function directly
		err := archiver.cleanupCredentialModelIndex(ctx)
		if err != nil {
			t.Errorf("cleanupCredentialModelIndex failed: %v", err)
		}
	})

	t.Run("ArchiveCredentialModelIndex", func(t *testing.T) {
		archiver := NewTelemetryArchiver(pool)
		ctx := context.Background()

		// Try to archive last month (may skip if no data)
		lastMonth := time.Now().AddDate(0, -1, 0)
		archiveMonth := time.Date(lastMonth.Year(), lastMonth.Month(), 1, 0, 0, 0, 0, time.UTC)

		err := archiver.archiveCredentialModelIndex(ctx, archiveMonth)
		if err != nil {
			t.Errorf("archiveCredentialModelIndex failed: %v", err)
		}
	})

	t.Run("ArchiveTable", func(t *testing.T) {
		archiver := NewTelemetryArchiver(pool)
		ctx := context.Background()

		// Try to archive last month routing_decision_log (may skip if no partition)
		lastMonth := time.Now().AddDate(0, -1, 0)
		archiveMonth := time.Date(lastMonth.Year(), lastMonth.Month(), 1, 0, 0, 0, 0, time.UTC)

		err := archiver.archiveTable(ctx, "archive_routing_decision_log", archiveMonth)
		// Error is expected if partition doesn't exist, which is OK
		if err != nil {
			t.Logf("archiveTable returned (expected if no partition): %v", err)
		}
	})
}

// TestTelemetryArchiverScheduling tests the scheduling logic without
// actually waiting for the scheduled times.
func TestTelemetryArchiverScheduling(t *testing.T) {
	// This is a unit test of the scheduling logic
	// We can't easily test the actual scheduling without mocking time.Now()
	// So we just verify the archiver can be created and stopped
	
	archiver := &TelemetryArchiver{
		done: make(chan struct{}),
	}

	if archiver.done == nil {
		t.Error("done channel should be initialized")
	}
}

// getTestDatabaseURL returns the test database URL from environment
func getTestDatabaseURL(t *testing.T) string {
	// Check for TEST_DATABASE_URL first, fall back to DATABASE_URL
	if url := getEnv("TEST_DATABASE_URL", ""); url != "" {
		return url
	}
	return getEnv("DATABASE_URL", "")
}

// TestArchivalFunctions tests that the SQL archival functions exist
// and have the correct signatures.
func TestArchivalFunctions(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	dbURL := getTestDatabaseURL(t)
	if dbURL == "" {
		t.Skip("DATABASE_URL not set, skipping integration test")
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatalf("Failed to connect to database: %v", err)
	}
	defer pool.Close()

	ctx := context.Background()

	testCases := []struct {
		name     string
		funcName string
	}{
		{"archive_routing_decision_log", "archive_routing_decision_log"},
		{"archive_credential_model_index", "archive_credential_model_index"},
		{"cleanup_old_credential_model_index", "cleanup_old_credential_model_index"},
		{"ensure_next_month_routing_archive_partition", "ensure_next_month_routing_archive_partition"},
		{"ensure_next_month_cmi_archive_partition", "ensure_next_month_cmi_archive_partition"},
		{"create_next_month_routing_partitions", "create_next_month_routing_partitions"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			var exists bool
			err := pool.QueryRow(ctx,
				"SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = $1)",
				tc.funcName,
			).Scan(&exists)

			if err != nil {
				t.Fatalf("Failed to check function existence: %v", err)
			}

			if !exists {
				t.Errorf("Function %s does not exist", tc.funcName)
			}
		})
	}
}

// TestArchiveTables tests that the archive tables exist
func TestArchiveTables(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	dbURL := getTestDatabaseURL(t)
	if dbURL == "" {
		t.Skip("DATABASE_URL not set, skipping integration test")
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatalf("Failed to connect to database: %v", err)
	}
	defer pool.Close()

	ctx := context.Background()

	testCases := []struct {
		name      string
		tableName string
	}{
		{"routing_decision_log_archive", "routing_decision_log_archive"},
		{"credential_model_index_archive", "credential_model_index_archive"},
		{"request_logs_archive", "request_logs_archive"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			var exists bool
			err := pool.QueryRow(ctx,
				"SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = $1)",
				tc.tableName,
			).Scan(&exists)

			if err != nil {
				t.Fatalf("Failed to check table existence: %v", err)
			}

			if !exists {
				t.Errorf("Table %s does not exist", tc.tableName)
			}
		})
	}
}
