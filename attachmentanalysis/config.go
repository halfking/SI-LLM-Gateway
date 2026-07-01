package attachmentanalysis

import (
	"sync/atomic"
	"time"
)

// Config holds the runtime configuration for the analyzer, populated from
// settings (hot-reloadable). It is stored atomically so the sink workers
// always see a consistent snapshot.
type Config struct {
	Enabled                  bool
	ResponseReuseEnabled     bool
	VisionDescriptionEnabled bool
	OCREnabled               bool
	ClassificationEnabled    bool
	InjectionEnabled         bool
	OCREndpoint              string
	VisionModel              string
	VisionTimeout            time.Duration
}

// AtomicConfig is a pointer-sized atomic holder for Config. Config is
// copied by value on Load/Store, so callers always get a consistent
// snapshot — no partial reads under concurrent hot-reload.
type AtomicConfig struct {
	v atomic.Pointer[Config]
}

func (a *AtomicConfig) Load() Config {
	if p := a.v.Load(); p != nil {
		return *p
	}
	return Config{} // zero value = everything disabled
}

func (a *AtomicConfig) Store(c Config) {
	a.v.Store(&c)
}
