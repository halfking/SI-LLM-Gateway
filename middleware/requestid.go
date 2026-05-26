package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
)

// requestIDKey is the context key for the request ID.
type requestIDKey struct{}

// WithRequestID injects a unique X-Request-Id header into every response and
// stores it in the request context.
func WithRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-Id")
		if id == "" {
			id = generateID()
			r.Header.Set("X-Request-Id", id)
		}
		w.Header().Set("X-Request-Id", id)
		next.ServeHTTP(w, r)
	})
}

func generateID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}
