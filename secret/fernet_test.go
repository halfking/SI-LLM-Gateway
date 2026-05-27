package secret

import "testing"

func TestDecryptFernetPythonToken(t *testing.T) {
	key, err := FernetKeyFromSecret("", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
	if err != nil {
		t.Fatalf("key: %v", err)
	}
	got, err := DecryptFernet([]byte("gAAAAABqFnoxaiaW-xfzoiIZjE-7WrhwY6GAe241ir6CzS-ywsLI1gTe8QdKvN1mHgdX6WieRaY6c0ErYbdXz-6-FIwqjT66jA=="), key)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if got != "sk-test-secret" {
		t.Fatalf("expected sk-test-secret, got %q", got)
	}
}

func TestFernetKeyDerivedFromSecret(t *testing.T) {
	key, err := FernetKeyFromSecret("01234567890123456789012345678901", "")
	if err != nil {
		t.Fatalf("derive key: %v", err)
	}
	if len(key) != 32 {
		t.Fatalf("expected 32 byte key, got %d", len(key))
	}
}
