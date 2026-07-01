package bg

import (
	"context"
	"log/slog"
	"time"

	"github.com/kaixuan/llm-gateway-go/attachmentanalysis"
)

// AttachmentAnalysisSweeper (2026-07-02) is a periodic background worker
// that recovers attachment-analysis ops lost to a crash or a full queue.
//
// When the gateway restarts, or the analysis sink's queue was full and
// dropped ops, some attachments sit with analysis_status='pending' (or
// NULL) indefinitely. This sweeper scans for them every 5 minutes and
// re-enqueues them. It is the crash-recovery counterpart to the in-path
// enqueue that happens at archival time.
//
// Lifecycle (mirrors bg.PendingSweeper):
//   - Start(ctx) spawns a goroutine that runs every interval
//   - Stop() is cooperative via context cancel; blocks on done
//   - Each tick scans the attachments table for pending rows
type AttachmentAnalysisSweeper struct {
	analyzer  *attachmentanalysis.Analyzer
	sink      *attachmentanalysis.Sink
	interval  time.Duration // default 5 minutes
	batchSize int           // default 200
	// refreshConfig is called at the top of each tick to hot-reload the
	// analyzer's settings snapshot (master switch, per-source switches,
	// OCR endpoint, vision model). nil disables refresh. This is how
	// settings changes propagate without a dedicated change bus — the
	// 5-minute tick is fresh enough for a background subsystem.
	refreshConfig func() attachmentanalysis.Config
	cancel        context.CancelFunc
	done          chan struct{}
}

// NewAttachmentAnalysisSweeper builds a sweeper. The analyzer/sink may be
// nil; in that case Start() is still safe (the sweeper just skips).
func NewAttachmentAnalysisSweeper(analyzer *attachmentanalysis.Analyzer, sink *attachmentanalysis.Sink, interval time.Duration) *AttachmentAnalysisSweeper {
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	return &AttachmentAnalysisSweeper{
		analyzer:  analyzer,
		sink:      sink,
		interval:  interval,
		batchSize: 200,
		done:      make(chan struct{}),
	}
}

// SetConfigRefresher wires the hot-reload callback invoked each tick.
func (s *AttachmentAnalysisSweeper) SetConfigRefresher(fn func() attachmentanalysis.Config) {
	if s != nil {
		s.refreshConfig = fn
	}
}

func (s *AttachmentAnalysisSweeper) Start(ctx context.Context) {
	if s == nil || s.analyzer == nil || s.sink == nil {
		return
	}
	ctx, s.cancel = context.WithCancel(ctx)
	go s.run(ctx)
	slog.Info("attachment_analysis_sweeper started", "interval", s.interval)
}

func (s *AttachmentAnalysisSweeper) Stop() {
	if s == nil {
		return
	}
	if s.cancel != nil {
		s.cancel()
	} else {
		return // Start() was never called
	}
	<-s.done
}

func (s *AttachmentAnalysisSweeper) run(ctx context.Context) {
	defer close(s.done)

	// Stagger the first sweep by a fraction of the interval so it doesn't
	// fire at the exact same instant as startup (which is already busy).
	time.Sleep(s.interval / 4)

	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.sweep(ctx)
		}
	}
}

func (s *AttachmentAnalysisSweeper) sweep(ctx context.Context) {
	// Hot-reload: refresh the analyzer config from settings so toggle
	// changes (master switch, OCR endpoint, per-source switches) take
	// effect without a restart.
	if s.refreshConfig != nil {
		cfg := s.refreshConfig()
		if cfg.OCREnabled && cfg.OCREndpoint != "" {
			// Rebuild the OCR client if the endpoint may have changed.
			s.analyzer.SetOCR(attachmentanalysis.NewOCRClient(cfg.OCREndpoint, 120*time.Second))
		}
		s.analyzer.UpdateConfig(cfg)
	}

	// Only sweep if the master switch is on — otherwise re-enqueuing is
	// pointless (the analyzer will immediately mark them skipped).
	if !s.analyzer.Enabled() {
		return
	}
	scanCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	// tenantID="" scans all tenants (super-admin scope). The pending
	// partial index (idx_attachments_analysis_pending) makes this cheap.
	ops, err := s.analyzer.ScanPending(scanCtx, "", s.batchSize)
	if err != nil {
		slog.Warn("attachment_analysis_sweeper: scan failed", "error", err)
		return
	}
	if len(ops) == 0 {
		return // quiet tick — nothing pending
	}
	enqueued := 0
	for _, op := range ops {
		s.sink.Enqueue(op)
		enqueued++
	}
	slog.Info("attachment_analysis_sweeper: re-enqueued pending",
		"scanned", len(ops), "enqueued", enqueued)
}
