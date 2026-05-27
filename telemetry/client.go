package telemetry

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"time"
)

type Client struct {
	endpoint   string
	adminKey   string
	httpClient *http.Client

	queue chan any
	done  chan struct{}
	wg    sync.WaitGroup
}

type DecisionLogEntry struct {
	RequestID          string  `json:"request_id"`
	IdempotencyKey     *string `json:"idempotency_key,omitempty"`
	TenantID           string  `json:"tenant_id"`
	APIKeyID           *int    `json:"api_key_id,omitempty"`
	Model              string  `json:"model"`
	ChosenCredentialID *int    `json:"chosen_credential_id,omitempty"`
	ChosenProviderID   *int    `json:"chosen_provider_id,omitempty"`
	Tier               *int    `json:"tier,omitempty"`
	CandidatesTried    int     `json:"candidates_tried"`
	LatencyMs          int     `json:"latency_ms"`
	Success            bool    `json:"success"`
	ErrorClass         *string `json:"error_class,omitempty"`
	PromptTokens       *int    `json:"prompt_tokens,omitempty"`
	CompletionTokens   *int    `json:"completion_tokens,omitempty"`
	CostUSD            *float64 `json:"cost_usd,omitempty"`
	RequestBytes       *int    `json:"request_bytes,omitempty"`
	ResponseBytes      *int    `json:"response_bytes,omitempty"`
	ClientModel        *string `json:"client_model,omitempty"`
	ResolvedRawModel   *string `json:"resolved_raw_model,omitempty"`
	OutboundModel      *string `json:"outbound_model,omitempty"`
	StickyHit          *bool   `json:"sticky_hit,omitempty"`
	ClientProfile      *string `json:"client_profile,omitempty"`
	RequestMode        *string `json:"request_mode,omitempty"`
	IdentityHash       *string `json:"identity_hash,omitempty"`
	TransformRuleID    *string `json:"transform_rule_id,omitempty"`
	EgressProtocol     *string `json:"egress_protocol,omitempty"`
	FailureStage       *string `json:"failure_stage,omitempty"`
	FailureDetailCode  *string `json:"failure_detail_code,omitempty"`
}

type RequestLogEntry struct {
	RequestID          string   `json:"request_id"`
	TenantID           string   `json:"tenant_id"`
	ApplicationID      *int     `json:"application_id,omitempty"`
	APIKeyID           *int     `json:"api_key_id,omitempty"`
	EndUserID          *string  `json:"end_user_id,omitempty"`
	ClientModel        *string  `json:"client_model,omitempty"`
	OutboundModel      *string  `json:"outbound_model,omitempty"`
	CredentialID       *int     `json:"credential_id,omitempty"`
	ProviderID         *int     `json:"provider_id,omitempty"`
	CanonicalID        *int     `json:"canonical_id,omitempty"`
	ClientProfile      *string  `json:"client_profile,omitempty"`
	RequestMode        *string  `json:"request_mode,omitempty"`
	PromptTokens       *int     `json:"prompt_tokens,omitempty"`
	CompletionTokens   *int     `json:"completion_tokens,omitempty"`
	CacheReadTokens    *int     `json:"cache_read_tokens,omitempty"`
	CacheWriteTokens   *int     `json:"cache_write_tokens,omitempty"`
	CostUSD            *float64 `json:"cost_usd,omitempty"`
	LatencyMs          *int     `json:"latency_ms,omitempty"`
	Success            bool     `json:"success"`
	ErrorKind          *string  `json:"error_kind,omitempty"`
	IdentityHash       *string  `json:"identity_hash,omitempty"`
	StreamFirstChunkMs *int     `json:"stream_first_chunk_ms,omitempty"`
	StreamChunkCount   *int     `json:"stream_chunk_count,omitempty"`
	StreamDoneReceived *bool    `json:"stream_done_received,omitempty"`
	StreamInterrupted  *bool    `json:"stream_interrupted,omitempty"`
	ResponseChecksum   *string  `json:"response_checksum,omitempty"`
	FailureDetailCode  *string  `json:"failure_detail_code,omitempty"`
	TransformRuleID    *string  `json:"transform_rule_id,omitempty"`
	EgressProtocol     *string  `json:"egress_protocol,omitempty"`
}

func NewClient(pythonEndpoint, adminAPIKey string) *Client {
	c := &Client{
		endpoint:   pythonEndpoint,
		adminKey:   adminAPIKey,
		httpClient: &http.Client{Timeout: 10 * time.Second},
		queue:      make(chan any, 4096),
		done:       make(chan struct{}),
	}
	c.wg.Add(1)
	go c.worker()
	return c
}

func (c *Client) Enabled() bool {
	return c.endpoint != "" && c.adminKey != ""
}

func (c *Client) EmitDecisionLog(entry *DecisionLogEntry) {
	if !c.Enabled() {
		return
	}
	select {
	case c.queue <- entry:
	default:
		slog.Warn("telemetry queue full, dropping decision log", "request_id", entry.RequestID)
	}
}

func (c *Client) EmitRequestLog(entry *RequestLogEntry) {
	if !c.Enabled() {
		return
	}
	select {
	case c.queue <- entry:
	default:
		slog.Warn("telemetry queue full, dropping request log", "request_id", entry.RequestID)
	}
}

func (c *Client) Stop() {
	close(c.done)
	c.wg.Wait()
}

func (c *Client) worker() {
	defer c.wg.Done()

	batch := make([]any, 0, 50)
	timer := time.NewTimer(200 * time.Millisecond)
	defer timer.Stop()

	for {
		select {
		case <-c.done:
			c.flush(batch)
			return
		case item := <-c.queue:
			batch = append(batch, item)
			if len(batch) >= 50 {
				c.flush(batch)
				batch = batch[:0]
				timer.Reset(200 * time.Millisecond)
			} else if len(batch) == 1 {
				timer.Reset(200 * time.Millisecond)
			}
		case <-timer.C:
			if len(batch) > 0 {
				c.flush(batch)
				batch = batch[:0]
			}
		}
	}
}

func (c *Client) flush(batch []any) {
	for _, item := range batch {
		switch v := item.(type) {
		case *DecisionLogEntry:
			c.send("/api/telemetry/decision-log", v)
		case *RequestLogEntry:
			c.send("/api/telemetry/request-log", v)
		}
	}
}

func (c *Client) send(path string, payload any) {
	body, err := json.Marshal(payload)
	if err != nil {
		slog.Warn("telemetry marshal error", "error", err)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint+path, bytes.NewReader(body))
	if err != nil {
		slog.Warn("telemetry request error", "error", err)
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.adminKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		slog.Debug("telemetry send failed", "path", path, "error", err)
		return
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()

	if resp.StatusCode >= 300 {
		slog.Debug("telemetry send non-2xx", "path", path, "status", resp.StatusCode)
	}
}

func intptr(v int) *int       { return &v }
func floatptr(v float64) *float64 { return &v }
func strptr(v string) *string { return &v }
func boolptr(v bool) *bool    { return &v }
