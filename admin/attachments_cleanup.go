package admin

import (
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// CleanupAttachmentsRequest defines the cleanup request parameters
type CleanupAttachmentsRequest struct {
	DryRun         bool `json:"dry_run"`
	OlderThanDays  int  `json:"older_than_days"`
	OrphanedOnly   bool `json:"orphaned_only"`
}

// CleanupAttachmentsResponse defines the cleanup response
type CleanupAttachmentsResponse struct {
	AffectedFiles         int    `json:"affected_files"`
	AffectedDBRows        int    `json:"affected_db_rows"`
	EstimatedFreedBytes   int64  `json:"estimated_freed_bytes"`
	EstimatedFreedHuman   string `json:"estimated_freed_human"`
	OrphanedFiles         int    `json:"orphaned_files"`
	OrphanedSizeBytes     int64  `json:"orphaned_size_bytes"`
	WarningMessage        string `json:"warning_message,omitempty"`
	ExecutedAt            string `json:"executed_at,omitempty"`
}

// POST /api/admin/data-lifecycle/cleanup-attachments
// Preview or execute attachment cleanup
func (h *Handler) handleCleanupAttachments(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req CleanupAttachmentsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Default to 90 days if not specified
	if req.OlderThanDays == 0 {
		req.OlderThanDays = 90
	}

	// Validate parameters
	if req.OlderThanDays < 7 {
		writeError(w, http.StatusBadRequest, "older_than_days must be at least 7")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Minute)
	defer cancel()

	resp := &CleanupAttachmentsResponse{}

	if req.OrphanedOnly {
		// Clean up orphaned files only
		if err := h.cleanupOrphanedAttachments(ctx, req.DryRun, resp); err != nil {
			slog.Error("failed to cleanup orphaned attachments", "error", err)
			writeError(w, http.StatusInternalServerError, fmt.Sprintf("cleanup failed: %v", err))
			return
		}
	} else {
		// Clean up old attachments
		if err := h.cleanupOldAttachments(ctx, req.OlderThanDays, req.DryRun, resp); err != nil {
			slog.Error("failed to cleanup old attachments", "error", err)
			writeError(w, http.StatusInternalServerError, fmt.Sprintf("cleanup failed: %v", err))
			return
		}
	}

	if !req.DryRun {
		resp.ExecutedAt = time.Now().UTC().Format(time.RFC3339)
	}

	if resp.AffectedFiles == 0 && resp.OrphanedFiles == 0 {
		resp.WarningMessage = "没有需要清理的附件"
	} else if resp.AffectedFiles > 10000 {
		resp.WarningMessage = "影响文件数超过 1 万，建议分批执行"
	}

	w.Header().Set("Content-Type", "application/json")
	//nolint:errcheck // HTTP write error non-recoverable
	json.NewEncoder(w).Encode(resp)
}

// cleanupOldAttachments cleans up attachments older than specified days
func (h *Handler) cleanupOldAttachments(ctx context.Context, olderThanDays int, dryRun bool, resp *CleanupAttachmentsResponse) error {
	storagePath := os.Getenv("ATTACHMENT_STORAGE_PATH")
	if storagePath == "" {
		storagePath = "/opt/llm-gateway-go/data/attachments"
	}

	// First, get the list of attachments to clean up
	cutoffDate := time.Now().UTC().Add(-time.Duration(olderThanDays) * 24 * time.Hour)

	// 2026-07-02: column is `file_path`, not `storage_path` (per the
	// attachments table schema; `storage_path` was a pre-existing field
	// name used by an earlier draft of this handler).
	rows, err := h.db.Query(ctx, `
		SELECT id, file_path, file_size
		FROM attachments
		WHERE created_at < $1
		ORDER BY created_at
	`, cutoffDate)

	if err != nil {
		return fmt.Errorf("failed to query old attachments: %w", err)
	}
	defer rows.Close()

	type attachmentInfo struct {
		id          string
		storagePath string
		fileSize    int64
	}

	var toDelete []attachmentInfo
	var totalSize int64

	for rows.Next() {
		var info attachmentInfo
		if err := rows.Scan(&info.id, &info.storagePath, &info.fileSize); err != nil {
			slog.Warn("failed to scan attachment row", "error", err)
			continue
		}
		toDelete = append(toDelete, info)
		totalSize += info.fileSize
	}

	resp.AffectedFiles = len(toDelete)
	resp.AffectedDBRows = len(toDelete)
	resp.EstimatedFreedBytes = totalSize
	resp.EstimatedFreedHuman = formatBytes(totalSize)

	if dryRun {
		slog.Info("cleanup preview: old attachments",
			"count", len(toDelete),
			"size", formatBytes(totalSize),
			"older_than_days", olderThanDays)
		return nil
	}

	// Execute cleanup
	tx, err := h.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	deletedCount := 0
	deletedSize := int64(0)

	for _, info := range toDelete {
		// Delete file from disk
		fullPath := filepath.Join(storagePath, info.storagePath)
		if err := os.Remove(fullPath); err != nil {
			if !os.IsNotExist(err) {
				slog.Warn("failed to delete attachment file", "path", fullPath, "error", err)
			}
			// Continue even if file deletion fails
		}

		// Delete from database
		_, err := tx.Exec(ctx, `DELETE FROM attachments WHERE id = $1`, info.id)
		if err != nil {
			slog.Warn("failed to delete attachment record", "id", info.id, "error", err)
			continue
		}

		deletedCount++
		deletedSize += info.fileSize
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	slog.Info("cleanup completed: old attachments",
		"deleted_count", deletedCount,
		"deleted_size", formatBytes(deletedSize),
		"older_than_days", olderThanDays)

	resp.AffectedFiles = deletedCount
	resp.AffectedDBRows = deletedCount
	resp.EstimatedFreedBytes = deletedSize
	resp.EstimatedFreedHuman = formatBytes(deletedSize)

	return nil
}

// cleanupOrphanedAttachments cleans up orphaned files (files without database records)
func (h *Handler) cleanupOrphanedAttachments(ctx context.Context, dryRun bool, resp *CleanupAttachmentsResponse) error {
	storagePath := os.Getenv("ATTACHMENT_STORAGE_PATH")
	if storagePath == "" {
		storagePath = "/opt/llm-gateway-go/data/attachments"
	}

	// Get all attachment IDs and paths from database
	rows, err := h.db.Query(ctx, `SELECT id, file_path FROM attachments`)
	if err != nil {
		return fmt.Errorf("failed to query attachments: %w", err)
	}
	defer rows.Close()

	dbPaths := make(map[string]bool)
	for rows.Next() {
		var id, path string
		if err := rows.Scan(&id, &path); err != nil {
			continue
		}
		dbPaths[path] = true
	}

	// Scan storage directory for orphaned files
	var orphanedFiles []string
	var orphanedSize int64

	err = filepath.WalkDir(storagePath, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}

		relPath, err := filepath.Rel(storagePath, path)
		if err != nil {
			return nil
		}

		// Check if this file is in database
		if !dbPaths[relPath] {
			orphanedFiles = append(orphanedFiles, path)
			
			// Get file size
			if info, err := d.Info(); err == nil {
				orphanedSize += info.Size()
			}
		}

		return nil
	})

	if err != nil {
		return fmt.Errorf("failed to walk storage directory: %w", err)
	}

	resp.OrphanedFiles = len(orphanedFiles)
	resp.OrphanedSizeBytes = orphanedSize
	resp.EstimatedFreedBytes = orphanedSize
	resp.EstimatedFreedHuman = formatBytes(orphanedSize)

	if dryRun {
		slog.Info("cleanup preview: orphaned attachments",
			"count", len(orphanedFiles),
			"size", formatBytes(orphanedSize))
		return nil
	}

	// Execute cleanup
	deletedCount := 0
	deletedSize := int64(0)

	for _, path := range orphanedFiles {
		info, err := os.Stat(path)
		if err != nil {
			continue
		}

		if err := os.Remove(path); err != nil {
			slog.Warn("failed to delete orphaned file", "path", path, "error", err)
			continue
		}

		deletedCount++
		deletedSize += info.Size()
	}

	slog.Info("cleanup completed: orphaned attachments",
		"deleted_count", deletedCount,
		"deleted_size", formatBytes(deletedSize))

	resp.OrphanedFiles = deletedCount
	resp.OrphanedSizeBytes = deletedSize
	resp.EstimatedFreedBytes = deletedSize
	resp.EstimatedFreedHuman = formatBytes(deletedSize)

	return nil
}

// POST /api/admin/data-lifecycle/config
// Update lifecycle configuration
func (h *Handler) handleUpdateLifecycleConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodPut {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var config LifecycleConfig
	if err := json.NewDecoder(r.Body).Decode(&config); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Validate configuration
	if config.RetentionDays < 7 {
		writeError(w, http.StatusBadRequest, "retention_days must be at least 7")
		return
	}

	if config.MaxAttachmentSizeMB < 1 || config.MaxAttachmentSizeMB > 100 {
		writeError(w, http.StatusBadRequest, "max_attachment_size_mb must be between 1 and 100")
		return
	}

	// TODO: Save configuration to settings table
	// For now, just return success
	slog.Info("lifecycle config updated",
		"retention_days", config.RetentionDays,
		"auto_cleanup_enabled", config.AutoCleanupEnabled,
		"cleanup_schedule", config.CleanupSchedule)

	w.Header().Set("Content-Type", "application/json")
	//nolint:errcheck // HTTP write error non-recoverable
	json.NewEncoder(w).Encode(map[string]any{
		"success": true,
		"message": "配置已更新（注意：当前版本配置不持久化，重启后恢复默认值）",
		"config": config,
	})
}
