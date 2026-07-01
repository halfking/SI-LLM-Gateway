package rotate

import (
	"context"
	"log/slog"
	"sync"
)

// MultiHandler fans out every log record to multiple child
// handlers. It is intended to be used with two children:
//
//   - one that writes to os.Stderr (preserves the existing
//     docker logs / kubectl logs behavior), and
//   - one that writes to a Rotator-backed file (preserves the
//     long-term, size-bounded, compressed history).
//
// Both children receive every record at the level they accept;
// the MultiHandler does NOT drop records on a child error —
// instead it returns the first error from Handle() to satisfy
// the slog.Handler contract, but still attempts every child
// (best-effort fan-out).
//
// Concurrency
// ===========
//
// slog handlers can be invoked concurrently from many
// goroutines. Each child handler is responsible for its own
// internal locking (slog.JSONHandler does this; lumberjack does
// this). MultiHandler adds a single mutex around Handle() to
// avoid an obvious race: with two children, the second child's
// Handle() could interleave between the first child's fmt
// formatting and its os.File write, producing garbled output on
// the second child. The mutex makes the fan-out atomic across
// children.
//
// The mutex is held only for the duration of one Handle call,
// so contention is bounded by the rate of log records, not by
// any long-running operation.
type MultiHandler struct {
	mu       sync.Mutex
	children []slog.Handler
}

// NewMultiHandler constructs a MultiHandler over the given
// children. At least one child is required; passing zero
// panics (matching the policy of slog.New — fail fast on
// programmer error).
func NewMultiHandler(children ...slog.Handler) *MultiHandler {
	if len(children) == 0 {
		panic("rotate: NewMultiHandler requires at least one child handler")
	}
	return &MultiHandler{children: children}
}

// Enabled returns true if any child is enabled at the given
// level. This matches the convention used by other
// fan-out handlers in the Go ecosystem (e.g. slog-multi).
// Returning false short-circuits the call and prevents useless
// work in every child.
func (m *MultiHandler) Enabled(ctx context.Context, level slog.Level) bool {
	for _, h := range m.children {
		if h.Enabled(ctx, level) {
			return true
		}
	}
	return false
}

// Handle dispatches the record to every child that accepts it.
// It returns the first non-nil error encountered, but
// continues attempting subsequent children so a single broken
// sink does not silence the others.
func (m *MultiHandler) Handle(ctx context.Context, r slog.Record) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	var firstErr error
	for _, h := range m.children {
		if !h.Enabled(ctx, r.Level) {
			continue
		}
		if err := h.Handle(ctx, r); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

// WithAttrs returns a new MultiHandler whose children have the
// given attributes attached. This is how slog.Logger.With(...)
// propagates context (e.g. request_id) through to every sink.
func (m *MultiHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	children := make([]slog.Handler, len(m.children))
	for i, h := range m.children {
		children[i] = h.WithAttrs(attrs)
	}
	return &MultiHandler{children: children}
}

// WithGroup returns a new MultiHandler whose children are
// grouped under the given name.
func (m *MultiHandler) WithGroup(name string) slog.Handler {
	children := make([]slog.Handler, len(m.children))
	for i, h := range m.children {
		children[i] = h.WithGroup(name)
	}
	return &MultiHandler{children: children}
}
