// Package relay provides content-based deduplication for chat completion requests.
// When a client retries the same request with a different request ID (e.g., after
// network failure), this cache detects the duplicate by content fingerprint and
// replays the cached response, avoiding redundant LLM calls.
//
// Design: 2026-06-29 Content Deduplication
//
// See also: pending/ for the storage layer, relay/idempotent.go for request-ID
// based deduplication.
package relay

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/kaixuan/llm-gateway-go/pending"
)

// ContentDedupCache detects duplicate requests based on message content
// rather than request ID. This catches network retries where the client
// generates a new request ID but sends the same messages.
type ContentDedupCache struct {
	store  *pending.Store
	window time.Duration // Only check duplicates within this time window
	depth  int           // Number of recent messages to include in fingerprint
}

// NewContentDedupCache creates a content deduplication cache.
//
// Parameters:
//   - store: pending.Store for reading/writing cached responses
//   - window: time window for dedup (e.g., 10 minutes). Older cache entries are ignored.
//   - depth: number of recent messages to include in fingerprint (0 = last message only, -1 = all)
func NewContentDedupCache(store *pending.Store, window time.Duration, depth int) *ContentDedupCache {
	if depth == 0 {
		depth = 3 // default: last 3 messages
	}
	if window == 0 {
		window = 10 * time.Minute // default: 10 minutes
	}
	return &ContentDedupCache{
		store:  store,
		window: window,
		depth:  depth,
	}
}

// Message represents a simplified chat message for fingerprinting.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ComputeFingerprint calculates a SHA-256 hash of the request content.
// The fingerprint includes:
//   - Last N messages (role + content)
//   - Model name
//   - Stream flag
//
// This allows detecting semantic duplicates even when request IDs differ.
func (c *ContentDedupCache) ComputeFingerprint(messages []Message, model string, stream bool) string {
	var buf bytes.Buffer

	// Include only the last N messages to balance uniqueness and hit rate
	start := len(messages) - c.depth
	if start < 0 {
		start = 0
	}

	for _, msg := range messages[start:] {
		buf.WriteString(msg.Role)
		buf.WriteString(":")
		// Truncate very long messages to avoid DoS via huge hashes
		content := msg.Content
		if len(content) > 10000 {
			content = content[:10000]
		}
		buf.WriteString(content)
		buf.WriteString("|")
	}

	buf.WriteString("model=")
	buf.WriteString(model)
	buf.WriteString("|stream=")
	buf.WriteString(strconv.FormatBool(stream))

	hash := sha256.Sum256(buf.Bytes())
	return hex.EncodeToString(hash[:])
}

// truncateHash safely truncates a hash for logging (max 16 chars)
func truncateHash(hash string) string {
	if len(hash) > 16 {
		return hash[:16]
	}
	return hash
}

// CheckAndReplay checks if a cached response exists for the given content
// fingerprint and replays it if found. Returns (true, nil) if replayed,
// (false, nil) if cache miss, or (false, err) on error.
//
// The response is written directly to http.ResponseWriter with headers:
//   - X-Gw-Content-Replay: true
//   - X-Gw-Cache-Hit: content-hash
//   - X-Gw-Cached-At: timestamp
func (c *ContentDedupCache) CheckAndReplay(
	ctx context.Context,
	sessionID string,
	contentHash string,
	w http.ResponseWriter,
) (replayed bool, err error) {
	if c == nil || c.store == nil {
		return false, nil
	}

	// Construct cache key: session:hash
	// Use contentHash as pseudo-requestID since pending.Store expects (sessionID, requestID)
	entry, found, err := c.store.Get(ctx, sessionID, contentHash)
	if err != nil {
		slog.Debug("content dedup: store get failed", "session_id", sessionID, "hash", truncateHash(contentHash), "error", err)
		return false, nil // Treat errors as cache miss
	}

	if !found || entry == nil || entry.Status != pending.StatusCompleted {
		return false, nil // Cache miss or in-progress entry
	}

	// Check if entry is within time window
	createdAt := time.Unix(entry.CreatedAt, 0)
	if time.Since(createdAt) > c.window {
		slog.Debug("content dedup: cache entry too old", "session_id", sessionID, "hash", truncateHash(contentHash), "age", time.Since(createdAt))
		return false, nil
	}

	// Cache hit! Replay the response
	w.Header().Set("X-Gw-Content-Replay", "true")
	w.Header().Set("X-Gw-Cache-Hit", "content-hash")
	w.Header().Set("X-Gw-Cached-At", createdAt.Format(time.RFC3339))
	w.Header().Set("X-Gw-Cache-Key", truncateHash(contentHash)) // Truncated hash for debugging

	if entry.ContentType != "" {
		w.Header().Set("Content-Type", entry.ContentType)
	} else {
		w.Header().Set("Content-Type", "text/event-stream")
	}

	w.WriteHeader(http.StatusOK)
	_, err = w.Write([]byte(entry.Body))
	if err != nil {
		slog.Warn("content dedup: failed to write cached response", "error", err)
		return true, err // Already wrote headers, can't recover
	}

	slog.Info("content dedup: cache hit", "session_id", sessionID, "hash", truncateHash(contentHash), "age", time.Since(createdAt))
	return true, nil
}

// Store saves a response to the content dedup cache for future replay.
func (c *ContentDedupCache) Store(
	ctx context.Context,
	sessionID string,
	contentHash string,
	responseBody string,
	contentType string,
) error {
	if c == nil || c.store == nil {
		return nil
	}

	// Use contentHash as pseudo-requestID
	entry := &pending.Response{
		SessionID:   sessionID,
		RequestID:   contentHash, // Use hash as pseudo request ID
		Body:        responseBody,
		ContentType: contentType,
		Status:      pending.StatusCompleted,
		CreatedAt:   time.Now().Unix(),
		IsStream:    contentType == "text/event-stream",
	}

	err := c.store.Save(ctx, entry)
	if err != nil {
		slog.Warn("content dedup: failed to store cache entry", "session_id", sessionID, "hash", truncateHash(contentHash), "error", err)
		return err
	}

	slog.Debug("content dedup: stored cache entry", "session_id", sessionID, "hash", truncateHash(contentHash), "size", len(responseBody))
	return nil
}

// ParseMessagesForFingerprint extracts messages from a request body for fingerprinting.
// This is a helper to avoid duplicating JSON parsing logic.
func ParseMessagesForFingerprint(bodyBytes []byte) (messages []Message, model string, stream bool, err error) {
	var req struct {
		Messages []Message `json:"messages"`
		Model    string    `json:"model"`
		Stream   bool      `json:"stream"`
	}

	if err := json.Unmarshal(bodyBytes, &req); err != nil {
		return nil, "", false, fmt.Errorf("failed to parse request body: %w", err)
	}

	return req.Messages, req.Model, req.Stream, nil
}
