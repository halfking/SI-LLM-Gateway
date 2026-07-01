package attachmentanalysis

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

// OCRClient extracts text from images by calling an external PaddleOCR /
// PaddleX serving service over HTTP. It is a thin HTTP client — the OCR
// service is deployed independently as a shared public service (per the
// user's requirement that common services be standalone for reuse across
// projects).
//
// The wire format matches the PaddleX basic-serving `POST /ocr` contract
// (confirmed from PaddleOCR 3.7.0's mcp_server self_hosted adapter and
// http_result_parsers):
//
//	Request:  {"file": "<base64 image>", "fileType": 1}
//	Response: {"errorCode": 0, "result": {"ocrResults": [
//	            {"prunedResult": {"rec_texts": [...], "rec_scores": [...], "rec_boxes": [...]}}
//	          ]}}
//
// If the endpoint is empty or unreachable, Extract returns an error and
// the analyzer skips OCR gracefully (the other sources still run).
type OCRClient struct {
	endpoint   string // base URL, e.g. http://ocr-service:8080
	httpClient *http.Client
}

// NewOCRClient builds an OCR client. endpoint is the PaddleX serving base
// URL (the client appends "/ocr"). An empty endpoint yields a client that
// always returns an error — the analyzer treats this as "OCR disabled".
func NewOCRClient(endpoint string, timeout time.Duration) *OCRClient {
	if timeout <= 0 {
		timeout = 120 * time.Second // PaddleOCR default serving timeout is generous
	}
	return &OCRClient{
		endpoint:   strings.TrimRight(endpoint, "/"),
		httpClient: &http.Client{Timeout: timeout},
	}
}

// ocrResponse mirrors the PaddleX serving response shape. Only the fields
// we need are decoded; the rest is ignored.
type ocrResponse struct {
	ErrorCode int    `json:"errorCode"`
	ErrorMsg  string `json:"errorMsg"`
	Result    struct {
		OCRResults []struct {
			PrunedResult struct {
				RecTexts  []string  `json:"rec_texts"`
				RecScores []float64 `json:"rec_scores"`
			} `json:"prunedResult"`
		} `json:"ocrResults"`
	} `json:"result"`
}

// Extract implements OCRSource. It base64-encodes the image, POSTs it to
// the PaddleX /ocr endpoint, and returns the joined recognized text plus
// the average confidence score.
func (c *OCRClient) Extract(ctx context.Context, imageData []byte) (text string, confidence float64, err error) {
	if c == nil || c.endpoint == "" {
		return "", 0, fmt.Errorf("attachmentanalysis: ocr endpoint not configured")
	}

	// PaddleX serving accepts base64 in the "file" field. fileType=1 means image.
	payload := map[string]any{
		"file":     base64Encode(imageData),
		"fileType": 1,
	}
	body, _ := json.Marshal(payload)

	url := c.endpoint + "/ocr"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return "", 0, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", 0, fmt.Errorf("ocr request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 4*1024*1024))
	if err != nil {
		return "", 0, fmt.Errorf("ocr read body: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", 0, fmt.Errorf("ocr HTTP %d: %s", resp.StatusCode, truncate(string(respBody), 500))
	}

	var parsed ocrResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return "", 0, fmt.Errorf("ocr parse response: %w", err)
	}
	if parsed.ErrorCode != 0 {
		return "", 0, fmt.Errorf("ocr service error %d: %s", parsed.ErrorCode, parsed.ErrorMsg)
	}

	// Flatten all pages' recognized text lines. Mirrors PaddleOCR's
	// http_result_parsers.parse_ocr_result: join rec_texts, average rec_scores.
	var texts []string
	var scores []float64
	for _, page := range parsed.Result.OCRResults {
		for i, t := range page.PrunedResult.RecTexts {
			t = strings.TrimSpace(t)
			if t == "" {
				continue
			}
			texts = append(texts, t)
			if i < len(page.PrunedResult.RecScores) {
				scores = append(scores, page.PrunedResult.RecScores[i])
			}
		}
	}

	joined := strings.Join(texts, "\n")
	avgConf := avg(scores)
	slog.Debug("attachmentanalysis: ocr extract ok",
		"text_len", len(joined), "lines", len(texts), "confidence", avgConf)
	return joined, avgConf, nil
}

func avg(v []float64) float64 {
	if len(v) == 0 {
		return 0
	}
	var sum float64
	for _, x := range v {
		sum += x
	}
	return sum / float64(len(v))
}
