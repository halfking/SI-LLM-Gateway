# llm-gateway-go

Go data-plane for the LLM gateway.

## Repository

- Remote: `https://codeup.aliyun.com/kaixuan/official-deploy/llm-gateway-go.git`
- Default branch: `main`

## What it does

- Proxies LLM requests through identity-aware routing.
- Applies circuit breaking, concurrency limiting, and sticky routing.
- Normalizes request/response bodies for OpenAI-compatible and Anthropic-compatible flows.
- Emits audit and telemetry events for both success and failure paths.
- Reads provider, policy, and credential state from the control plane and local database.

## Main flow

1. `cmd/gateway/main.go` boots the service and wires dependencies.
2. `relay/handler.go` receives requests and resolves the execution path.
3. `routing/executor.go` plans candidates and runs upstream attempts.
4. `circuit/breaker.go` and `limiter/limiter.go` gate unhealthy or saturated credentials.
5. `relay/stream.go` handles SSE streaming and interruption tracking.

## High-value modules

- `routing/executor.go`: candidate execution, retries, state writes, sticky routing.
- `relay/handler.go`: HTTP request lifecycle and fallback routing.
- `provider/client.go`: provider/policy resolution.
- `identity/identity.go`: identity hash and virtual address derivation.
- `transform/transform.go`: request transformation and outbound model rendering.
- `circuit/breaker.go`: credential-level circuit state machine.
- `pool/pool.go`: identity-bound connection pools.
- `relay/stream.go`: streaming proxy, timeouts, and keepalives.

## Codegraph summary

- Highest-risk runtime nodes cluster around `circuit/breaker.go`, `errorsx/classify.go`, `limiter/pool/identity/transform`, and `relay/*`.
- `routing/executor.go` is the main hot path that ties candidate planning, retries, circuit state, and credential state together.
- `relay/stream.go` is the most failure-sensitive streaming path.

## Runtime endpoints

- `GET /healthz`
- `POST /v1/chat/completions`
- `POST /v1/completions`
- `POST /v1/messages`
- `POST /v1/responses`
- `GET /v1/models`

## Validation

- `go test ./...`
- `gofmt -w ./...`

## Notes

- This repository is meant to track the `main` branch.
- The Python control plane remains the source of truth for provider and policy management.
