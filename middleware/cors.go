package middleware

import (
	"net/http"
	"os"
	"strings"
)

// CORS returns middleware that handles Cross-Origin Resource Sharing headers.
// Origins are configured via LLM_GATEWAY_CORS_ORIGINS (comma-separated, default "*").
func CORS(next http.Handler) http.Handler {
	origins := os.Getenv("LLM_GATEWAY_CORS_ORIGINS")
	if origins == "" {
		origins = "*"
	}
	allowMethods := "GET, POST, PUT, DELETE, OPTIONS"
	allowHeaders := "Content-Type, Authorization, X-Request-Id, X-Device-Seed, X-Machine-Id, X-Runtime-Name, X-Runtime-Version, X-OS-Name, X-OS-Arch, X-Client-Profile"
	maxAge := "86400"

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")

		// Set CORS headers
		if origins == "*" {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		} else if origin != "" {
			// Check if the origin is in the allowed list
			for _, o := range strings.Split(origins, ",") {
				if strings.TrimSpace(o) == origin {
					w.Header().Set("Access-Control-Allow-Origin", origin)
					break
				}
			}
		}

		w.Header().Set("Access-Control-Allow-Methods", allowMethods)
		w.Header().Set("Access-Control-Allow-Headers", allowHeaders)
		w.Header().Set("Access-Control-Max-Age", maxAge)

		// Handle preflight requests
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
