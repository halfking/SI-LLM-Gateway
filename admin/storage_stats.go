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
	"strings"
	"syscall"
	"time"
)

// StorageStatsResponse holds comprehensive storage statistics
type StorageStatsResponse struct {
	Disk              *DiskStats              `json:"disk"`
	Database          *DatabaseStats          `json:"database"`
	AttachmentsStorage *AttachmentStorageStats `json:"attachments_storage"`
	LogFilesStorage   *LogFilesStorageStats   `json:"log_files_storage"`
	LifecycleConfig   *LifecycleConfig        `json:"lifecycle_config"`
}

type DiskStats struct {
	TotalBytes     uint64  `json:"total_bytes"`
	UsedBytes      uint64  `json:"used_bytes"`
	AvailableBytes uint64  `json:"available_bytes"`
	UsagePercent   float64 `json:"usage_percent"`
	MountPath      string  `json:"mount_path"`
	Filesystem     string  `json:"filesystem"`
}

type DatabaseStats struct {
	TotalSizeBytes        int64            `json:"total_size_bytes"`
	TotalSizeHuman        string           `json:"total_size_human"`
	RequestLogsBytes      int64            `json:"request_logs_bytes"`
	RequestLogsHuman      string           `json:"request_logs_human"`
	AttachmentsMetaBytes  int64            `json:"attachments_meta_bytes"`
	AttachmentsMetaHuman  string           `json:"attachments_meta_human"`
	OtherTablesBytes      int64            `json:"other_tables_bytes"`
	OtherTablesHuman      string           `json:"other_tables_human"`
	TableSizes            []TableSizeInfo  `json:"table_sizes,omitempty"`
}

type TableSizeInfo struct {
	TableName string `json:"table_name"`
	SizeBytes int64  `json:"size_bytes"`
	SizeHuman string `json:"size_human"`
	RowCount  int64  `json:"row_count,omitempty"`
}

type AttachmentStorageStats struct {
	StoragePath   string               `json:"storage_path"`
	TotalFiles    int                  `json:"total_files"`
	TotalSizeBytes int64               `json:"total_size_bytes"`
	TotalSizeHuman string              `json:"total_size_human"`
	ByMediaType   []MediaTypeStats     `json:"by_media_type"`
	OrphanedFiles int                  `json:"orphaned_files,omitempty"`
}

type MediaTypeStats struct {
	MediaType string `json:"media_type"`
	Count     int    `json:"count"`
	SizeBytes int64  `json:"size_bytes"`
	SizeHuman string `json:"size_human"`
}

type LogFilesStorageStats struct {
	LogDirectory   string        `json:"log_directory"`
	TotalFiles     int           `json:"total_files"`
	TotalSizeBytes int64         `json:"total_size_bytes"`
	TotalSizeHuman string        `json:"total_size_human"`
	ActiveLogFile  *LogFileInfo  `json:"active_log_file,omitempty"`
	RotatedFiles   []LogFileInfo `json:"rotated_files"`
	Config         *LogConfig    `json:"config"`
}

type LogFileInfo struct {
	Name         string    `json:"name"`
	Path         string    `json:"path"`
	SizeBytes    int64     `json:"size_bytes"`
	SizeHuman    string    `json:"size_human"`
	ModifiedAt   time.Time `json:"modified_at"`
	IsCompressed bool      `json:"is_compressed"`
	IsActive     bool      `json:"is_active"`
}

type LogConfig struct {
	File       string `json:"file"`
	MaxSizeMB  int    `json:"max_size_mb"`
	MaxBackups int    `json:"max_backups"`
	MaxAgeDays int    `json:"max_age_days"`
	Compress   bool   `json:"compress"`
}

type LifecycleConfig struct {
	RetentionDays        int    `json:"retention_days"`
	AutoCleanupEnabled   bool   `json:"auto_cleanup_enabled"`
	CleanupSchedule      string `json:"cleanup_schedule"`
	LastCleanupAt        string `json:"last_cleanup_at,omitempty"`
	AttachmentStoragePath string `json:"attachment_storage_path"`
	MaxAttachmentSizeMB  int    `json:"max_attachment_size_mb"`
}

// GET /api/admin/data-lifecycle/storage-stats
// Returns comprehensive storage statistics including disk, database, and attachments
func (h *Handler) handleStorageStats(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()

	resp := &StorageStatsResponse{}

	// Get disk stats
	diskStats, err := getDiskStats("/")
	if err != nil {
		slog.Warn("failed to get disk stats", "error", err)
		// Continue without disk stats
	} else {
		resp.Disk = diskStats
	}

	// Get database stats
	dbStats, err := h.getDatabaseStats(ctx)
	if err != nil {
		slog.Warn("failed to get database stats", "error", err)
	} else {
		resp.Database = dbStats
	}

	// Get attachments storage stats
	attachmentPath := os.Getenv("ATTACHMENT_STORAGE_PATH")
	if attachmentPath == "" {
		// 2026-07-02: anchor to bind-mount target so this matches
		// the path used by attachments.Manager and survives container
		// restarts. See scripts/deploy-71-data-bindmounts.sh.
		attachmentPath = "/opt/llm-gateway-go/data/attachments"
	}
	attachStats, err := h.getAttachmentStorageStats(ctx, attachmentPath)
	if err != nil {
		slog.Warn("failed to get attachment storage stats", "error", err)
	} else {
		resp.AttachmentsStorage = attachStats
	}

	// Get log files storage stats
	logStats := h.getLogFilesStorageStats()
	if logStats != nil {
		resp.LogFilesStorage = logStats
	}

	// Get lifecycle config
	config := h.getLifecycleConfig(ctx)
	resp.LifecycleConfig = config

	w.Header().Set("Content-Type", "application/json")
	//nolint:errcheck // HTTP write error non-recoverable
	json.NewEncoder(w).Encode(resp)
}

// getDiskStats retrieves disk space statistics for the given path
func getDiskStats(path string) (*DiskStats, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return nil, fmt.Errorf("statfs failed: %w", err)
	}

	// Calculate sizes
	totalBytes := stat.Blocks * uint64(stat.Bsize)
	availableBytes := stat.Bavail * uint64(stat.Bsize)
	usedBytes := totalBytes - availableBytes
	usagePercent := 0.0
	if totalBytes > 0 {
		usagePercent = float64(usedBytes) / float64(totalBytes) * 100
	}

	return &DiskStats{
		TotalBytes:     totalBytes,
		UsedBytes:      usedBytes,
		AvailableBytes: availableBytes,
		UsagePercent:   usagePercent,
		MountPath:      path,
		Filesystem:     "unknown", // syscall.Statfs doesn't provide filesystem type easily
	}, nil
}

// getDatabaseStats retrieves database size statistics
func (h *Handler) getDatabaseStats(ctx context.Context) (*DatabaseStats, error) {
	stats := &DatabaseStats{
		TableSizes: []TableSizeInfo{},
	}

	// Get total database size
	err := h.db.QueryRow(ctx, `
		SELECT 
			pg_database_size(current_database()) AS total_size,
			pg_size_pretty(pg_database_size(current_database())) AS total_human
	`).Scan(&stats.TotalSizeBytes, &stats.TotalSizeHuman)
	
	if err != nil {
		return nil, fmt.Errorf("failed to get database size: %w", err)
	}

	// Get individual table sizes
	rows, err := h.db.Query(ctx, `
		SELECT 
			'request_logs' AS table_name,
			pg_total_relation_size('request_logs') AS size_bytes,
			pg_size_pretty(pg_total_relation_size('request_logs')) AS size_human,
			(SELECT COUNT(*) FROM request_logs) AS row_count
		UNION ALL
		SELECT 
			'attachments' AS table_name,
			pg_total_relation_size('attachments') AS size_bytes,
			pg_size_pretty(pg_total_relation_size('attachments')) AS size_human,
			(SELECT COUNT(*) FROM attachments) AS row_count
		ORDER BY size_bytes DESC
	`)
	
	if err != nil {
		return nil, fmt.Errorf("failed to query table sizes: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var info TableSizeInfo
		if err := rows.Scan(&info.TableName, &info.SizeBytes, &info.SizeHuman, &info.RowCount); err != nil {
			continue
		}
		stats.TableSizes = append(stats.TableSizes, info)

		// Populate specific fields
		switch info.TableName {
		case "request_logs":
			stats.RequestLogsBytes = info.SizeBytes
			stats.RequestLogsHuman = info.SizeHuman
		case "attachments":
			stats.AttachmentsMetaBytes = info.SizeBytes
			stats.AttachmentsMetaHuman = info.SizeHuman
		}
	}

	// Calculate "other tables" size
	stats.OtherTablesBytes = stats.TotalSizeBytes - stats.RequestLogsBytes - stats.AttachmentsMetaBytes
	if stats.OtherTablesBytes < 0 {
		stats.OtherTablesBytes = 0
	}
	stats.OtherTablesHuman = formatBytes(stats.OtherTablesBytes)

	return stats, nil
}

// getAttachmentStorageStats scans the attachment directory and retrieves statistics
func (h *Handler) getAttachmentStorageStats(ctx context.Context, storagePath string) (*AttachmentStorageStats, error) {
	stats := &AttachmentStorageStats{
		StoragePath: storagePath,
		ByMediaType: []MediaTypeStats{},
	}

	// Check if directory exists
	if _, err := os.Stat(storagePath); os.IsNotExist(err) {
		slog.Warn("attachment storage path does not exist", "path", storagePath)
		return stats, nil // Return empty stats, not an error
	}

	// Get media type statistics from database
	rows, err := h.db.Query(ctx, `
		SELECT 
			media_type,
			COUNT(*) AS count,
			SUM(file_size) AS total_size
		FROM attachments
		GROUP BY media_type
		ORDER BY total_size DESC
	`)
	
	if err != nil {
		return nil, fmt.Errorf("failed to query attachment stats: %w", err)
	}
	defer rows.Close()

	totalFiles := 0
	var totalSize int64 = 0

	for rows.Next() {
		var mt MediaTypeStats
		if err := rows.Scan(&mt.MediaType, &mt.Count, &mt.SizeBytes); err != nil {
			continue
		}
		mt.SizeHuman = formatBytes(mt.SizeBytes)
		stats.ByMediaType = append(stats.ByMediaType, mt)
		totalFiles += mt.Count
		totalSize += mt.SizeBytes
	}

	stats.TotalFiles = totalFiles
	stats.TotalSizeBytes = totalSize
	stats.TotalSizeHuman = formatBytes(totalSize)

	// Check for orphaned files (files in directory but not in database)
	orphanedCount, err := h.countOrphanedAttachments(ctx, storagePath)
	if err != nil {
		slog.Warn("failed to count orphaned attachments", "error", err)
	} else {
		stats.OrphanedFiles = orphanedCount
	}

	return stats, nil
}

// countOrphanedAttachments counts files in storage directory that have no database record.
// 2026-07-02: the actual on-disk layout is {YYYY}/{MM}/{DD}/{uuid}.{ext}
// (see attachments.Manager.ArchiveFromRequest); the previous version of
// this function compared the bare filename to the row id, which always
// mismatched because the stored path includes the date directories.
// We now build the full relative path of each file on disk and look it
// up in the set of `file_path` values from the attachments table.
func (h *Handler) countOrphanedAttachments(ctx context.Context, storagePath string) (int, error) {
	// Get all attachment file paths from database
	rows, err := h.db.Query(ctx, `SELECT file_path FROM attachments`)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	dbPaths := make(map[string]bool)
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			continue
		}
		dbPaths[p] = true
	}

	// Walk storage directory and check each file's relative path
	orphanedCount := 0
	err = filepath.WalkDir(storagePath, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		relPath, err := filepath.Rel(storagePath, path)
		if err != nil {
			return nil
		}
		if !dbPaths[relPath] {
			orphanedCount++
		}
		return nil
	})

	if err != nil {
		return 0, err
	}

	return orphanedCount, nil
}

// getLifecycleConfig retrieves the current lifecycle configuration
func (h *Handler) getLifecycleConfig(ctx context.Context) *LifecycleConfig {
	config := &LifecycleConfig{
		RetentionDays:        90,  // Default
		AutoCleanupEnabled:   false,
		CleanupSchedule:      "0 2 * * *", // 2 AM daily
		MaxAttachmentSizeMB:  10,
	}

	// Get attachment storage path from environment
	attachmentPath := os.Getenv("ATTACHMENT_STORAGE_PATH")
	if attachmentPath == "" {
		attachmentPath = "/opt/llm-gateway-go/data/attachments"
	}
	config.AttachmentStoragePath = attachmentPath

	// TODO: Load these from settings table when storage settings are implemented
	// For now, return defaults

	return config
}

// getLogFilesStorageStats retrieves statistics about log files
func (h *Handler) getLogFilesStorageStats() *LogFilesStorageStats {
	// Get log configuration from environment
	logFile := os.Getenv("LLM_GATEWAY_LOG_FILE")
	if logFile == "" {
		logFile = "./logs/gateway.log"
	}

	maxSizeMB := 100
	if env := os.Getenv("LLM_GATEWAY_LOG_MAX_SIZE_MB"); env != "" {
		fmt.Sscanf(env, "%d", &maxSizeMB)
	}

	maxBackups := 10
	if env := os.Getenv("LLM_GATEWAY_LOG_MAX_BACKUPS"); env != "" {
		fmt.Sscanf(env, "%d", &maxBackups)
	}

	maxAgeDays := 30
	if env := os.Getenv("LLM_GATEWAY_LOG_MAX_AGE_DAYS"); env != "" {
		fmt.Sscanf(env, "%d", &maxAgeDays)
	}

	compress := true
	if env := os.Getenv("LLM_GATEWAY_LOG_COMPRESS"); env == "false" {
		compress = false
	}

	stats := &LogFilesStorageStats{
		LogDirectory: filepath.Dir(logFile),
		RotatedFiles: []LogFileInfo{},
		Config: &LogConfig{
			File:       logFile,
			MaxSizeMB:  maxSizeMB,
			MaxBackups: maxBackups,
			MaxAgeDays: maxAgeDays,
			Compress:   compress,
		},
	}

	// Check if log file exists
	if _, err := os.Stat(logFile); os.IsNotExist(err) {
		slog.Warn("log file does not exist", "path", logFile)
		return stats
	}

	// Get log directory
	logDir := filepath.Dir(logFile)
	baseName := filepath.Base(logFile)

	// Scan log directory for all log files
	var totalSize int64
	var fileCount int

	err := filepath.WalkDir(logDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}

		name := d.Name()
		
		// Check if this is a log file (active or rotated)
		// Active: gateway.log
		// Rotated: gateway-YYYY-MM-DD.log, gateway-YYYY-MM-DD.log.gz
		isLogFile := false
		isActive := false
		isCompressed := false

		if name == baseName {
			isLogFile = true
			isActive = true
		} else if strings.HasPrefix(name, strings.TrimSuffix(baseName, ".log")) {
			if strings.HasSuffix(name, ".log.gz") || strings.HasSuffix(name, ".log") {
				isLogFile = true
				isCompressed = strings.HasSuffix(name, ".gz")
			}
		}

		if !isLogFile {
			return nil
		}

		info, err := d.Info()
		if err != nil {
			return nil
		}

		fileInfo := LogFileInfo{
			Name:         name,
			Path:         path,
			SizeBytes:    info.Size(),
			SizeHuman:    formatBytes(info.Size()),
			ModifiedAt:   info.ModTime(),
			IsCompressed: isCompressed,
			IsActive:     isActive,
		}

		if isActive {
			stats.ActiveLogFile = &fileInfo
		} else {
			stats.RotatedFiles = append(stats.RotatedFiles, fileInfo)
		}

		totalSize += info.Size()
		fileCount++

		return nil
	})

	if err != nil {
		slog.Warn("failed to scan log directory", "error", err, "dir", logDir)
	}

	stats.TotalFiles = fileCount
	stats.TotalSizeBytes = totalSize
	stats.TotalSizeHuman = formatBytes(totalSize)

	return stats
}

// formatBytes formats bytes into human-readable string
func formatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}
