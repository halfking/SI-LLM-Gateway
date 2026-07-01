package attachments

import (
	"testing"
)

func TestHasAttachments(t *testing.T) {
	cases := []struct {
		name string
		body string
		want bool
	}{
		{"plain text", `{"messages":[{"role":"user","content":"hi"}]}`, false},
		{"openai image_url", `{"messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:image/png;base64,xxx"}}]}]}`, true},
		{"anthropic image", `{"messages":[{"role":"user","content":[{"type":"image","source":{"type":"base64","data":"xxx"}}]}]}`, true},
		{"anthropic spaced", `{"messages":[{"role":"user","content":[{"type": "image"}]}]}`, true},
		{"data url only", `{"messages":[{"content":"data:image/jpeg;base64,abc"}]}`, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := HasAttachments([]byte(c.body)); got != c.want {
				t.Errorf("HasAttachments = %v, want %v", got, c.want)
			}
		})
	}
}

// TestManagerDisabledIsObserver verifies that when the manager is
// disabled, ArchiveAttachments is a no-op (the body must never be
// touched, which is the contract the relay handler relies on).
func TestManagerDisabledIsObserver(t *testing.T) {
	m := &Manager{enabled: false}
	body := []byte(`{"messages":[{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:image/png;base64,xxx"}}]}]}`)
	n, err := m.ArchiveAttachments(nil, body, "req-1", "default")
	if err != nil {
		t.Fatalf("disabled manager returned error: %v", err)
	}
	if n != 0 {
		t.Errorf("disabled manager archived %d, want 0", n)
	}
}

func TestSafeExt(t *testing.T) {
	cases := map[string]string{
		"image/png":  "image.png",
		"image/jpeg": "image.jpeg",
		"image/gif":  "image.gif",
		"":           "attachment.bin",
		"weird":      "attachment.bin",
	}
	for in, want := range cases {
		if got := safeExt(in); got != want {
			t.Errorf("safeExt(%q) = %q, want %q", in, got, want)
		}
	}
}
