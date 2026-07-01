package attachmentanalysis

import (
	"context"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"
)

// AnalysisOp is one unit of work for the analysis sink: a single
// attachment that has just been archived and needs content identification.
type AnalysisOp struct {
	AttachmentID string
	ContentHash  string
	MediaType    string
	FilePath     string // relative path from the attachment storage root
	TenantID     string
	RequestID    string
}

// Sink is a bounded, async, fire-and-forget analysis queue modelled on
// memora.Sink. It decouples the (fast, must-not-block) relay archival
// path from the (slow, network-bound) vision/OCR analysis.
//
// A full queue means "we drop the op" — it MUST NOT block or panic the
// caller. Dropped ops are recoverable: the bg sweeper re-scans for
// pending rows periodically, so a dropped op is merely deferred, not lost.
type Sink struct {
	analyzer *Analyzer
	queue    chan AnalysisOp
	workers  int
	wg       sync.WaitGroup
	started  bool
	mu       sync.Mutex

	enqueued  atomic.Uint64
	dropped   atomic.Uint64
	processed atomic.Uint64
	errored   atomic.Uint64

	lastError   atomic.Value // string
	lastErrorAt atomic.Value // time.Time
}

// NewSink builds a sink. workers and queueSize are clamped to sane
// defaults if non-positive. Vision/OCR calls are slow and sequential, so
// few workers (2) is the right default — more workers just pile on
// concurrent LLM/HTTP load without improving throughput much.
func NewSink(analyzer *Analyzer, workers, queueSize int) *Sink {
	if workers <= 0 {
		workers = 2
	}
	if queueSize <= 0 {
		queueSize = 256
	}
	return &Sink{
		analyzer: analyzer,
		queue:    make(chan AnalysisOp, queueSize),
		workers:  workers,
	}
}

// Start launches worker goroutines. Idempotent.
func (s *Sink) Start() {
	if s == nil || s.analyzer == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.started {
		return
	}
	s.started = true
	for i := 0; i < s.workers; i++ {
		s.wg.Add(1)
		go s.worker()
	}
	slog.Info("attachmentanalysis.sink started",
		"workers", s.workers, "queue_cap", cap(s.queue))
}

// Stop waits for queued items to drain. Pass a context to bound the wait.
// A nil context blocks until all queued items are processed.
func (s *Sink) Stop(ctx context.Context) {
	if s == nil {
		return
	}
	s.mu.Lock()
	if !s.started {
		s.mu.Unlock()
		return
	}
	s.started = false
	s.mu.Unlock()

	close(s.queue)
	done := make(chan struct{})
	go func() { s.wg.Wait(); close(done) }()
	if ctx == nil {
		<-done
		slog.Info("attachmentanalysis.sink stopped cleanly")
		return
	}
	select {
	case <-done:
		slog.Info("attachmentanalysis.sink stopped cleanly")
	case <-ctx.Done():
		slog.Warn("attachmentanalysis.sink stop timed out",
			"dropped", s.dropped.Load())
	}
}

// Enqueue is the ONLY way callers feed the sink. It is O(1) and never
// blocks: a full queue causes the op to be dropped and counted. A dropped
// op is recoverable via the bg sweeper.
func (s *Sink) Enqueue(op AnalysisOp) {
	if s == nil || s.analyzer == nil || op.AttachmentID == "" {
		return
	}
	// Master switch short-circuit — checked here (hot path) AND in the
	// worker, so a runtime toggle-off stops accepting new work promptly.
	if !s.analyzer.Enabled() {
		return
	}
	select {
	case s.queue <- op:
		s.enqueued.Add(1)
	default:
		s.dropped.Add(1)
		slog.Debug("attachmentanalysis.sink dropped op (queue full)",
			"dropped_total", s.dropped.Load(), "attachment_id", op.AttachmentID)
	}
}

// SinkStats holds the counters exposed for /healthz and the admin stats API.
type SinkStats struct {
	Enqueued    uint64 `json:"enqueued"`
	Dropped     uint64 `json:"dropped"`
	Processed   uint64 `json:"processed"`
	Errored     uint64 `json:"errored"`
	QueueLen    int    `json:"queue_len"`
	QueueCap    int    `json:"queue_cap"`
	LastError   string `json:"last_error"`
	LastErrorAt string `json:"last_error_at"`
}

func (s *Sink) Stats() SinkStats {
	if s == nil {
		return SinkStats{}
	}
	st := SinkStats{
		Enqueued:  s.enqueued.Load(),
		Dropped:   s.dropped.Load(),
		Processed: s.processed.Load(),
		Errored:   s.errored.Load(),
		QueueLen:  len(s.queue),
		QueueCap:  cap(s.queue),
	}
	if v, ok := s.lastError.Load().(string); ok {
		st.LastError = v
	}
	if v, ok := s.lastErrorAt.Load().(time.Time); ok && !v.IsZero() {
		st.LastErrorAt = v.Format(time.RFC3339)
	}
	return st
}

func (s *Sink) worker() {
	defer s.wg.Done()
	for op := range s.queue {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		err := s.analyzer.Analyze(ctx, op)
		cancel()
		s.processed.Add(1)
		if err != nil {
			s.errored.Add(1)
			s.lastError.Store(err.Error())
			s.lastErrorAt.Store(time.Now())
			// Log: first 5 errors at Warn, then every 100th, to avoid spam.
			total := s.errored.Load()
			if total <= 5 || total%100 == 0 {
				slog.Warn("attachmentanalysis.sink analyze failed",
					"error", err,
					"attachment_id", op.AttachmentID,
					"errored_total", total)
			}
		}
	}
}
