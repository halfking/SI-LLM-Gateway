// Package attachmentanalysis provides asynchronous content identification
// for archived image attachments. It is a side-channel observer — like the
// attachments manager itself — that enriches attachment rows with
// descriptions, OCR text, and classification tags stored in the existing
// metadata JSONB column.
//
// Five identification sources, layered by cost:
//
//   - A. response reuse — zero cost, reuses the already-captured upstream
//     LLM response text as a description (only meaningful when the user
//     asked about the image).
//   - B. hash cache — zero cost, reuses a prior analysis result for the
//     same content_hash (the foundation of injection).
//   - C. vision LLM description — 1 LLM call, via gateway self-loopback.
//   - D. OCR — external HTTP call to a PaddleOCR/PaddleX service.
//   - E. classification — local, derived from OCR text + description.
//
// Each source has an independent switch (settings) because every source
// carries a processing cost. Analysis never blocks the request path: it
// runs in a bounded worker queue (modelled on memora.Sink).
package attachmentanalysis

// analysis_status values stored under metadata->>'analysis_status'.
const (
	statusPending   = "pending"
	statusAnalyzing = "analyzing"
	statusDone      = "done"
	statusFailed    = "failed"
	statusSkipped   = "skipped"
)

// ContentIdentification is the structured result stored under
// metadata->'content_identification'. Fields are omitempty so partial
// results (e.g. only OCR, no description) serialise cleanly.
type ContentIdentification struct {
	Description       string   `json:"description,omitempty"`
	DescriptionSource string   `json:"description_source,omitempty"` // vision_loopback | response_reuse | hash_cache
	OCRText           string   `json:"ocr_text,omitempty"`
	OCRConfidence     float64  `json:"ocr_confidence,omitempty"`
	Tags              []string `json:"tags,omitempty"`
	Summary           string   `json:"summary,omitempty"`
}
