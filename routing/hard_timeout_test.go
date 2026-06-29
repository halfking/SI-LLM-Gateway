package routing

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// TestDoUpstreamWithHardTimeout verifies that when the upstream is silent
// (server accepts connection but never responds), the wrapper returns within
// the configured context budget instead of waiting for the http.Client's own
// (much longer) timeouts.
//
// This guards against the 2026-06-28 P0 regression found by the prod_e2e suite:
// certain foreign-via-proxy upstreams silently accept the connection but never
// respond, and the underlying http.Client.Timeout/ResponseHeaderTimeout fail
// to fire — the executor was stalled for 3+ minutes per request.
//
// To reproduce the production bug in the test we use a TCP server (not
// httptest) that accepts the connection, reads the request body, then
// "stalls" — like a hung HTTP proxy. We then verify the wrapper returns
// within the configured budget rather than waiting for http.Client.Timeout
// (which in production is 120s; the wrapper should override that to the
// configured ctx deadline).
func TestDoUpstreamWithHardTimeout(t *testing.T) {
	// TCP-level "hung" server: accept, read request bytes, then never write.
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer listener.Close()
	addr := listener.Addr().String()

	// Server goroutine: accept one connection, read until EOF, then block.
	release := make(chan struct{})
	defer close(release)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		// Read request bytes (just to consume them).
		go func() {
			buf := make([]byte, 8192)
			for {
				if _, rerr := conn.Read(buf); rerr != nil {
					return
				}
			}
		}()
		<-release // wait until test releases us
	}()

	req, err := http.NewRequest(http.MethodPost, "http://"+addr+"/", strings.NewReader(`{"x":1}`))
	if err != nil {
		t.Fatalf("build request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// 500ms hard deadline.
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()
	// Deliberately LONG http.Client.Timeout to demonstrate that the wrapper
	// bounds the wait to ctx, not http.Client.Timeout. (In production we
	// observed http.Client.Timeout fail to fire through the proxy.)
	httpClient := &http.Client{Timeout: 30 * time.Second}

	start := time.Now()
	resp, uErr := doUpstreamRawWithHardTimeout(req, ctx, httpClient)
	elapsed := time.Since(start)

	if resp != nil {
		t.Errorf("expected nil resp on hard-timeout, got %v", resp)
	}
	if uErr == nil {
		t.Fatalf("expected non-nil uErr on hard-timeout")
	}
	if uErr.Kind != "timeout" {
		t.Errorf("expected KindTimeout, got %q (msg=%s)", uErr.Kind, uErr.Message)
	}
	// The wrapper's watchdog fires after upCtx + a few hundred ms for body
	// close. Allow up to 2s slack. (The 5s inner watchdog caps things.)
	if elapsed > 3*time.Second {
		t.Errorf("wrapper took %v, expected < 3s (ctx was 500ms)", elapsed)
	}
	t.Logf("PASS: wrapper returned in %v with kind=%s", elapsed, uErr.Kind)
}

// TestDoUpstreamWithHardTimeout_NormalResponse verifies the happy path: when
// the upstream returns quickly, the wrapper returns the response unchanged
// without waiting for the context.
func TestDoUpstreamWithHardTimeout_NormalResponse(t *testing.T) {
	fastServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer fastServer.Close()

	req, err := http.NewRequest(http.MethodPost, fastServer.URL, strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("build request: %v", err)
	}

	// 5s ctx — should never fire.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	httpClient := &http.Client{Timeout: 5 * time.Second}
	resp, uErr := doUpstreamRawWithHardTimeout(req, ctx, httpClient)
	if uErr != nil {
		t.Fatalf("expected nil uErr on success, got %v", uErr)
	}
	if resp == nil {
		t.Fatalf("expected non-nil resp on success")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("expected 200, got %d", resp.StatusCode)
	}
}

// TestDoUpstreamWithHardTimeout_ServerErrorReturnsImmediately verifies that
// when the upstream returns a 4xx/5xx immediately, the wrapper propagates the
// response so the executor's existing 4xx/5xx classification logic runs
// (we don't intercept those — we only intercept the *silent* hang case).
func TestDoUpstreamWithHardTimeout_ServerErrorReturnsImmediately(t *testing.T) {
	errServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`internal error`))
	}))
	defer errServer.Close()

	req, err := http.NewRequest(http.MethodPost, errServer.URL, strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("build request: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	httpClient := &http.Client{Timeout: 2 * time.Second}
	resp, uErr := doUpstreamRawWithHardTimeout(req, ctx, httpClient)
	if uErr != nil {
		t.Fatalf("expected nil uErr (5xx handled in caller), got %v", uErr)
	}
	if resp == nil {
		t.Fatalf("expected non-nil resp for 5xx passthrough")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", resp.StatusCode)
	}
}