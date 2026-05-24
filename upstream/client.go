// Package upstream provides an HTTP client wrapper for upstream LLM provider
// calls with configurable timeouts, retry, and error classification.
package upstream

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/kaixuan/llm-gateway-go/identity"
)

const (
	maxRetries      = 2
	retryBaseDelay  = 500 * time.Millisecond
	defaultTimeout  = 120 * time.Second
	connectTimeout  = 10 * time.Second
)

// ErrorKind classifies the upstream error for circuit-breaker / audit.
type ErrorKind string

const (
	KindTransient    ErrorKind = "transient"
	KindTimeout      ErrorKind = "timeout"
	KindNetwork      ErrorKind = "network"
	KindRateLimit    ErrorKind = "rate_limit"
	KindAuth         ErrorKind = "auth"
	KindQuota        ErrorKind = "quota"
	KindUpstreamDown ErrorKind = "upstream_down"
)

// Error carries the classified error kind and original error.
type Error struct {
	Kind    ErrorKind
	Message string
	Err     error
}

func (e *Error) Error() string { return fmt.Sprintf("[%s] %s: %v", e.Kind, e.Message, e.Err) }
func (e *Error) Unwrap() error { return e.Err }

// classifyError maps HTTP status / Go errors to ErrorKind.
func classifyError(err error, resp *http.Response) ErrorKind {
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "timeout") || strings.Contains(msg, "deadline") {
			return KindTimeout
		}
		if strings.Contains(msg, "connection") || strings.Contains(msg, "refused") ||
			strings.Contains(msg, "no such host") || strings.Contains(msg, "reset") {
			return KindNetwork
		}
		return KindTransient
	}
	if resp == nil {
		return KindUpstreamDown
	}
	switch {
	case resp.StatusCode == 429:
		return KindRateLimit
	case resp.StatusCode == 401 || resp.StatusCode == 403:
		return KindAuth
	case resp.StatusCode == 402:
		return KindQuota
	case resp.StatusCode >= 500:
		return KindUpstreamDown
	default:
		return KindTransient
	}
}

// Client wraps http.Client with upstream-specific configuration.
type Client struct {
	hc          *http.Client
	maxRetries  int
	baseDelay   time.Duration
}

// New creates a new upstream client with sensible defaults.
func New() *Client {
	return &Client{
		hc: &http.Client{
			Timeout: defaultTimeout,
			Transport: &http.Transport{
				IdleConnTimeout: 90 * time.Second,
				DialContext: (&net.Dialer{
					Timeout:   connectTimeout,
					KeepAlive: 30 * time.Second,
				}).DialContext,
				MaxIdleConns:        128,
				MaxIdleConnsPerHost: 32,
			},
		},
		maxRetries: maxRetries,
		baseDelay:  retryBaseDelay,
	}
}

// Do sends an HTTP request with retry and error classification.
// It does NOT close the response body — caller must do that.
func (c *Client) Do(req *http.Request) (*http.Response, *Error) {
	var (
		resp *http.Response
		uErr *Error
	)
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			delay := c.baseDelay * (1 << (attempt - 1))
			slog.Debug("upstream retry", "attempt", attempt, "delay_ms", delay.Milliseconds())
			select {
			case <-req.Context().Done():
				return nil, &Error{Kind: KindTimeout, Message: "context cancelled", Err: req.Context().Err()}
			case <-time.After(delay):
			}
		}

		var doErr error
		resp, doErr = c.hc.Do(req)
		if doErr == nil && resp.StatusCode < 500 {
			return resp, nil
		}

		kind := classifyError(doErr, resp)
		if !isRetryable(kind) {
			msg := ""
			if doErr != nil {
				msg = doErr.Error()
			} else if resp != nil {
				body, _ := io.ReadAll(resp.Body)
				resp.Body.Close()
				msg = strings.TrimSpace(string(body))
			}
			return resp, &Error{Kind: kind, Message: msg, Err: doErr}
		}
		if resp != nil {
			resp.Body.Close()
		}
		uErr = &Error{Kind: kind, Message: "retry exhausted", Err: doErr}
	}
	return resp, uErr
}

func isRetryable(kind ErrorKind) bool {
	switch kind {
	case KindTransient, KindTimeout, KindNetwork, KindUpstreamDown, KindRateLimit:
		return true
	default:
		return false
	}
}

// BuildUpstreamRequest creates an HTTP request to the upstream LLM provider.
func BuildUpstreamRequest(
	ctx context.Context,
	baseURL string,
	apiKey string,
	model string,
	body io.Reader,
	stream bool,
	id *identity.ClientIdentity,
) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/v1/chat/completions", body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)
	if stream {
		req.Header.Set("Accept", "text/event-stream")
	}
	// Forward identity labels as upstream headers (not the raw fingerprint)
	if id != nil {
		req.Header.Set("X-Virtual-Client-Id", id.VirtualClientID)
		req.Header.Set("X-Virtual-IP", id.VirtualIP)
		req.Header.Set("X-Virtual-MAC", id.VirtualMAC)
	}
	return req, nil
}
