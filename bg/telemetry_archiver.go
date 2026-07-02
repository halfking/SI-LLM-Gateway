// Package bg — telemetry archiver.
//
// TelemetryArchiver is a background worker that handles monthly archival
// of telemetry tables to columnar storage and daily cleanup of old data.
//
// Archival schedule:
//  - Monthly (day 1, 2AM): archive_request_logs, archive_routing_decision_log,
//    archive_credential_model_index
//  - Daily (3AM): cleanup_old_credential_model_index (removes 7d+ data)
//  - Weekly (Mon 1:30AM): ensure_next_month_*_partition() for each telemetry
//    parent — pre-creates next-month partitions as columnar so writes never
//    land in heap partitions.
//  - Gateway startup: ensure_next_month_*_partition() runs once idempotently.
//
// Architecture:
//  - request_logs: monthly heap → columnar migration
//  - routing_decision_log: monthly heap → columnar migration
//  - credential_model_index: 7-day retention in heap, monthly columnar archival
//  - request_wal: monthly heap → columnar migration
//  - All telemetry partition tables use citus_columnar with zstd level 9
//    (set in migration 999). See deploy/sql/migrations/999_columnar_backfill_and_enforce.sql.
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
	slog.Info("telemetry_archiver: started (monthly archival + daily cleanup + ensure-next-month scheduler)")

	// Run ensure_next_month once at startup so a freshly-deployed gateway
	// doesn't have to wait up to a week for the Mon 1:30AM tick.
	go func() {
		bootCtx, bootCancel := context.WithTimeout(childCtx, 2*time.Minute)
		defer bootCancel()
		if err := a.ensureNextMonthPartitions(bootCtx); err != nil {
			slog.Warn("telemetry_archiver: startup ensure_next_month failed",
				"error", err)
		}
	}()
}

func (a *TelemetryArchiver) run(ctx context.Context) {
	defer close(a.done)

	// Check every hour for scheduled tasks
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	// Track last execution times to prevent duplicate runs
	var lastMonthlyArchive time.Time
	var lastDailyCleanup time.Time
	var lastWeeklyEnsure time.Time

	for {
		select {
		case <-ctx.Done():
			slog.Info("telemetry_archiver: shutting down")
			return
		case now := <-ticker.C:
			// Monthly archival: day 1, hour 2 (2AM UTC)
			if now.Day() == 1 && now.Hour() == 2 {
				if now.Sub(lastMonthlyArchive) > 50*time.Minute {
					lastMonthlyArchive = now
					a.archiveLastMonth(ctx)
				}
			}

			// Daily cleanup: hour 3 (3AM UTC)
			if now.Hour() == 3 {
				if now.Sub(lastDailyCleanup) > 50*time.Minute {
					lastDailyCleanup = now
					a.runDailyCleanup(ctx)
				}
			}

			// Weekly ensure-next-month partitions: Monday 01:30 UTC.
			// Pre-creates next-month columnar partitions for all telemetry
			// parents so writes never have to land in a heap partition.
			if now.Weekday() == time.Monday && now.Hour() == 1 && now.Minute() < 30 {
				if now.Sub(lastWeeklyEnsure) > 6*24*time.Hour {
					lastWeeklyEnsure = now
					ensureCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
					if err := a.ensureNextMonthPartitions(ensureCtx); err != nil {
						slog.Error("telemetry_archiver: weekly ensure_next_month failed",
							"error", err)
					}
					cancel()
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

	// Archive request_logs
	if err := a.archiveTable(ctx, "archive_request_logs", archiveMonth); err != nil {
		slog.Error("telemetry_archiver: request_logs archival failed",
			"error", err,
			"month", archiveMonth.Format("2006-01"))
	}

	// Archive routing_decision_log
	if err := a.archiveTable(ctx, "archive_routing_decision_log", archiveMonth); err != nil {
		slog.Error("telemetry_archiver: routing_decision_log archival failed",
			"error", err,
			"month", archiveMonth.Format("2006-01"))
	}

	// Archive credential_model_index (different signature)
	if err := a.archiveCredentialModelIndex(ctx, archiveMonth); err != nil {
		slog.Error("telemetry_archiver: credential_model_index archival failed",
			"error", err,
			"month", archiveMonth.Format("2006-01"))
	}

	// Archive request_wal (different signature; archive_request_wal returns
	// TABLE(status, rows_migrated, partition_dropped)).
	if err := a.archiveRequestWal(ctx, archiveMonth); err != nil {
		slog.Error("telemetry_archiver: request_wal archival failed",
			"error", err,
			"month", archiveMonth.Format("2006-01"))
	}

	slog.Info("telemetry_archiver: monthly archival complete",
		"archive_month", archiveMonth.Format("2006-01"))
}

// runDailyCleanup performs daily cleanup tasks.
func (a *TelemetryArchiver) runDailyCleanup(ctx context.Context) {
	slog.Info("telemetry_archiver: starting daily cleanup", "trigger", "scheduled")

	if err := a.cleanupCredentialModelIndex(ctx); err != nil {
		slog.Error("telemetry_archiver: credential_model_index cleanup failed",
			"error", err)
	}

	slog.Info("telemetry_archiver: daily cleanup complete")
}

// ensureNextMonthPartitions pre-creates next-month columnar partitions for
// every telemetry parent. Each helper function is idempotent (it checks for
// existing partitions before creating new ones) so this is safe to call from
// both the weekly tick and the startup hook.
func (a *TelemetryArchiver) ensureNextMonthPartitions(ctx context.Context) error {
	helpers := []string{
		"ensure_next_month_archive_partition",
		"ensure_next_month_routing_archive_partition",
		"ensure_next_month_cmi_archive_partition",
		"ensure_next_month_request_wal_partition",
	}
	for _, fn := range helpers {
		callCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		_, err := a.db.Exec(callCtx, fmt.Sprintf("SELECT %s()", fn))
		cancel()
		if err != nil {
			slog.Error("telemetry_archiver: ensure_next_month failed",
				"function", fn, "error", err)
			// continue with the next helper; do not abort the whole sweep
			continue
		}
		slog.Info("telemetry_archiver: ensured next-month partition",
			"function", fn)
	}
	return nil
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

// archiveRequestWal archives one month of request_wal data into the
// request_wal_archive columnar parent. Same return shape as archiveTable.
func (a *TelemetryArchiver) archiveRequestWal(ctx context.Context, archiveMonth time.Time) error {
	archiveCtx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()

	var status string
	var rowsMigrated int64
	var partitionDropped bool

	err := a.db.QueryRow(archiveCtx,
		"SELECT * FROM archive_request_wal($1)",
		archiveMonth,
	).Scan(&status, &rowsMigrated, &partitionDropped)

	if err != nil {
		return fmt.Errorf("archive failed: %w", err)
	}

	slog.Info("telemetry_archiver: request_wal archived",
		"status", status,
		"rows_migrated", rowsMigrated,
		"partition_dropped", partitionDropped,
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
