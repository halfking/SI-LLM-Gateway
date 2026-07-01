package rotate

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

// --- Rotator tests ---------------------------------------------------

func TestNew_RequiresFile(t *testing.T) {
	if _, err := New(Config{}); err == nil {
		t.Fatal("expected error for empty File path")
	}
}

func TestNew_AppliesDefaults(t *testing.T) {
	dir := t.TempDir()
	r, err := New(Config{File: filepath.Join(dir, "out.log")})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	t.Cleanup(func() { r.Close() })

	if r.Path() == "" {
		t.Error("Path() must be non-empty")
	}
	// Defaults: 100 MiB / 10 / 0 / true. We can't introspect
	// lumberjack directly, but we can sanity-check that the
	// file was created and is writable.
	if _, err := os.Stat(r.Path()); err != nil {
		t.Errorf("expected log file to exist: %v", err)
	}
}

func TestNew_CreatesParentDir(t *testing.T) {
	dir := t.TempDir()
	nested := filepath.Join(dir, "a", "b", "c", "out.log")
	r, err := New(Config{File: nested})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	t.Cleanup(func() { r.Close() })
	if _, err := os.Stat(nested); err != nil {
		t.Errorf("nested log file should exist: %v", err)
	}
}

func TestNew_RejectsBadPath(t *testing.T) {
	// /dev/null is a character device, not a directory — but
	// using a path under a non-existent AND unwritable location
	// is platform-flaky. Use a path whose parent is a file.
	dir := t.TempDir()
	notADir := filepath.Join(dir, "file")
	if err := os.WriteFile(notADir, []byte("x"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}
	if _, err := New(Config{File: filepath.Join(notADir, "child", "out.log")}); err == nil {
		t.Error("expected error when parent path is a file, not a directory")
	}
}

func TestRotator_WritesLines(t *testing.T) {
	dir := t.TempDir()
	r, err := New(Config{File: filepath.Join(dir, "out.log")})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	// Close BEFORE reading so lumberjack releases the file
	// handle and the t.TempDir() cleanup at test end can
	// unlink it without a race.
	msg := "hello world\n"
	for i := 0; i < 5; i++ {
		if _, err := r.Writer().Write([]byte(msg)); err != nil {
			t.Fatalf("Write %d: %v", i, err)
		}
	}
	if err := r.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(dir, "out.log"))
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if got := strings.Count(string(data), msg); got != 5 {
		t.Errorf("expected 5 lines, got %d", got)
	}
}

func TestRotator_RotatesBySize(t *testing.T) {
	dir := t.TempDir()
	// 1 MiB threshold + 3 backups + compression. Write ~5 MiB
	// of data; we should observe multiple rotated files.
	compress := true
	r, err := New(Config{
		File:       filepath.Join(dir, "out.log"),
		MaxSizeMB:  1,
		MaxBackups: 3,
		Compress:   &compress,
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	// Each line is 100 KiB; write 60 lines → ~6 MiB → at least
	// 6 rotations + 1 active file.
	chunk := bytes.Repeat([]byte("a"), 100*1024)
	for i := 0; i < 60; i++ {
		line := fmt.Sprintf("line-%05d-%s\n", i, string(chunk))
		if _, err := r.Writer().Write([]byte(line)); err != nil {
			t.Fatalf("Write %d: %v", i, err)
		}
	}
	// Close BEFORE scanning the directory so lumberjack
	// finishes compressing the last rotated file and releases
	// all handles. Without this, t.TempDir() cleanup at test
	// end races with the goroutine and occasionally fails
	// with "directory not empty".
	if err := r.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	// Expect at least one rotated file. With LocalTime=true,
	// lumberjack uses ISO-style names like
	// "out-2026-07-01T02-39-38.411.log" (active) or "...log.gz"
	// (compressed). The active file is named just "out.log" but
	// rotated copies start with "out-".
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	var rotated int
	for _, e := range entries {
		name := e.Name()
		if name == "out.log" {
			continue
		}
		if strings.HasPrefix(name, "out-") {
			rotated++
		}
	}
	if rotated < 1 {
		t.Errorf("expected at least 1 rotated file, got %d (entries: %v)", rotated, namesOf(entries))
	}
}

func TestRotator_CloseIdempotent(t *testing.T) {
	dir := t.TempDir()
	r, err := New(Config{File: filepath.Join(dir, "out.log")})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if err := r.Close(); err != nil {
		t.Errorf("first Close: %v", err)
	}
	if err := r.Close(); err != nil {
		t.Errorf("second Close: %v", err)
	}
}

// --- MultiHandler tests ---------------------------------------------

// recordingHandler counts the records it has seen, storing the
// level of each. Used to verify fan-out and WithAttrs / WithGroup
// propagation. The records slice is shared via a *shared slice
// so WithAttrs / WithGroup clones still write back to the
// original (slog.Logger.With returns a *new* logger wrapping a
// new handler chain).
type recordingHandler struct {
	shared *sharedRecords

	enabled slog.Level // minimum level for Enabled; 0 = always true
	failing bool
	attrs   []slog.Attr
	group   string
}

type sharedRecords struct {
	mu      sync.Mutex
	records []slog.Record
}

func (h *recordingHandler) Enabled(_ context.Context, l slog.Level) bool {
	if h.enabled == 0 {
		return true
	}
	return l >= h.enabled
}

func (h *recordingHandler) Handle(_ context.Context, r slog.Record) error {
	// Apply the per-handler attrs (set via WithAttrs) and any
	// group prefix, matching how slog.JSONHandler behaves, so
	// tests can verify attribute propagation.
	cloned := r.Clone()
	cloned.AddAttrs(h.attrs...)
	// For groups: skip re-keying; we just store the group name
	// for assertion convenience and let tests inspect attrs
	// via Attrs(). (Real slog.JSONHandler re-keys attrs under
	// "group." but for fan-out correctness we just need to
	// confirm WithGroup was called and the record arrived.)
	h.shared.mu.Lock()
	h.shared.records = append(h.shared.records, cloned)
	h.shared.mu.Unlock()
	if h.failing {
		return fmt.Errorf("simulated failure at level %s", r.Level)
	}
	return nil
}

func (h *recordingHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	clone := *h
	clone.attrs = append(append([]slog.Attr{}, h.attrs...), attrs...)
	return &clone
}

func (h *recordingHandler) WithGroup(name string) slog.Handler {
	clone := *h
	clone.group = name
	return &clone
}

func (h *recordingHandler) count() int {
	h.shared.mu.Lock()
	defer h.shared.mu.Unlock()
	return len(h.shared.records)
}

func (h *recordingHandler) lastMsg() string {
	h.shared.mu.Lock()
	defer h.shared.mu.Unlock()
	if len(h.shared.records) == 0 {
		return ""
	}
	return h.shared.records[len(h.shared.records)-1].Message
}

func (h *recordingHandler) lastRecord() (slog.Record, bool) {
	h.shared.mu.Lock()
	defer h.shared.mu.Unlock()
	if len(h.shared.records) == 0 {
		return slog.Record{}, false
	}
	return h.shared.records[len(h.shared.records)-1], true
}

func newRecording() *recordingHandler {
	return &recordingHandler{shared: &sharedRecords{}}
}

func TestMultiHandler_FansOut(t *testing.T) {
	a := newRecording()
	b := newRecording()
	mh := NewMultiHandler(a, b)

	logger := slog.New(mh)
	logger.Info("hello", "k", "v")

	if got := a.count(); got != 1 {
		t.Errorf("handler A: got %d records, want 1", got)
	}
	if got := b.count(); got != 1 {
		t.Errorf("handler B: got %d records, want 1", got)
	}
	if got := a.lastMsg(); got != "hello" {
		t.Errorf("handler A msg: got %q, want %q", got, "hello")
	}
}

func TestMultiHandler_Enabled_AnyChild(t *testing.T) {
	// Both children accept WARN → MultiHandler.Enabled = true.
	loose1 := &strictHandler{min: slog.LevelWarn}
	loose2 := &strictHandler{min: slog.LevelWarn}
	if !NewMultiHandler(loose1, loose2).Enabled(context.Background(), slog.LevelWarn) {
		t.Error("expected enabled when at least one child accepts WARN")
	}

	// strict children: only ERROR and above is allowed.
	strict1 := &strictHandler{min: slog.LevelError}
	strict2 := &strictHandler{min: slog.LevelError}
	if NewMultiHandler(strict1, strict2).Enabled(context.Background(), slog.LevelWarn) {
		t.Error("expected disabled when no child accepts WARN")
	}
	if !NewMultiHandler(strict1, strict2).Enabled(context.Background(), slog.LevelError) {
		t.Error("expected enabled when at least one child accepts ERROR")
	}
}

func TestMultiHandler_WithAttrs(t *testing.T) {
	a := newRecording()
	mh := NewMultiHandler(a)
	with := slog.New(mh).With("rid", "req-1")
	with.Info("hi")

	rec, ok := a.lastRecord()
	if !ok {
		t.Fatal("no record captured")
	}
	found := false
	rec.Attrs(func(attr slog.Attr) bool {
		if attr.Key == "rid" && attr.Value.String() == "req-1" {
			found = true
			return false
		}
		return true
	})
	if !found {
		t.Error("expected rid=req-1 attribute on record")
	}
}

func TestMultiHandler_WithGroup(t *testing.T) {
	a := newRecording()
	mh := NewMultiHandler(a)
	with := slog.New(mh).WithGroup("grp")
	with.Info("hi", "k", "v")

	// slog's JSON handler does the grp.k flattening; we just
	// need to confirm that calling WithGroup did not panic and
	// the record was still delivered.
	if a.count() != 1 {
		t.Errorf("expected 1 record after WithGroup, got %d", a.count())
	}
}

func TestMultiHandler_HandleError(t *testing.T) {
	good := newRecording()
	bad := newRecording()
	bad.failing = true
	mh := NewMultiHandler(good, bad)

	logger := slog.New(mh)
	logger.Info("x")

	// Even when one child errors, the other must still receive
	// the record.
	if got := good.count(); got != 1 {
		t.Errorf("good handler should still receive the record, got %d", got)
	}
	if got := bad.count(); got != 1 {
		t.Errorf("bad handler should still be invoked, got %d", got)
	}
}

func TestMultiHandler_PanicsOnEmpty(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Error("expected panic for NewMultiHandler() with no children")
		}
	}()
	NewMultiHandler()
}

func TestMultiHandler_Concurrent(t *testing.T) {
	a := newRecording()
	b := newRecording()
	mh := NewMultiHandler(a, b)
	logger := slog.New(mh)

	const goroutines = 20
	const perG = 50
	var wg sync.WaitGroup
	wg.Add(goroutines)
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < perG; j++ {
				logger.Info("concurrent", "g", j)
			}
		}()
	}
	wg.Wait()

	want := goroutines * perG
	if got := a.count(); got != want {
		t.Errorf("handler A: got %d records, want %d", got, want)
	}
	if got := b.count(); got != want {
		t.Errorf("handler B: got %d records, want %d", got, want)
	}
}

// --- helpers --------------------------------------------------------

type strictHandler struct {
	min slog.Level
}

func (h *strictHandler) Enabled(_ context.Context, l slog.Level) bool {
	return l >= h.min
}

func (h *strictHandler) Handle(_ context.Context, _ slog.Record) error {
	atomic.AddInt64(&globalCounter, 1)
	return nil
}

func (h *strictHandler) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h *strictHandler) WithGroup(string) slog.Handler      { return h }

var globalCounter int64

func namesOf(entries []os.DirEntry) []string {
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.Name())
	}
	return out
}
