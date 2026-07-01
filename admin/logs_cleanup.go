package admin

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// CleanupLogsRequest defines the log cleanup request parameters
type CleanupLogsRequest struct {
	DryRun        bool `json:"dry_run"`
	OlderThanDays int  `json:"older_than_days"`
	CompressedOnly bool `json:"compressed_only"`
}

// CleanupLogsResponse defines the log cleanup response
type CleanupLogsResponse struct {
	AffectedFiles       int    `json:"affected_files"`
	EstimatedFreedBytes int64  `json:"estimated_freed_bytes"`
	EstimatedFreedHuman string `json:"estimated_freed_human"`
	WarningMessage      string `json:"warning_message,omitempty"`
	ExecutedAt          string `json:"executed_at,omitempty"`
}

// POST /api/admin/data-lifecycle/cleanup-logs
// Preview or execute log file cleanup
func (h *Handler) handleCleanupLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var req CleanupLogsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Default to 30 days if not specified
	if req.OlderThanDays == 0 {
		req.OlderThanDays = 30
	}

	// Validate parameters
	if req.OlderThanDays < 7 {
		writeError(w, http.StatusBadRequest, "older_than_days must be at least 7")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Minute)
	defer cancel()

	resp := &CleanupLogsResponse{}

	if err := h.cleanupOldLogFiles(ctx, req.OlderThanDays, req.CompressedOnly, req.DryRun, resp); err != nil {
		slog.Error("failed to cleanup log files", "error", err)
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("cleanup failed: %v", err))
		return
	}

	if !req.DryRun {
		resp.ExecutedAt = time.Now().UTC().Format(time.RFC3339)
	}

	if resp.AffectedFiles == 0 {
		resp.WarningMessage = "没有需要清理的日志文件"
	} else if resp.AffectedFiles > 100 {
		resp.WarningMessage = "影响文件数超过 100，请确认操作"
	}

	w.Header().Set("Content-Type", "application/json")
	//nolint:errcheck // HTTP write error non-recoverable
	json.NewEncoder(w).Encode(resp)
}

// cleanupOldLogFiles cleans up log files older than specified days
func (h *Handler) cleanupOldLogFiles(ctx context.Context, olderThanDays int, compressedOnly bool, dryRun bool, resp *CleanupLogsResponse) error {
	logFile := os.Getenv("LLM_GATEWAY_LOG_FILE")
	if logFile == "" {
		logFile = "./logs/gateway.log"
	}

	logDir := filepath.Dir(logFile)
	baseName := filepath.Base(logFile)
	cutoffTime := time.Now().Add(-time.Duration(olderThanDays) * 24 * time.Hour)

	// Find files to delete
	var toDelete []string
	var totalSize int64

	err := filepath.Walk(logDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}

		name := info.Name()

		// Skip active log file
		if name == baseName {
			return nil
		}

		// Check if this is a rotated log file
		isRotatedLog := false
		if strings.HasPrefix(name, strings.TrimSuffix(baseName, ".log")) {
			if strings.HasSuffix(name, ".log.gz") || strings.HasSuffix(name, ".log") {
				isRotatedLog = true
			}
		}

		if !isRotatedLog {
			return nil
		}

		// If compressed_only, skip uncompressed files
		if compressedOnly && !strings.HasSuffix(name, ".gz") {
			return nil
		}

		// Check if file is older than cutoff
		if info.ModTime().Before(cutoffTime) {
			toDelete = append(toDelete, path)
			totalSize += info.Size()
		}

		return nil
	})

	if err != nil {
		return fmt.Errorf("failed to scan log directory: %w", err)
	}

	resp.AffectedFiles = len(toDelete)
	resp.EstimatedFreedBytes = totalSize
	resp.EstimatedFreedHuman = formatBytes(totalSize)

	if dryRun {
		slog.Info("cleanup preview: old log files",
			"count", len(toDelete),
			"size", formatBytes(totalSize),
			"older_than_days", olderThanDays,
			"compressed_only", compressedOnly)
		return nil
	}

	// Execute cleanup
	deletedCount := 0
	deletedSize := int64(0)

	for _, path := range toDelete {
		info, err := os.Stat(path)
		if err != nil {
			continue
		}

		if err := os.Remove(path); err != nil {
			slog.Warn("failed to delete log file", "path", path, "error", err)
			continue
		}

		deletedCount++
		deletedSize += info.Size()
	}

	slog.Info("cleanup completed: old log files",
		"deleted_count", deletedCount,
		"deleted_size", formatBytes(deletedSize),
		"older_than_days", olderThanDays)

	resp.AffectedFiles = deletedCount
	resp.EstimatedFreedBytes = deletedSize
	resp.EstimatedFreedHuman = formatBytes(deletedSize)

	return nil
}

// UpdateLogConfigRequest defines the log configuration update request
type UpdateLogConfigRequest struct {
	MaxSizeMB  int  `json:"max_size_mb"`
	MaxBackups int  `json:"max_backups"`
	MaxAgeDays int  `json:"max_age_days"`
	Compress   bool `json:"compress"`
}

// POST /api/admin/data-lifecycle/log-config
// Update log file configuration (note: requires restart to take effect)
func (h *Handler) handleUpdateLogConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodPut {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	var config UpdateLogConfigRequest
	if err := json.NewDecoder(r.Body).Decode(&config); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Validate configuration
	if config.MaxSizeMB < 10 || config.MaxSizeMB > 1000 {
		writeError(w, http.StatusBadRequest, "max_size_mb must be between 10 and 1000")
		return
	}

	if config.MaxBackups < 1 || config.MaxBackups > 100 {
		writeError(w, http.StatusBadRequest, "max_backups must be between 1 and 100")
		return
	}

	if config.MaxAgeDays < 0 || config.MaxAgeDays > 365 {
		writeError(w, http.StatusBadRequest, "max_age_days must be between 0 and 365")
		return
	}

	// TODO: Save to configuration file or settings table
	// For now, just return a message
	slog.Info("log config update requested (requires restart)",
		"max_size_mb", config.MaxSizeMB,
		"max_backups", config.MaxBackups,
		"max_age_days", config.MaxAgeDays,
		"compress", config.Compress)

	w.Header().Set("Content-Type", "application/json")
	//nolint:errcheck // HTTP write error non-recoverable
	json.NewEncoder(w).Encode(map[string]any{
		"success": true,
		"message": "日志配置已记录。注意：需要重启服务才能生效。当前版本配置通过环境变量设置。",
		"config":  config,
	})
}
