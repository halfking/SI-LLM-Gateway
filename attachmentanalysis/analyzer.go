package attachmentanalysis

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Analyzer orchestrates the content-identification pipeline for a single
// attachment. It is constructed once at startup and shared by the Sink
// (and by manual re-analyze admin requests). The sources it dispatches to
// are pluggable — each can be nil/disabled without affecting the others.
type Analyzer struct {
	store       *store
	storagePath string // attachments storage root, for reading image files
	cfg         AtomicConfig

	// Source providers. nil = that source is unavailable. The Enabled()
	// method checks both the per-source switch in cfg AND whether the
	// provider is wired.
	responseReuse ResponseReuseSource
	vision        VisionSource
	ocr           OCRSource
	classifier    ClassifierSource
}

// ResponseReuseSource provides description text derived from the upstream
// LLM response (source A — zero cost). SetResponseText is called by the
// relay pipeline when the response is available.
type ResponseReuseSource interface {
	// GetDescription returns the cached response text for a request, if any.
	// Returns "", false if none is available yet.
	GetDescription(requestID, tenantID string) (string, bool)
}

// VisionSource generates a description by calling a vision-capable LLM
// (source C — 1 LLM call). Implemented via gateway self-loopback.
type VisionSource interface {
	Describe(ctx context.Context, imageData []byte, mediaType string) (string, error)
}

// OCRSource extracts text from an image via an external OCR service
// (source D — external HTTP call to PaddleOCR/PaddleX).
type OCRSource interface {
	Extract(ctx context.Context, imageData []byte) (text string, confidence float64, err error)
}

// ClassifierSource assigns tags from OCR text + description (source E —
// local, zero cost).
type ClassifierSource interface {
	Classify(ocrText, description string) []string
}

// NewAnalyzer creates an analyzer wired to the DB and attachment storage.
// Source providers are set via the Set* methods (or left nil for sources
// that aren't enabled).
func NewAnalyzer(pool *pgxpool.Pool, storagePath string) *Analyzer {
	return &Analyzer{
		store:       newStore(pool),
		storagePath: storagePath,
	}
}

// SetResponseReuse wires source A.
func (a *Analyzer) SetResponseReuse(s ResponseReuseSource) { a.responseReuse = s }

// SetVision wires source C.
func (a *Analyzer) SetVision(s VisionSource) { a.vision = s }

// SetOCR wires source D.
func (a *Analyzer) SetOCR(s OCRSource) { a.ocr = s }

// SetClassifier wires source E.
func (a *Analyzer) SetClassifier(s ClassifierSource) { a.classifier = s }

// UpdateConfig atomically swaps the runtime config (called when settings
// hot-reload). Safe to call concurrently with Analyze.
func (a *Analyzer) UpdateConfig(cfg Config) { a.cfg.Store(cfg) }

// Enabled reports whether the master switch is on.
func (a *Analyzer) Enabled() bool { return a.cfg.Load().Enabled }

// Analyze runs the full pipeline for one attachment. It is idempotent for
// the done state (a re-analyze forces a fresh pass). Each source is
// best-effort: a failure in one does not abort the others. The final
// result is merged into the attachment's metadata JSONB.
func (a *Analyzer) Analyze(ctx context.Context, op AnalysisOp) error {
	cfg := a.cfg.Load()
	if !cfg.Enabled {
		return a.store.SetStatus(ctx, op.AttachmentID, statusSkipped)
	}

	// ── Source B: hash cache ────────────────────────────────────────
	// If a sibling attachment with the same content_hash already has a
	// completed analysis, reuse its content_identification verbatim.
	// This is the highest-value, zero-cost shortcut.
	if cached, ok, _ := a.store.FindByHashDone(ctx, op.ContentHash, op.TenantID); ok {
		slog.Info("attachmentanalysis: hash cache hit",
			"attachment_id", op.AttachmentID, "hash_prefix", safeHashPrefix(op.ContentHash))
		cached.DescriptionSource = "hash_cache"
		return a.store.MarkDone(ctx, op.AttachmentID, cached)
	}

	// Mark as analyzing.
	if err := a.store.SetStatus(ctx, op.AttachmentID, statusAnalyzing); err != nil {
		return fmt.Errorf("set status analyzing: %w", err)
	}

	// Read the image file once; shared by vision and OCR.
	var imageData []byte
	if a.visionEnabled(cfg) || a.ocrEnabled(cfg) {
		var err error
		imageData, err = a.readImage(op.FilePath)
		if err != nil {
			a.markFailed(ctx, op.AttachmentID, "read image: "+err.Error())
			return err
		}
	}

	var ci ContentIdentification

	// ── Source A: response reuse ───────────────────────────────────
	if a.responseReuseEnabled(cfg) && a.responseReuse != nil {
		if text, ok := a.responseReuse.GetDescription(op.RequestID, op.TenantID); ok && text != "" {
			ci.Description = truncate(text, 2000)
			ci.DescriptionSource = "response_reuse"
		}
	}

	// ── Source C: vision LLM description ───────────────────────────
	if a.visionEnabled(cfg) && a.vision != nil && imageData != nil {
		vctx, vcancel := context.WithTimeout(ctx, cfg.VisionTimeout)
		desc, err := a.vision.Describe(vctx, imageData, op.MediaType)
		vcancel()
		if err != nil {
			slog.Warn("attachmentanalysis: vision describe failed",
				"attachment_id", op.AttachmentID, "error", err)
			// Don't abort — fall through to other sources.
		} else if desc != "" {
			// Vision description is higher-quality than response reuse;
			// prefer it if response reuse didn't already fill in.
			ci.Description = truncate(desc, 2000)
			ci.DescriptionSource = "vision_loopback"
		}
	}

	// ── Source D: OCR ──────────────────────────────────────────────
	if a.ocrEnabled(cfg) && a.ocr != nil && imageData != nil {
		octx, ocancel := context.WithTimeout(ctx, 60*time.Second)
		text, conf, err := a.ocr.Extract(octx, imageData)
		ocancel()
		if err != nil {
			slog.Warn("attachmentanalysis: ocr extract failed",
				"attachment_id", op.AttachmentID, "error", err)
		} else if text != "" {
			ci.OCRText = truncate(text, 5000)
			ci.OCRConfidence = conf
		}
	}

	// ── Source E: classification ───────────────────────────────────
	if a.classificationEnabled(cfg) && a.classifier != nil {
		ci.Tags = a.classifier.Classify(ci.OCRText, ci.Description)
	}

	// Build a short summary from whichever source produced text.
	ci.Summary = buildSummary(ci)

	return a.store.MarkDone(ctx, op.AttachmentID, ci)
}

func (a *Analyzer) readImage(relPath string) ([]byte, error) {
	absPath := filepath.Join(a.storagePath, relPath)
	return os.ReadFile(absPath)
}

func (a *Analyzer) markFailed(ctx context.Context, attachmentID, reason string) {
	if err := a.store.MergeMetadata(ctx, attachmentID, map[string]any{
		"analysis_status": statusFailed,
		"analysis_error":  reason,
	}); err != nil {
		slog.Error("attachmentanalysis: markFailed write error",
			"attachment_id", attachmentID, "error", err)
	}
}

// ── per-source enable checks (switch AND provider wired) ─────────────

func (a *Analyzer) responseReuseEnabled(cfg Config) bool {
	return cfg.ResponseReuseEnabled && a.responseReuse != nil
}
func (a *Analyzer) visionEnabled(cfg Config) bool {
	return cfg.VisionDescriptionEnabled && a.vision != nil
}
func (a *Analyzer) ocrEnabled(cfg Config) bool {
	return cfg.OCREnabled && a.ocr != nil
}
func (a *Analyzer) classificationEnabled(cfg Config) bool {
	return cfg.ClassificationEnabled && a.classifier != nil
}

// ── admin / sweeper helpers ───────────────────────────────────────────

// ForceReanalyze resets an attachment to pending and re-runs the full
// pipeline synchronously (bypassing the hash-cache shortcut). Used by the
// admin re-analyze endpoint when an operator wants a fresh pass after
// enabling a new source or changing a model. It is blocking — callers
// from the HTTP path should run it in the sink worker, not inline.
//
// Implementation: reset status, then call Analyze. Analyze skips the hash
// cache only for non-done rows; since we set pending, it runs fresh.
func (a *Analyzer) ForceReanalyze(ctx context.Context, op AnalysisOp) error {
	if !a.Enabled() {
		return a.store.SetStatus(ctx, op.AttachmentID, statusSkipped)
	}
	// Clear any prior done/error so Analyze does a fresh pass.
	if err := a.store.SetStatus(ctx, op.AttachmentID, statusPending); err != nil {
		return err
	}
	return a.Analyze(ctx, op)
}

// ScanPending returns up to limit attachments whose analysis is pending or
// never started (metadata is NULL or analysis_status in (NULL, 'pending')).
// Used by the admin recovery endpoint and the bg sweeper. tenantID="" means
// all tenants (super_admin scope).
func (a *Analyzer) ScanPending(ctx context.Context, tenantID string, limit int) ([]AnalysisOp, error) {
	return a.store.ScanPending(ctx, tenantID, limit)
}

// FindByHashDone implements InjectionLookup so the relay's feature-#4
// injector can look up a completed description by image content hash.
// Returns the cached ContentIdentification and whether a done result exists.
func (a *Analyzer) FindByHashDone(ctx context.Context, contentHash, tenantID string) (ContentIdentification, bool, error) {
	return a.store.FindByHashDone(ctx, contentHash, tenantID)
}

// ── helpers ───────────────────────────────────────────────────────────

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max]
}

func safeHashPrefix(h string) string {
	if len(h) >= 12 {
		return h[:12]
	}
	return h
}

func buildSummary(ci ContentIdentification) string {
	// Prefer OCR text (most concrete), fall back to description.
	if ci.OCRText != "" {
		return truncate(ci.OCRText, 200)
	}
	if ci.Description != "" {
		return truncate(ci.Description, 200)
	}
	return ""
}
