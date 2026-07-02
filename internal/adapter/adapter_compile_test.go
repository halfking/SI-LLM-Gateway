package adapter

// Compile-time interface compliance checks.
// These asserts ensure every adapter fully implements ProviderAdapter.
// If an adapter is missing a method, `go build` / `go test` fails here
// with a clear "does not implement" error.

var (
	_ ProviderAdapter = (*Minimax)(nil)
	_ ProviderAdapter = (*DeepSeek)(nil)
	_ ProviderAdapter = (*Qwen)(nil)
	_ ProviderAdapter = (*Doubao)(nil)
	_ ProviderAdapter = (*Moonshot)(nil)
	_ ProviderAdapter = (*Zhipu)(nil)
	_ ProviderAdapter = StandardAnthropic{}
	_ ProviderAdapter = StandardOpenAI{}
)
