package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestKeyVerifier_Disabled(t *testing.T) {
	kv := NewKeyVerifier("", "")
	if kv.Enabled() {
		t.Fatal("empty endpoint+key should be disabled")
	}
	_, err := kv.Verify(context.Background(), "sk-test")
	if err == nil {
		t.Fatal("disabled verifier should return error")
	}
}

func TestKeyVerifier_Cache(t *testing.T) {
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		if r.URL.Path == "/api/keys/verify" {
			w.Header().Set("Content-Type", "application/json")
			w.Write([]byte(`{"id":1,"tenant_id":"default","application_id":1,"application_code":"default","rate_limit_rpm":60,"budget_usd":100.0}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer server.Close()

	kv := NewKeyVerifier(server.URL, "test-admin-key")
	kv.httpClient = server.Client()

	info1, err := kv.Verify(context.Background(), "sk-testkey123")
	if err != nil {
		t.Fatalf("first verify failed: %v", err)
	}
	if info1.ID != 1 {
		t.Errorf("expected id=1, got %d", info1.ID)
	}
	if callCount != 1 {
		t.Errorf("expected 1 RPC call, got %d", callCount)
	}

	info2, err := kv.Verify(context.Background(), "sk-testkey123")
	if err != nil {
		t.Fatalf("cached verify failed: %v", err)
	}
	if info2.ID != 1 {
		t.Errorf("expected cached id=1, got %d", info2.ID)
	}
	if callCount != 1 {
		t.Errorf("expected still 1 RPC call (cached), got %d", callCount)
	}
}

func TestKeyVerifier_InvalidKey(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"detail":"Invalid or expired API key"}`))
	}))
	defer server.Close()

	kv := NewKeyVerifier(server.URL, "test-admin-key")
	kv.httpClient = server.Client()

	_, err := kv.Verify(context.Background(), "sk-badkey")
	if err == nil {
		t.Fatal("expected error for invalid key")
	}
	if _, ok := err.(*InvalidKeyError); !ok {
		t.Errorf("expected InvalidKeyError, got %T: %v", err, err)
	}
}

func TestKeyVerifier_ServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte(`{"detail":"internal error"}`))
	}))
	defer server.Close()

	kv := NewKeyVerifier(server.URL, "test-admin-key")
	kv.httpClient = server.Client()

	_, err := kv.Verify(context.Background(), "sk-testkey")
	if err == nil {
		t.Fatal("expected error for server error")
	}
	if _, ok := err.(*InvalidKeyError); ok {
		t.Error("500 should not be InvalidKeyError")
	}
}

func TestKeyVerifier_DifferentKeys(t *testing.T) {
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"id":` + string(rune('0'+callCount)) + `,"tenant_id":"default","application_id":1,"application_code":"default"}`))
	}))
	defer server.Close()

	kv := NewKeyVerifier(server.URL, "test-admin-key")
	kv.httpClient = server.Client()

	info1, _ := kv.Verify(context.Background(), "sk-key-a")
	info2, _ := kv.Verify(context.Background(), "sk-key-b")
	if info1.ID == info2.ID {
		t.Error("different keys should get different results")
	}
	if callCount != 2 {
		t.Errorf("expected 2 RPC calls for different keys, got %d", callCount)
	}
}
