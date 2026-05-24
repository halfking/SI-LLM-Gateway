# syntax=docker/dockerfile:1
# Multi-stage build for llm-gateway-go data plane
# Build with: docker build --platform linux/amd64 -t kx-llm-gateway-go:latest .

# ── Build stage ──────────────────────────────────────────────────────────────
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG TARGETOS TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -ldflags="-s -w" -o /llm-gateway-go ./cmd/gateway

# ── Runtime stage ───────────────────────────────────────────────────────────
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata && \
    adduser -D -u 1001 llmgw

COPY --from=builder /llm-gateway-go /usr/local/bin/llm-gateway-go

USER llmgw

EXPOSE 8781

ENTRYPOINT ["/usr/local/bin/llm-gateway-go"]
