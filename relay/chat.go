// Package relay provides the core chat/completions proxy handler.
//
// In Phase 1, the Go data plane acts as a lightweight reverse proxy that
// forwards requests to the Python control plane.  Future phases will add
// identity-aware connection pooling, request transform, streaming relay,
// concurrency control, and audit.
package relay

import (
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
)

var upstream *url.URL

func init() {
	target := os.Getenv("LLM_GATEWAY_UPSTREAM")
	if target == "" {
		target = "http://127.0.0.1:8780"
	}
	var err error
	upstream, err = url.Parse(target)
	if err != nil {
		slog.Error("invalid LLM_GATEWAY_UPSTREAM", "url", target, "error", err)
		upstream, _ = url.Parse("http://127.0.0.1:8780")
	}
}

// Shared reverse proxy instance (supports streaming via HTTP/1.1).
var proxy = httputil.NewSingleHostReverseProxy(upstream)

func init() {
	proxy.ModifyResponse = func(r *http.Response) error {
		slog.Debug("proxy response",
			"status", r.StatusCode,
			"content_length", r.ContentLength,
		)
		return nil
	}
}

// ChatCompletions handles /v1/chat/completions and /v1/completions by
// forwarding to the Python control plane.
//
// Identity headers (X-Device-Seed, X-Client-Profile, etc.) are forwarded
// as-is so that the Python control plane can perform identity-based routing.
func ChatCompletions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Ensure X-Request-Id from middleware is propagated
	rid := w.Header().Get("X-Request-Id")
	if rid == "" {
		rid = r.Header.Get("X-Request-Id")
	}

	slog.Info("chat completions proxy",
		"request_id", rid,
		"upstream", upstream.String(),
		"stream", r.Header.Get("Accept") == "text/event-stream" || r.URL.Query().Get("stream") == "true",
	)

	proxy.ServeHTTP(w, r)
}
