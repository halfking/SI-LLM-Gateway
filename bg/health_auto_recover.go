package bg

import (
	"context"
	"log/slog"
	"time"

	"github.com/kaixuan/llm-gateway-go/credentialhealth"
)

// HealthAutoRecover checks for credentials with expired availability_recover_at
// and restores them to 'ready' state.
type HealthAutoRecover struct {
	db              credentialhealth.DBQuerier
	interval        time.Duration // default 1 minute
	invalidateCache func()        // optional candCache invalidator (nil → no-op)
	stopCh          chan struct{}
}

// NewHealthAutoRecover creates a recovery worker.
//
// invalidateCache is invoked once per tick after a successful recovery so the
// provider.Client.candCache picks up the restored cmb.available=TRUE on the
// very next request, rather than waiting up to 30s for the cache TTL to
// expire. This closes the gap behind the 2026-07-03 minimax-m3 incident
// (request a69a71a05e6610adcf55df32f2618797) where the route was healthy in
// the session but the router kept returning "no available provider" until
// the candCache TTL naturally expired. Pass nil in tests where the cache
// is not wired.
func NewHealthAutoRecover(
	db credentialhealth.DBQuerier,
	interval time.Duration,
	invalidateCache func(),
) *HealthAutoRecover {
	if interval == 0 {
		interval = 1 * time.Minute
	}

	return &HealthAutoRecover{
		db:              db,
		interval:        interval,
		invalidateCache: invalidateCache,
		stopCh:          make(chan struct{}),
	}
}

// Start begins the recovery loop.
func (w *HealthAutoRecover) Start(ctx context.Context) {
	slog.Info("health_auto_recover started", "interval", w.interval)

	go func() {
		ticker := time.NewTicker(w.interval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				slog.Info("health_auto_recover stopping")
				return
			case <-w.stopCh:
				slog.Info("health_auto_recover stopped")
				return
			case <-ticker.C:
				if err := w.recover(ctx); err != nil {
					slog.Error("health_auto_recover failed", "error", err)
				}
			}
		}
	}()
}

// Stop gracefully stops the worker.
func (w *HealthAutoRecover) Stop() {
	close(w.stopCh)
}

// recover restores expired credentials to 'ready' state.
func (w *HealthAutoRecover) recover(ctx context.Context) error {
	count, err := credentialhealth.RecoverExpired(ctx, w.db, w.invalidateCache)
	if err != nil {
		return err
	}

	if count > 0 {
		slog.Info("health_auto_recover: recovered credentials", "count", count)
	}

	return nil
}
