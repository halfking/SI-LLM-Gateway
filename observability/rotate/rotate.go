// Package rotate provides size- and age-bounded log file rotation
// for the gateway's structured (slog) logs.
//
// The package is a thin wrapper around the de-facto standard
// `gopkg.in/natefinch/lumberjack.v2` library. We expose:
//
//   - Config: a small struct mirroring the lumberjack knobs we
//     care about (size in MiB, number of rotated backups to keep,
//     optional age in days, gzip compression).
//   - Rotator: holds the underlying *lumberjack.Logger and
//     implements Close + Writer + Path. Use Writer() to feed a
//     slog JSON handler.
//   - MultiHandler: a slog.Handler that fans out records to
//     multiple child handlers (typically stderr + rotated file),
//     so callers don't need a third-party tee writer.
//
// Design notes
// ============
//
//   - lumberjack.Logger is already goroutine-safe and implements
//     io.Writer. slog.JSONHandler is also goroutine-safe. The
//     MultiHandler adds a mutex around Handle() so concurrent
//     record writes from different goroutines do not interleave
//     a half-line from one child with a half-line from another.
//   - We do NOT use `slog.GroupValue` or any other fancy features
//     in the multi-handler — keep it simple and obvious.
//   - Defaults are conservative: 100 MiB per file × 10 backups ≈
//     1 GiB worst-case disk usage. That matches the operator
//     requirement: "最大 1G 的 log,过期删除".
package rotate

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	lumberjack "gopkg.in/natefinch/lumberjack.v2"
)

// Config mirrors the lumberjack knobs the gateway exposes. All
// fields are optional; zero values fall back to package defaults
// (see Defaults).
type Config struct {
	// File is the absolute or CWD-relative path of the active log
	// file. The parent directory is created on Open with mode 0755
	// (mirrors observability/siem.FileSink).
	File string

	// MaxSizeMB is the size threshold (in megabytes) at which the
	// current file is rotated. Default 100 MiB.
	MaxSizeMB int

	// MaxBackups is the number of rotated files to keep on disk
	// (oldest are deleted first). 0 means keep all. Default 10.
	MaxBackups int

	// MaxAgeDays is the maximum age (in days) of a rotated file
	// before it is deleted. 0 means no time-based expiry. Default
	// 0 (size-based only, in line with the operator spec).
	MaxAgeDays int

	// Compress enables gzip compression of rotated files
	// (gateway.log.1.gz, gateway.log.2.gz, ...). Pointer so
	// callers (and YAML/env parsing in cmd/gateway) can
	// distinguish "unset" (→ default true) from "explicitly
	// false".
	Compress *bool
}

// Defaults returns the package defaults. Exported so callers can
// show the effective values in startup logs.
func Defaults() Config {
	compress := true
	return Config{
		MaxSizeMB:  100,
		MaxBackups: 10,
		MaxAgeDays: 0,
		Compress:   &compress,
	}
}

// applyDefaults fills in zero-valued fields with package defaults.
func (c Config) applyDefaults() Config {
	d := Defaults()
	if c.MaxSizeMB == 0 {
		c.MaxSizeMB = d.MaxSizeMB
	}
	if c.MaxBackups == 0 {
		c.MaxBackups = d.MaxBackups
	}
	// MaxAgeDays = 0 is a valid "no expiry" setting; don't overwrite.
	if c.Compress == nil {
		c.Compress = d.Compress
	}
	return c
}

// Rotator wraps a *lumberjack.Logger. It is safe for concurrent use.
type Rotator struct {
	inner *lumberjack.Logger
	path  string
}

// New opens (creating the parent directory if necessary) a rotated
// log file according to the supplied Config. Returns an error if
// the file cannot be opened — callers should treat that as
// "fall back to stderr only" rather than aborting the process.
func New(cfg Config) (*Rotator, error) {
	if cfg.File == "" {
		return nil, fmt.Errorf("rotate: File is required")
	}
	cfg = cfg.applyDefaults()

	dir := filepath.Dir(cfg.File)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("rotate: mkdir %s: %w", dir, err)
	}

	inner := &lumberjack.Logger{
		Filename:   cfg.File,
		MaxSize:    cfg.MaxSizeMB, // lumberjack uses megabytes
		MaxBackups: cfg.MaxBackups,
		MaxAge:     cfg.MaxAgeDays,
		Compress:   *cfg.Compress,
		LocalTime:  true, // human-friendly rotated file names
	}

	// Touch the file eagerly so a permission error surfaces now
	// (during startup) rather than on the first log line.
	if _, err := inner.Write([]byte{}); err != nil {
		_ = inner.Close()
		return nil, fmt.Errorf("rotate: open %s: %w", cfg.File, err)
	}

	return &Rotator{inner: inner, path: cfg.File}, nil
}

// Writer returns the underlying io.Writer. Use this when wiring
// into a slog.JSONHandler.
func (r *Rotator) Writer() io.Writer { return r.inner }

// Path returns the resolved log file path.
func (r *Rotator) Path() string { return r.path }

// Close flushes pending writes and closes the file. Idempotent.
func (r *Rotator) Close() error {
	if r == nil || r.inner == nil {
		return nil
	}
	return r.inner.Close()
}
