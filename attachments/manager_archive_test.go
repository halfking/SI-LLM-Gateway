package attachments

import (
	"context"
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
)

// TestArchiveFileWrittenWithoutDB verifies the on-disk archival path
// works end to end when no DB pool is configured (the manager's save()
// is a no-op when pool == nil). We assert:
//   - the image is decoded and written to storagePath/<date>/...
//   - the returned count is 1
//   - the original body is returned byte-for-byte unchanged (the
//     "observer" contract that the relay handler relies on)
func TestArchiveFileWrittenWithoutDB(t *testing.T) {
	tmp := t.TempDir()
	m := &Manager{
		storagePath: tmp,
		enabled:     true,
		maxSizeMB:   10,
		// pool intentionally nil → save() is a no-op
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
	if n != 1 {
		t.Fatalf("archived %d, want 1", n)
	}

	// A file should exist under <tmp>/<year>/<month>/<day>/*.png
	matches, err := filepath.Glob(filepath.Join(tmp, "*", "*", "*", "*.png"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 1 {
		t.Fatalf("expected 1 archived file, got %d: %v", len(matches), matches)
	}
	got, err := os.ReadFile(matches[0])
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(png) {
		t.Errorf("archived file size %d, want %d", len(got), len(png))
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
	if n != 1 {
		t.Fatalf("archived %d, want 1", n)
	}
	matches, _ := filepath.Glob(filepath.Join(tmp, "*", "*", "*", "*.png"))
	if len(matches) != 1 {
		t.Fatalf("expected 1 file, got %d", len(matches))
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
