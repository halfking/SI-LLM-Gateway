package relay

import (
	"bufio"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"runtime/debug"
	"strings"

	"github.com/kaixuan/llm-gateway-go/audit"
	"github.com/kaixuan/llm-gateway-go/routing"
)

const anthropicSSEBufSize = 64 * 1024

// StreamAnthropicPassthrough is the Q4 Anthropic SSE forwarder. It reads
// Anthropic-format SSE events from upstream and writes them to the
// client unchanged (byte-for-byte), while scanning for has_thinking /
// usage accounting in the side-channel audit capture.
//
// This is the "Q4" path: client speaks Anthropic, upstream speaks
// Anthropic (e.g. anthropic provider, or minimax's /anthropic
// compatible endpoint), no protocol conversion required.
//
// Track C C5 (2026-06-21): when pc is non-nil, every byte forwarded to
// the client is also appended to the capturer buffer so the gateway can
// replay the full SSE response from pending store after a client
// disconnect. The capturer is finalized before return so the caller can
// snapshot and persist it (see cmd/gateway/main.go's saveCapturedPending
// helper). nil pc is fine (legacy / non-session requests).
func StreamAnthropicPassthrough(
	w http.ResponseWriter,
	resp *http.Response,
	clientModel, outboundModel, requestID string,
	capture *audit.StreamCapture,
	pc *pendingCapturer,
) (outcome routing.StreamOutcome) {
	//nolint:errcheck // best-effort close
	defer resp.Body.Close()
	// Top-level panic recovery. Mirrors StreamChatWithPendingCapture
	// so a panic during streaming (e.g. JSON parse failure, write to
	// a closed connection) does not skip the deferred capturer
	// finalize and lose the pending-store entry entirely.
	defer func() {
		if r := recover(); r != nil {
			slog.Error("anthropic passthrough panic", "panic", r, "stack", string(debug.Stack()))
			if capture != nil {
				capture.MarkInterruptedWithReason("stream_panic")
			}
			outcome.Interrupted = true
			outcome.Reason = "stream_panic"
			if pc != nil {
				pc.markInterrupted("stream_panic")
			}
		}
		// Best-effort capturer finalise. If the stream completed
		// normally, the capturer holds the full body ready for replay
		// via GET /v1/sessions/{id}/pending-response. If terminated
		// abnormally, the capturer still holds whatever was captured
		// so the admin API can inspect (status=failed).
		if pc != nil {
			pc.finalize(outcome)
		}
	}()

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return routing.StreamOutcome{Interrupted: true, Reason: "no_flusher"}
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	if requestID != "" {
		w.Header().Set("X-Request-Id", requestID)
	}
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	reader := bufio.NewReaderSize(resp.Body, anthropicSSEBufSize)

	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			if err == io.EOF {
				break
			}
			outcome.Interrupted = true
			outcome.Reason = "read_error"
			if capture != nil {
				capture.MarkInterruptedWithReason("read_error")
			}
			return outcome
		}
		if _, werr := w.Write([]byte(line)); werr != nil {
			outcome.Interrupted = true
			outcome.Reason = "client_disconnected"
			if capture != nil {
				capture.MarkInterruptedWithReason("client_disconnected")
			}
			return outcome
		}
		// Track C C5 (2026-06-21): record every line into the capturer
		// BEFORE the side-channel audit observer runs so a panic in
		// observeAnthropicPayload does not skip the buffer write.
		// Anthropic SSE events span 2-3 lines each (`event:` + `data:`
		// + blank line); storing the whole line is correct for replay.
		if pc != nil {
			pc.append(line)
		}
		if capture != nil && strings.HasPrefix(line, "data: ") {
			payload := strings.TrimPrefix(line, "data: ")
			payload = strings.TrimSpace(payload)
			observeAnthropicPayload(capture, payload, clientModel, outboundModel)
		}
		if line == "\n" {
			flusher.Flush()
		}
	}
	flusher.Flush()
	return outcome
}

// observeAnthropicPayload inspects a single Anthropic SSE data payload
// and updates the side-channel audit capture accordingly. It handles
// the three event types that carry state worth recording:
//
//   - message_start: contains usage.input_tokens (initial value), plus
//     cache_creation_input_tokens and cache_read_input_tokens for
//     prompt-cached prompts
//   - message_delta:  contains usage.output_tokens (cumulative final),
//     plus the FINAL cache_read_input_tokens tally (Anthropic emits the
//     cache_read value on message_delta, not on message_start, so the
//     stream capture would otherwise stay nil even though upstream
//     charged the request for cache hits).
//   - content_block_start with type=thinking: marks the response as
//     containing reasoning, increments the thinking-block counter
//   - any event with a "message.model" field: triggers model-mismatch
//     check against the requested model
//
// 2026-06-30: the message_start and message_delta branches now also
// lift cache_creation_input_tokens / cache_read_input_tokens into the
// capture. Before this fix, request_logs.cache_read_tokens and
// cache_write_tokens stayed NULL for every Anthropic cached-prompt
// call, hiding the cache discount from billing rollups.
func observeAnthropicPayload(c *audit.StreamCapture, payload, clientModel, outboundModel string) {
	if payload == "" || payload == "[DONE]" {
		return
	}
	var v struct {
		Type    string `json:"type"`
		Message *struct {
			Model string `json:"model"`
			Usage struct {
				InputTokens              *int `json:"input_tokens"`
				OutputTokens             *int `json:"output_tokens"`
				CacheReadInputTokens     *int `json:"cache_read_input_tokens"`
				CacheCreationInputTokens *int `json:"cache_creation_input_tokens"`
			} `json:"usage"`
		} `json:"message"`
		Usage *struct {
			OutputTokens             *int `json:"output_tokens"`
			CacheReadInputTokens     *int `json:"cache_read_input_tokens"`
			CacheCreationInputTokens *int `json:"cache_creation_input_tokens"`
		} `json:"usage"`
		Index        *int `json:"index"`
		ContentBlock *struct {
			Type string `json:"type"`
		} `json:"content_block"`
	}
	if err := json.Unmarshal([]byte(payload), &v); err != nil {
		return
	}
	switch v.Type {
	case "message_start":
		if v.Message != nil {
			if v.Message.Usage.InputTokens != nil {
				pt := *v.Message.Usage.InputTokens
				c.InputTokens = &pt
			}
			// message_start may also carry the initial cache counts when
			// the prompt was served from cache. Forward to the capture
			// so the WAL can persist cache_read_tokens / cache_write_tokens
			// even if message_delta is never reached (e.g. interrupted
			// stream before the delta fires).
			if v.Message.Usage.CacheReadInputTokens != nil {
				cr := *v.Message.Usage.CacheReadInputTokens
				c.CacheReadTokens = &cr
			}
			if v.Message.Usage.CacheCreationInputTokens != nil {
				cw := *v.Message.Usage.CacheCreationInputTokens
				c.CacheWriteTokens = &cw
			}
			if v.Message.Model != "" {
				checkAnthropicModelMismatch(c, clientModel, outboundModel, v.Message.Model)
			}
		}
	case "message_delta":
		if v.Usage != nil {
			if v.Usage.OutputTokens != nil {
				ot := *v.Usage.OutputTokens
				c.OutputTokens = &ot
			}
			// Anthropic emits the cumulative cache_read count on
			// message_delta, not on message_start. Promote it here
			// (overwriting the message_start value) so the capture
			// ends with the final billing-relevant number.
			if v.Usage.CacheReadInputTokens != nil {
				cr := *v.Usage.CacheReadInputTokens
				c.CacheReadTokens = &cr
			}
			if v.Usage.CacheCreationInputTokens != nil {
				cw := *v.Usage.CacheCreationInputTokens
				c.CacheWriteTokens = &cw
			}
		}
	case "message_stop":
		c.MarkDone()
	case "content_block_start":
		if v.ContentBlock != nil && v.ContentBlock.Type == "thinking" {
			c.HasThinking = true
			c.ThinkingBlocksN++
		}
	case "error":
		c.MarkStreamError()
	}
}

// checkAnthropicModelMismatch sets the capture's ModelMismatch flag
// when the upstream response model name does not case-insensitively
// match the clientModel (or outboundModel fallback). This is a
// side-channel detection — most upstreams will report a different
// model name in the response message_start than what the client
// asked for (e.g. "claude-3-5-sonnet-20241022" vs "claude-3-5-sonnet"),
// so we only flag a mismatch when the names diverge in a way the
// caller likely cares about.
func checkAnthropicModelMismatch(c *audit.StreamCapture, clientModel, outboundModel, respModel string) {
	want := clientModel
	if want == "" {
		want = outboundModel
	}
	if want == "" || respModel == "" {
		return
	}
	if !strings.EqualFold(want, respModel) {
		c.ModelMismatch = true
	}
}
