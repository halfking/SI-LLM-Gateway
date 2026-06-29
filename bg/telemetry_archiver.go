// Package bg — telemetry archiver.
//
// TelemetryArchiver is a background worker that handles monthly archival
// of telemetry tables to columnar storage and daily cleanup of old data.
//
// Archival schedule:
//  - Monthly (day 1, 2AM): archive_request_logs, archive_routing_decision_log
//  - Daily (3AM): cleanup_old_credential_model_index (removes 7d+ data)
//  - Monthly (day 1, 2:30AM): archive_credential_model_index (7d+ data to columnar)
//
// Architecture:
//  - request_logs: monthly heap → columnar migration (existing)
//  - routing_decision_log: monthly heap → columnar migration (new)
//  - credential_model_index: 7-day retention in heap, monthly columnar archival (new)
//
// Storage benefits:
//  - Columnar compression: 80-90% space savings
//  - Query performance: partition pruning on time ranges
//  - Automatic maintenance: no manual intervention required
//
// Co-authored-by: Cursor <cursoragent@cursor.com>
package bg

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TelemetryArchiver handles monthly archival of telemetry tables
// to columnar storage and daily cleanup of old data.
type TelemetryArchiver struct {
	db     *pgxpool.Pool
	cancel context.CancelFunc
	done   chan struct{}
}

// NewTelemetryArchiver creates a new telemetry archiver.
func NewTelemetryArchiver(db *pgxpool.Pool) *TelemetryArchiver {
	return &TelemetryArchiver{
		db:   db,
		done: make(chan struct{}),
	}
}

// Start begins the archival scheduler. Runs in background goroutine.
func (a *TelemetryArchiver) Start(ctx context.Context) {
	childCtx, cancel := context.WithCancel(ctx)
	a.cancel = cancel

	go a.run(childCtx)
	slog.Info("telemetry_archiver: started (monthly archival + daily cleanup scheduler)")
}

func (a *TelemetryArchiver) run(ctx context.Context) {
	defer close(a.done)

	// Check every hour for scheduled tasks
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	// Track last execution times to prevent duplicate runs
	var lastMonthlyArchive time.Time
	var lastDailyCleanup time.Time

	for {
		select {
		case <-ctx.Done():
			slog.Info("telemetry_archiver: shutting down")
			return
		case now := <-ticker.C:
			// Monthly archival: day 1, hour 2 (2AM)
			if now.Day() == 1 && now.Hour() == 2 {
				// Prevent duplicate runs within the same hour
				if now.Sub(lastMonthlyArchive) > 50*time.Minute {
					lastMonthlyArchive = now
					a.archiveLastMonth(ctx)
				}
			}

			// Daily cleanup: hour 3 (3AM)
			if now.Hour() == 3 {
				// Prevent duplicate runs within the same hour
				if now.Sub(lastDailyCleanup) > 50*time.Minute {
					lastDailyCleanup = now
					a.runDailyCleanup(ctx)
				}
			}
		}
	}
}

// archiveLastMonth performs monthly archival of all telemetry tables.
func (a *TelemetryArchiver) archiveLastMonth(ctx context.Context) {
	lastMonth := time.Now().AddDate(0, -1, 0)
	archiveMonth := time.Date(lastMonth.Year(), lastMonth.Month(), 1, 0, 0, 0, 0, time.UTC)

	slog.Info("telemetry_archiver: starting monthly archival",
		"archive_month", archiveMonth.Format("2006-01"),
		"trigger", "scheduled")

	// Archive request_logs (existing table)
	if err := a.archiveTable(ctx, "archive_request_logs", archiveMonth); err != nil {
		slog.Error("telemetry_archiver: request_logs archival failed",
			"error", err,
			"month", archiveMonth.Format("2006-01"))
	}

	// Archive routing_decision_log (new)
	if err := a.archiveTable(ctx, "archive_routing_decision_log", archiveMonth); err != nil {
		slog.Error("telemetry_archiver: routing_decision_log archival failed",
			"error", err,
			"month", archiveMonth.Format("2006-01"))
	}

	// Archive credential_model_index (new, different signature)
	if err := a.archiveCredentialModelIndex(ctx, archiveMonth); err != nil {
		slog.Error("telemetry_archiver: credential_model_index archival failed",
			"error", err,
			"month", archiveMonth.Format("2006-01"))
	}

	slog.Info("telemetry_archiver: monthly archival complete",
		"archive_month", archiveMonth.Format("2006-01"))
}

// runDailyCleanup performs daily cleanup tasks.
func (a *TelemetryArchiver) runDailyCleanup(ctx context.Context) {
	slog.Info("telemetry_archiver: starting daily cleanup", "trigger", "scheduled")

	// Cleanup credential_model_index (remove 7d+ data)
	if err := a.cleanupCredentialModelIndex(ctx); err != nil {
		slog.Error("telemetry_archiver: credential_model_index cleanup failed",
			"error", err)
	}

	slog.Info("telemetry_archiver: daily cleanup complete")
}

// archiveTable archives one month of data for request_logs or routing_decision_log.
func (a *TelemetryArchiver) archiveTable(ctx context.Context, funcName string, archiveMonth time.Time) error {
	archiveCtx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()

	var status string
	var rowsMigrated int64
	var partitionDropped bool

	err := a.db.QueryRow(archiveCtx,
		fmt.Sprintf("SELECT * FROM %s($1)", funcName),
		archiveMonth,
	).Scan(&status, &rowsMigrated, &partitionDropped)

	if err != nil {
		return fmt.Errorf("archive failed: %w", err)
	}

	slog.Info("telemetry_archiver: table archived",
		"function", funcName,
		"status", status,
		"rows_migrated", rowsMigrated,
		"partition_dropped", partitionDropped,
		"month", archiveMonth.Format("2006-01"))

	return nil
}

// archiveCredentialModelIndex archives 7d+ data for credential_model_index.
// Returns (status, rows_archived, rows_deleted).
func (a *TelemetryArchiver) archiveCredentialModelIndex(ctx context.Context, archiveMonth time.Time) error {
	archiveCtx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()

	var status string
	var rowsArchived int64
	var rowsDeleted int64

	err := a.db.QueryRow(archiveCtx,
		"SELECT * FROM archive_credential_model_index($1)",
		archiveMonth,
	).Scan(&status, &rowsArchived, &rowsDeleted)

	if err != nil {
		return fmt.Errorf("archive failed: %w", err)
	}

	slog.Info("telemetry_archiver: credential_model_index archived",
		"status", status,
		"rows_archived", rowsArchived,
		"rows_deleted", rowsDeleted,
		"month", archiveMonth.Format("2006-01"))

	return nil
}

// cleanupCredentialModelIndex removes data older than 7 days from main table.
func (a *TelemetryArchiver) cleanupCredentialModelIndex(ctx context.Context) error {
	cleanupCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	var deleted int64
	err := a.db.QueryRow(cleanupCtx,
		"SELECT cleanup_old_credential_model_index()",
	).Scan(&deleted)

	if err != nil {
		return fmt.Errorf("cleanup failed: %w", err)
	}

	if deleted > 0 {
		slog.Info("telemetry_archiver: credential_model_index cleanup complete",
			"rows_deleted", deleted)
	} else {
		slog.Debug("telemetry_archiver: credential_model_index cleanup complete (no old data)")
	}

	return nil
}

// Stop gracefully shuts down the archiver.
func (a *TelemetryArchiver) Stop() {
	if a.cancel != nil {
		a.cancel()
	}
	<-a.done
	slog.Info("telemetry_archiver: stopped")
}
