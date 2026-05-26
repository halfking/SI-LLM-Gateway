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
// It reads SSE chunks, discovers the upstream model name from the first chunk,
// and replaces it with clientModel in all subsequent chunks.
func StreamChat(
	w http.ResponseWriter,
	resp *http.Response,
	clientModel string,
	_ string,
	norm *Normalizer,
) {
	defer resp.Body.Close()

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
	discoveredUpstream := ""

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		line, err := readLineWithTimeout(ctx, reader)
		if err != nil {
			if err == io.EOF || strings.Contains(err.Error(), "EOF") {
				safeWriteSSE(w, "data: [DONE]\n\n")
				safeFlush(flusher)
			} else if strings.Contains(err.Error(), "context canceled") {
				slog.Debug("stream cancelled by client")
			} else if strings.Contains(err.Error(), "timeout") {
				slog.Warn("stream read timeout, sending error chunk")
				safeWriteSSE(w, "data: {\"error\":{\"message\":\"upstream read timeout\",\"type\":\"timeout\",\"code\":\"stream_timeout\"}}\n\n")
				safeFlush(flusher)
			} else {
				slog.Warn("stream read error", "error", err)
			}
			return
		}

		if clientModel != "" {
			if discoveredUpstream == "" {
				discoveredUpstream = extractModelFromChunk(line)
			}
			line = replaceModelInChunk(line, clientModel, discoveredUpstream)
		}

		if norm != nil {
			line = string(norm.NormalizeChunk([]byte(line), true))
		}

		safeWriteSSE(w, line)
		safeFlush(flusher)
	}
}

func readLineWithTimeout(ctx context.Context, reader *bufio.Reader) (string, error) {
	type result struct {
		line string
		err  error
	}
	ch := make(chan result, 1)
	ctx, cancel := context.WithTimeout(ctx, streamChunkTimeout)
	defer cancel()

	go func() {
		defer func() {
			if r := recover(); r != nil {
				ch <- result{"", fmt.Errorf("read panic: %v", r)}
			}
		}()
		line, err := reader.ReadString('\n')
		ch <- result{line, err}
	}()

	select {
	case r := <-ch:
		return r.line, r.err
	case <-ctx.Done():
		if ctx.Err() == context.DeadlineExceeded {
			return "", fmt.Errorf("stream read timeout")
		}
		return "", ctx.Err()
	}
}

func extractModelFromChunk(line string) string {
	if !strings.HasPrefix(line, "data: ") || strings.HasPrefix(line, "data: [DONE") {
		return ""
	}
	jsonStr := strings.TrimPrefix(line, "data: ")
	jsonStr = strings.TrimSpace(jsonStr)
	var obj map[string]json.RawMessage
	if err := json.Unmarshal([]byte(jsonStr), &obj); err != nil {
		return ""
	}
	if modelRaw, ok := obj["model"]; ok {
		var modelStr string
		if err := json.Unmarshal(modelRaw, &modelStr); err == nil {
			return modelStr
		}
	}
	return ""
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

func replaceModelInChunk(line, clientModel, discoveredUpstream string) string {
	if !strings.HasPrefix(line, "data: ") || clientModel == "" {
		return line
	}
	if strings.HasPrefix(line, "data: [DONE") {
		return line
	}
	jsonStr := strings.TrimPrefix(line, "data: ")
	jsonStr = strings.TrimSpace(jsonStr)

	var obj map[string]json.RawMessage
	if err := json.Unmarshal([]byte(jsonStr), &obj); err != nil {
		return line
	}
	modelRaw, ok := obj["model"]
	if !ok {
		return line
	}
	var modelStr string
	if err := json.Unmarshal(modelRaw, &modelStr); err != nil {
		return line
	}
	if modelStr == clientModel {
		return line
	}
	if discoveredUpstream != "" && modelStr != discoveredUpstream {
		return line
	}
	obj["model"], _ = json.Marshal(clientModel)
	newJSON, err := json.Marshal(obj)
	if err != nil {
		return line
	}
	return "data: " + string(newJSON) + "\n"
}

func BuildSSEChunk(data string) string {
	var b strings.Builder
	scanner := bufio.NewScanner(strings.NewReader(data))
	for scanner.Scan() {
		fmt.Fprintf(&b, "data: %s\n", scanner.Text())
	}
	b.WriteString("\n")
	return b.String()
}
