package attachments

import (
	"context"
	"encoding/base64"
	"path/filepath"
	"testing"
)

// TestArchiveFileWrittenWithoutDB verifies that archival fails gracefully
// when no DB pool is configured. After 2026-07-02 fix, save() returns an
// error when pool == nil (instead of silent no-op) to avoid phantom
// "has_attachments=t" rows with no actual DB records. The file is written
// then removed on save failure.
func TestArchiveFileWrittenWithoutDB(t *testing.T) {
	tmp := t.TempDir()
	m := &Manager{
		storagePath: tmp,
		enabled:     true,
		maxSizeMB:   10,
		// pool intentionally nil → save() returns error
	}

	// 1x1 red PNG.
	png, err := base64.StdEncoding.DecodeString(
		"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
	if err != nil {
		t.Fatal(err)
	}
	b64 := base64.StdEncoding.EncodeToString(png)

	// OpenAI image_url shape.
	body := []byte(`{
        "model":"gpt-4o",
        "messages":[{
            "role":"user",
            "content":[
                {"type":"text","text":"look"},
                {"type":"image_url","image_url":{"url":"data:image/png;base64,` + b64 + `"}}
            ]
        }]
    }`)

	n, err := m.ArchiveAttachments(context.Background(), body, "req-test-1", "default")
	if err != nil {
		t.Fatalf("ArchiveAttachments: %v", err)
	}
	// After 2026-07-02 fix: DB save failure causes file removal, count=0
	if n != 0 {
		t.Fatalf("archived %d, want 0 (no DB pool)", n)
	}

	// No files should remain (cleaned up on save failure)
	matches, err := filepath.Glob(filepath.Join(tmp, "*", "*", "*", "*.png"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 0 {
		t.Fatalf("expected 0 archived files (no DB), got %d: %v", len(matches), matches)
	}
}

// TestArchiveAnthropicImageBlock verifies the Anthropic content-block
// shape (type=image, source.type=base64) is archived — this is the
// format /v1/messages clients send and the one the user reported as
// "lost".
func TestArchiveAnthropicImageBlock(t *testing.T) {
	tmp := t.TempDir()
	m := &Manager{storagePath: tmp, enabled: true, maxSizeMB: 10}

	png, _ := base64.StdEncoding.DecodeString(
		"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
	b64 := base64.StdEncoding.EncodeToString(png)

	body := []byte(`{
        "model":"claude-3-5-sonnet",
        "messages":[{
            "role":"user",
            "content":[
                {"type":"image","source":{"type":"base64","media_type":"image/png","data":"` + b64 + `"}}
            ]
        }]
    }`)

	n, err := m.ArchiveAttachments(context.Background(), body, "req-anth-1", "default")
	if err != nil {
		t.Fatalf("ArchiveAttachments: %v", err)
	}
	// After 2026-07-02 fix: no DB pool → count=0
	if n != 0 {
		t.Fatalf("archived %d, want 0 (no DB pool)", n)
	}
	// No files should remain (cleaned up on save failure)
	matches, _ := filepath.Glob(filepath.Join(tmp, "*", "*", "*", "*.png"))
	if len(matches) != 0 {
		t.Fatalf("expected 0 archived files (no DB), got %d", len(matches))
	}
}

// TestArchiveSkipsExternalURL ensures http(s) URLs are not fetched and
// not archived (we keep them as references only).
func TestArchiveSkipsExternalURL(t *testing.T) {
	tmp := t.TempDir()
	m := &Manager{storagePath: tmp, enabled: true, maxSizeMB: 10}

	body := []byte(`{
        "messages":[{
            "role":"user",
            "content":[
                {"type":"image_url","image_url":{"url":"https://example.com/cat.png"}}
            ]
        }]
    }`)
	n, _ := m.ArchiveAttachments(context.Background(), body, "req-url-1", "default")
	if n != 0 {
		t.Errorf("archived %d external-url images, want 0", n)
	}
}
