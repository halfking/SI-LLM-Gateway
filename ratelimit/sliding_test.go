package ratelimit

import "testing"

func TestSlidingWindowLimiter_RPM_Allowed(t *testing.T) {
	rl := NewSlidingWindowLimiter()
	limit := 5

	for i := 0; i < limit; i++ {
		if !rl.CheckRPM(1, limit) {
			t.Fatalf("request %d should be allowed", i+1)
		}
	}
	if rl.CheckRPM(1, limit) {
		t.Fatal("request beyond limit should be denied")
	}
}

func TestSlidingWindowLimiter_RPM_NoLimit(t *testing.T) {
	rl := NewSlidingWindowLimiter()
	if !rl.CheckRPM(1, 0) {
		t.Fatal("limit=0 should allow all")
	}
	if !rl.CheckRPM(1, -1) {
		t.Fatal("limit<0 should allow all")
	}
}

func TestSlidingWindowLimiter_RPM_DifferentKeys(t *testing.T) {
	rl := NewSlidingWindowLimiter()
	limit := 2

	if !rl.CheckRPM(1, limit) {
		t.Fatal("key 1 first request should be allowed")
	}
	if !rl.CheckRPM(1, limit) {
		t.Fatal("key 1 second request should be allowed")
	}
	if rl.CheckRPM(1, limit) {
		t.Fatal("key 1 third request should be denied")
	}
	if !rl.CheckRPM(2, limit) {
		t.Fatal("key 2 first request should be allowed (separate counter)")
	}
}

func TestSlidingWindowLimiter_RPMStatus(t *testing.T) {
	rl := NewSlidingWindowLimiter()
	limit := 10

	for i := 0; i < 7; i++ {
		rl.CheckRPM(1, limit)
	}

	used, remaining := rl.RPMStatus(1, limit)
	if used != 7 {
		t.Errorf("expected used=7, got %d", used)
	}
	if remaining != 3 {
		t.Errorf("expected remaining=3, got %d", remaining)
	}
}

func TestSlidingWindowLimiter_TPM_Allowed(t *testing.T) {
	rl := NewSlidingWindowLimiter()
	limit := 1000

	if !rl.CheckTPM(1, 500, limit) {
		t.Fatal("500 tokens should be allowed under 1000 limit")
	}
	if !rl.CheckTPM(1, 400, limit) {
		t.Fatal("400 more tokens (total 900) should be allowed")
	}
	if rl.CheckTPM(1, 200, limit) {
		t.Fatal("200 more tokens (total 1100) should exceed 1000 limit")
	}
}

func TestSlidingWindowLimiter_TPM_NoLimit(t *testing.T) {
	rl := NewSlidingWindowLimiter()
	if !rl.CheckTPM(1, 99999, 0) {
		t.Fatal("limit=0 should allow all tokens")
	}
}

func TestSlidingWindowLimiter_TPM_DifferentKeys(t *testing.T) {
	rl := NewSlidingWindowLimiter()
	limit := 100

	if !rl.CheckTPM(1, 100, limit) {
		t.Fatal("key 1 100 tokens should be allowed")
	}
	if rl.CheckTPM(1, 1, limit) {
		t.Fatal("key 1 +1 token should be denied")
	}
	if !rl.CheckTPM(2, 100, limit) {
		t.Fatal("key 2 100 tokens should be allowed (separate counter)")
	}
}

func TestSlidingWindowLimiter_Stop(t *testing.T) {
	rl := NewSlidingWindowLimiter()
	rl.CheckRPM(1, 10)
	rl.CheckTPM(1, 500, 1000)
	rl.Stop()

	used, _ := rl.RPMStatus(1, 10)
	if used != 0 {
		t.Errorf("after Stop(), RPM status should be 0, got %d", used)
	}
}
