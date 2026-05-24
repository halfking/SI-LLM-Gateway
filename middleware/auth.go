// Package middleware provides HTTP middleware for the LLM Gateway Go data plane.
package middleware

import (
	"crypto/subtle"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
)

// APIKeyAuth returns an HTTP middleware that validates the "Authorization:
// Bearer <key>" header against the configured gateway API key.
//
// The expected key is read from the LLM_GATEWAY_API_KEY environment variable.
// If the variable is empty, authentication is disabled (development mode).
func APIKeyAuth(next http.Handler) http.Handler {
	expectedKey := os.Getenv("LLM_GATEWAY_API_KEY")

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if expectedKey == "" {
			next.ServeHTTP(w, r)
			return
		}

		if r.URL.Path == "/healthz" || r.URL.Path == "/" {
			next.ServeHTTP(w, r)
			return
		}

		auth := r.Header.Get("Authorization")
		if len(auth) < 7 || auth[:7] != "Bearer " {
			writeUnauthorized(w, "Missing or malformed Authorization header")
			return
		}
		provided := auth[7:]

		if subtle.ConstantTimeCompare([]byte(expectedKey), []byte(provided)) != 1 {
			slog.Warn("auth: invalid API key",
				"remote", r.RemoteAddr,
				"path", r.URL.Path,
			)
			writeUnauthorized(w, "Invalid API key")
			return
		}

		next.ServeHTTP(w, r)
	})
}

func writeUnauthorized(w http.ResponseWriter, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]any{
			"message": msg,
			"type":    "authentication_error",
			"code":    "invalid_api_key",
		},
	})
}
