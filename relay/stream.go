package relay

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

const (
	streamChunkTimeout = 30 * time.Second
	streamBufSize      = 64 * 1024
)

// StreamChat forwards a streaming chat completion from the upstream to the client.
// It reads SSE chunks, replaces model names, and writes to the client response.
func StreamChat(
	w http.ResponseWriter,
	resp *http.Response,
	clientModel string,
	outboundModel string,
) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	var ctx context.Context
	if resp.Request != nil {
		ctx = resp.Request.Context()
	} else {
		ctx = context.Background()
	}
	reader := bufio.NewReaderSize(resp.Body, streamBufSize)
	done := make(chan struct{})

	go func() {
		defer close(done)
		for {
			select {
			case <-ctx.Done():
				return
			default:
			}

			chunkCtx, cancel := context.WithTimeout(ctx, streamChunkTimeout)
			chunkDone := make(chan string, 1)
			chunkErr := make(chan error, 1)

			go func() {
				line, err := reader.ReadString('\n')
				if err != nil {
					chunkErr <- err
					return
				}
				chunkDone <- line
			}()

			var line string
			var err error
			select {
			case line = <-chunkDone:
			case err = <-chunkErr:
			case <-chunkCtx.Done():
				cancel()
				slog.Warn("stream read timeout, sending error chunk")
				safeWriteSSE(w, "data: {\"error\":{\"message\":\"upstream read timeout\",\"type\":\"timeout\",\"code\":\"stream_timeout\"}}\n\n")
				safeFlush(flusher)
				return
			}
			cancel()

			if err != nil {
				if err == io.EOF || strings.Contains(err.Error(), "EOF") {
					safeWriteSSE(w, "data: [DONE]\n\n")
					safeFlush(flusher)
				} else if strings.Contains(err.Error(), "context canceled") {
					slog.Debug("stream cancelled by client")
				} else {
					slog.Warn("stream read error", "error", err)
				}
				return
			}

			line = replaceModelInChunk(line, clientModel, outboundModel)
			safeWriteSSE(w, line)
			safeFlush(flusher)
		}
	}()

	select {
	case <-ctx.Done():
		slog.Debug("client disconnected, cancelling upstream")
	case <-done:
	}
}

func safeFlush(flusher http.Flusher) {
	defer func() {
		if r := recover(); r != nil {
			slog.Debug("flush after close", "recover", r)
		}
	}()
	flusher.Flush()
}

func safeWriteSSE(w io.Writer, line string) {
	defer func() {
		if r := recover(); r != nil {
			slog.Debug("write after close", "recover", r)
		}
	}()
	io.WriteString(w, line)
}

// writeSSE writes a single SSE line to the response writer.
func writeSSE(w io.Writer, line string) {
	_, _ = io.WriteString(w, line)
}

// replaceModelInChunk replaces the model field in SSE data chunks using JSON parsing.
func replaceModelInChunk(line, clientModel, outboundModel string) string {
	if !strings.HasPrefix(line, "data: ") || clientModel == "" || outboundModel == "" {
		return line
	}
	if strings.HasPrefix(line, "data: [DONE]") {
		return line
	}
	jsonStr := strings.TrimPrefix(line, "data: ")
	jsonStr = strings.TrimRight(jsonStr, "\n")

	var obj map[string]json.RawMessage
	if err := json.Unmarshal([]byte(jsonStr), &obj); err != nil {
		return line
	}
	if modelRaw, ok := obj["model"]; ok {
		var modelStr string
		if err := json.Unmarshal(modelRaw, &modelStr); err == nil {
			if modelStr == outboundModel {
				obj["model"], _ = json.Marshal(clientModel)
				newJSON, err := json.Marshal(obj)
				if err == nil {
					return "data: " + string(newJSON) + "\n\n"
				}
			}
		}
	}
	return line
}

func isTimeoutError(err error) bool {
	return strings.Contains(err.Error(), "timeout") ||
		strings.Contains(err.Error(), "deadline exceeded")
}

// BuildSSEChunk constructs an SSE-formatted data chunk.
func BuildSSEChunk(data string) string {
	var b strings.Builder
	scanner := bufio.NewScanner(strings.NewReader(data))
	for scanner.Scan() {
		fmt.Fprintf(&b, "data: %s\n", scanner.Text())
	}
	b.WriteString("\n")
	return b.String()
}

// BuildDoneEvent returns the SSE stream termination event.
func BuildDoneEvent() string { return "data: [DONE]\n\n" }
