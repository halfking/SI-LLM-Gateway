package headroom

import (
	"testing"
)

func TestSimHash(t *testing.T) {
	tests := []struct {
		name     string
		text     string
		wantZero bool
	}{
		{
			name:     "empty string",
			text:     "",
			wantZero: true,
		},
		{
			name:     "simple text",
			text:     "hello world",
			wantZero: false,
		},
		{
			name:     "longer text",
			text:     "The quick brown fox jumps over the lazy dog",
			wantZero: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hash := SimHash(tt.text)
			if tt.wantZero && hash != 0 {
				t.Errorf("SimHash() = %d, want 0", hash)
			}
			if !tt.wantZero && hash == 0 {
				t.Errorf("SimHash() = 0, want non-zero")
			}
		})
	}
}

func TestSimHashSimilarity(t *testing.T) {
	text1 := "The quick brown fox jumps over the lazy dog"
	text2 := "The quick brown fox jumps over the lazy cat"
	text3 := "Completely different text about something else"

	hash1 := SimHash(text1)
	hash2 := SimHash(text2)
	hash3 := SimHash(text3)

	dist12 := HammingDistance(hash1, hash2)
	dist13 := HammingDistance(hash1, hash3)

	// Similar texts should have smaller Hamming distance
	if dist12 >= dist13 {
		t.Errorf("Expected similar texts to have smaller distance: dist(%q, %q)=%d >= dist(%q, %q)=%d",
			text1, text2, dist12, text1, text3, dist13)
	}
}

func TestSimHashDeterministic(t *testing.T) {
	text := "deterministic test string"
	
	hash1 := SimHash(text)
	hash2 := SimHash(text)
	
	if hash1 != hash2 {
		t.Errorf("SimHash not deterministic: %d != %d", hash1, hash2)
	}
}

func TestHammingDistance(t *testing.T) {
	tests := []struct {
		name string
		a    uint64
		b    uint64
		want int
	}{
		{
			name: "identical",
			a:    0b1010101010101010,
			b:    0b1010101010101010,
			want: 0,
		},
		{
			name: "single bit difference",
			a:    0b1010101010101010,
			b:    0b1010101010101011,
			want: 1,
		},
		{
			name: "all bits different",
			a:    0b1111111111111111,
			b:    0b0000000000000000,
			want: 16,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := HammingDistance(tt.a, tt.b)
			if got != tt.want {
				t.Errorf("HammingDistance(%b, %b) = %d, want %d", tt.a, tt.b, got, tt.want)
			}
		})
	}
}

func TestCountUniqueSimHashes(t *testing.T) {
	tests := []struct {
		name      string
		items     []string
		threshold int
		want      int
	}{
		{
			name:      "empty",
			items:     []string{},
			threshold: 3,
			want:      0,
		},
		{
			name:      "single item",
			items:     []string{"hello"},
			threshold: 3,
			want:      1,
		},
		{
			name: "all duplicates",
			items: []string{
				"hello world",
				"hello world",
				"hello world",
			},
			threshold: 3,
			want:      1,
		},
		{
			name: "near duplicates",
			items: []string{
				"The quick brown fox",
				"The quick brown fox!",
				"The quick brown cat",
			},
			threshold: 5,
			want:      3, // All considered unique with threshold 5
		},
		{
			name: "all unique",
			items: []string{
				"Completely different text A",
				"Something totally unique B",
				"Another distinct string C",
			},
			threshold: 3,
			want:      3,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CountUniqueSimHashes(tt.items, tt.threshold)
			if got != tt.want {
				t.Errorf("CountUniqueSimHashes() = %d, want %d", got, tt.want)
			}
		})
	}
}

func TestNormalizeText(t *testing.T) {
	tests := []struct {
		name string
		text string
		want string
	}{
		{
			name: "uppercase to lowercase",
			text: "HELLO WORLD",
			want: "hello world",
		},
		{
			name: "collapse whitespace",
			text: "hello    world   test",
			want: "hello world test",
		},
		{
			name: "mixed case and whitespace",
			text: "  Hello   WORLD  ",
			want: "hello world",
		},
		{
			name: "tabs and newlines",
			text: "hello\tworld\ntest",
			want: "hello world test",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := NormalizeText(tt.text)
			if got != tt.want {
				t.Errorf("NormalizeText() = %q, want %q", got, tt.want)
			}
		})
	}
}

// Benchmark SimHash performance
func BenchmarkSimHash(b *testing.B) {
	text := "The quick brown fox jumps over the lazy dog. This is a longer text to benchmark the SimHash algorithm performance."
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		SimHash(text)
	}
}

func BenchmarkCountUniqueSimHashes(b *testing.B) {
	items := make([]string, 100)
	for i := 0; i < 100; i++ {
		items[i] = "Item number " + string(rune('A'+i%26)) + " with some text"
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		CountUniqueSimHashes(items, 3)
	}
}
