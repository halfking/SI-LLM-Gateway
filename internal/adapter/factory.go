package adapter

import (
	"fmt"
	"strings"
	"sync"
)

// Factory resolves a ProviderAdapter by catalog code or protocol.
//
// Usage:
//
//	factory := adapter.NewFactory()  // registers all built-in adapters
//	adapter, err := factory.Get(cand.CatalogCode)
//	if err != nil {
//	    adapter = factory.GetDefault(cand.Protocol)
//	}
type Factory struct {
	mu       sync.RWMutex
	adapters map[string]ProviderAdapter // keyed by Name()
	catalog  map[string]ProviderAdapter // keyed by CatalogCode
}

// NewFactory creates a Factory pre-populated with all built-in adapters.
// Callers can Register additional adapters at runtime (e.g., for custom
// or self-hosted providers).
func NewFactory() *Factory {
	f := &Factory{
		adapters: make(map[string]ProviderAdapter),
		catalog:  make(map[string]ProviderAdapter),
	}
	for _, a := range defaultAdapters() {
		f.register(a)
	}
	return f
}

// register adds an adapter to the factory. Not thread-safe for the initial
// batch; callers that Register at runtime should hold f.mu.
func (f *Factory) register(a ProviderAdapter) {
	f.adapters[a.Name()] = a
	for _, code := range a.CatalogCodes() {
		f.catalog[strings.ToLower(code)] = a
	}
}

// Register adds or replaces a provider adapter at runtime.
func (f *Factory) Register(a ProviderAdapter) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.register(a)
}

// Get returns the adapter for the given catalog code (e.g., "minimax").
// Returns an error if no adapter matches.
func (f *Factory) Get(catalogCode string) (ProviderAdapter, error) {
	f.mu.RLock()
	defer f.mu.RUnlock()
	a, ok := f.catalog[strings.ToLower(strings.TrimSpace(catalogCode))]
	if !ok {
		return nil, fmt.Errorf("adapter: no adapter for catalog code %q", catalogCode)
	}
	return a, nil
}

// GetOrDefault returns the adapter for the catalog code, falling back to a
// standard adapter based on the wire protocol when no provider-specific
// adapter is registered. This keeps legacy providers working without an
// explicit adapter.
//
//   protocol "anthropic-messages" → StandardAnthropic
//   protocol "openai-completions" or anything else → StandardOpenAI
func (f *Factory) GetOrDefault(catalogCode, protocol string) ProviderAdapter {
	f.mu.RLock()
	defer f.mu.RUnlock()
	if a, ok := f.catalog[strings.ToLower(strings.TrimSpace(catalogCode))]; ok {
		return a
	}
	// Fallback by protocol.
	if strings.EqualFold(protocol, "anthropic-messages") {
		return f.adapters["anthropic"]
	}
	return f.adapters["openai"]
}

// Names returns the sorted list of registered adapter names (for the admin UI).
func (f *Factory) Names() []string {
	f.mu.RLock()
	defer f.mu.RUnlock()
	out := make([]string, 0, len(f.adapters))
	for name := range f.adapters {
		out = append(out, name)
	}
	return out
}
