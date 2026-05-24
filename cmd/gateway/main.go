// Command gateway is the LLM Gateway Go data-plane entry point.
//
// Usage:
//
//	LLM_GATEWAY_LISTEN=:8781 LLM_GATEWAY_API_KEY=... go run ./cmd/gateway
//
// Environment variables:
//
//	LLM_GATEWAY_LISTEN             TCP listen address (default ":8781")
//	LLM_GATEWAY_API_KEY            Gateway API key for client auth (empty = disabled)
//	LLM_GATEWAY_LOG_LEVEL          Log level: debug, info, warn, error (default "info")
//	LLM_GATEWAY_DEFAULT_PROVIDER   Default provider ID (default "1")
//	LLM_GATEWAY_DEFAULT_CREDENTIAL Default credential ID (default "1")
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kaixuan/llm-gateway-go/circuit"
	"github.com/kaixuan/llm-gateway-go/limiter"
	"github.com/kaixuan/llm-gateway-go/middleware"
	"github.com/kaixuan/llm-gateway-go/pool"
	"github.com/kaixuan/llm-gateway-go/relay"
	"github.com/kaixuan/llm-gateway-go/resolve"
	"github.com/kaixuan/llm-gateway-go/transform"
)

func main() {
	// ── Logging ───────────────────────────────────────────────────────────
	level := slog.LevelInfo
	if l := os.Getenv("LLM_GATEWAY_LOG_LEVEL"); l != "" {
		switch l {
		case "debug":
			level = slog.LevelDebug
		case "warn":
			level = slog.LevelWarn
		case "error":
			level = slog.LevelError
		}
	}
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
		Level: level,
	})))

	// ── Dependencies ──────────────────────────────────────────────────────
	cm := circuit.NewManager()
	lim := limiter.New()

	matrixPath := transform.DefaultMatrixPath()
	matrix := transform.New(matrixPath)

	pythonEndpoint := os.Getenv("LLM_GATEWAY_PYTHON_ENDPOINT")
	resolver := resolve.NewResolver(pythonEndpoint, 120*time.Second)

	pools := pool.NewPoolManager()

	chatHandler := relay.NewChatHandler(cm, lim, matrix, pools, resolver)
	healthHandler := relay.NewHealthHandler(cm, lim)

	// ── Listen address ────────────────────────────────────────────────────
	listen := os.Getenv("LLM_GATEWAY_LISTEN")
	if listen == "" {
		listen = ":8781"
	}

	// ── Router ────────────────────────────────────────────────────────────
	mux := http.NewServeMux()

	// Health
	mux.Handle("/healthz", healthHandler)

	// Chat completions
	mux.Handle("/v1/chat/completions", chatHandler)
	mux.Handle("/v1/completions", chatHandler)

	// Legacy health endpoint
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			w.Write([]byte(`{"service":"llm-gateway-go","version":"0.2.0"}`))
			return
		}
		http.NotFound(w, r)
	})

	// ── Middleware stack ──────────────────────────────────────────────────
	handler := middleware.APIKeyAuth(mux)
	handler = middleware.WithRequestID(handler)
	handler = middleware.WithLogging(handler)

	srv := &http.Server{
		Addr:         listen,
		Handler:      handler,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 300 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// ── Graceful shutdown ─────────────────────────────────────────────────
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		slog.Info("gateway starting", "listen", listen)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("gateway listen failed", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	slog.Info("gateway shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// Stop background loops
	lim.Stop()
	pools.CloseAll()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("gateway shutdown error", "error", err)
	}
	slog.Info("gateway stopped")
}
