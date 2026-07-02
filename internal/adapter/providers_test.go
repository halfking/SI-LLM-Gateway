package adapter

import (
	"testing"

	"github.com/kaixuan/llm-gateway-go/internal/ir"
)

// ─── DeepSeek ──────────────────────────────────────────────────────────────

func TestDeepSeek_AdaptRequest_ClampsMaxTokens(t *testing.T) {
	d := NewDeepSeek()
	mt := 20000
	req := &ir.InternalRequest{MaxTokens: mt}
	out, err := d.AdaptRequest(req)
	if err != nil {
		t.Fatalf("AdaptRequest: %v", err)
	}
	if out.MaxTokens != 8192 {
		t.Errorf("MaxTokens = %d, want 8192 (clamped)", out.MaxTokens)
	}
}

func TestDeepSeek_AdaptRequest_NoClampWhenWithinLimit(t *testing.T) {
	d := NewDeepSeek()
	req := &ir.InternalRequest{MaxTokens: 4000}
	out, _ := d.AdaptRequest(req)
	if out.MaxTokens != 4000 {
		t.Errorf("MaxTokens = %d, want 4000 (unchanged)", out.MaxTokens)
	}
}

// ─── Qwen ──────────────────────────────────────────────────────────────────

func TestQwen_AdaptRequest_DropsTopPWhenTemperatureSet(t *testing.T) {
	q := NewQwen()
	temp := 0.7
	topP := 0.9
	req := &ir.InternalRequest{Temperature: &temp, TopP: &topP}
	out, err := q.AdaptRequest(req)
	if err != nil {
		t.Fatalf("AdaptRequest: %v", err)
	}
	if out.TopP != nil {
		t.Error("expected TopP to be nil (DashScope rejects temp+top_p together)")
	}
	if out.Temperature == nil || *out.Temperature != 0.7 {
		t.Error("expected Temperature to be preserved")
	}
}

func TestQwen_AdaptRequest_KeepsTopPWhenNoTemperature(t *testing.T) {
	q := NewQwen()
	topP := 0.9
	req := &ir.InternalRequest{TopP: &topP}
	out, _ := q.AdaptRequest(req)
	if out.TopP == nil {
		t.Error("expected TopP to be kept when Temperature is not set")
	}
}

// ─── Doubao ────────────────────────────────────────────────────────────────

func TestDoubao_AdaptRequest_ClampsTemperatureHigh(t *testing.T) {
	d := NewDoubao()
	highTemp := 2.0
	req := &ir.InternalRequest{Temperature: &highTemp}
	out, err := d.AdaptRequest(req)
	if err != nil {
		t.Fatalf("AdaptRequest: %v", err)
	}
	if out.Temperature == nil {
		t.Fatal("expected Temperature to be non-nil")
	}
	if *out.Temperature != 1.0 {
		t.Errorf("Temperature = %f, want 1.0 (clamped to [0,1])", *out.Temperature)
	}
}

func TestDoubao_AdaptRequest_ClampsTemperatureNegative(t *testing.T) {
	d := NewDoubao()
	negTemp := -0.5
	req := &ir.InternalRequest{Temperature: &negTemp}
	out, _ := d.AdaptRequest(req)
	if *out.Temperature != 0.0 {
		t.Errorf("Temperature = %f, want 0.0 (clamped to [0,1])", *out.Temperature)
	}
}

func TestDoubao_AdaptRequest_ClampsMaxTokens(t *testing.T) {
	d := NewDoubao()
	req := &ir.InternalRequest{MaxTokens: 8000}
	out, _ := d.AdaptRequest(req)
	if out.MaxTokens != 4096 {
		t.Errorf("MaxTokens = %d, want 4096 (Doubao limit)", out.MaxTokens)
	}
}

// ─── Moonshot ──────────────────────────────────────────────────────────────

func TestMoonshot_AdaptRequest_SetsTargetProvider(t *testing.T) {
	m := NewMoonshot()
	req := &ir.InternalRequest{Model: "moonshot-v1-8k"}
	out, _ := m.AdaptRequest(req)
	if out.TargetProvider != "moonshot" {
		t.Errorf("TargetProvider = %q, want 'moonshot'", out.TargetProvider)
	}
}

// ─── Zhipu ─────────────────────────────────────────────────────────────────

func TestZhipu_AdaptRequest_ClampsMaxTokens(t *testing.T) {
	z := NewZhipu()
	req := &ir.InternalRequest{MaxTokens: 30000}
	out, _ := z.AdaptRequest(req)
	if out.MaxTokens != 8192 {
		t.Errorf("MaxTokens = %d, want 8192 (GLM-4 limit)", out.MaxTokens)
	}
}

// ─── Standard adapters don't mutate ────────────────────────────────────────

func TestStandardOpenAI_AdaptRequest_NoMutation(t *testing.T) {
	s := StandardOpenAI{}
	original := &ir.InternalRequest{MaxTokens: 999999}
	out, err := s.AdaptRequest(original)
	if err != nil {
		t.Fatalf("AdaptRequest: %v", err)
	}
	// StandardOpenAI should NOT clamp — it has no provider-specific limit.
	if out.MaxTokens != 999999 {
		t.Errorf("StandardOpenAI should not clamp MaxTokens, got %d", out.MaxTokens)
	}
}

// ─── clampMaxTokens helper ─────────────────────────────────────────────────

func TestClampMaxTokens(t *testing.T) {
	cases := []struct {
		name    string
		input   int
		max     int
		want    int
		changed bool
	}{
		{"within limit", 4000, 8192, 4000, false},
		{"exceeds limit", 20000, 8192, 8192, true},
		{"zero max_tokens", 0, 8192, 0, false},
		{"exact limit", 8192, 8192, 8192, false},
		{"zero max_val (disabled)", 5000, 0, 5000, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			req := &ir.InternalRequest{MaxTokens: c.input}
			out := clampMaxTokens(req, c.max)
			if out.MaxTokens != c.want {
				t.Errorf("got %d, want %d", out.MaxTokens, c.want)
			}
		})
	}
}
