package admin

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"
)

// TopProviderStats represents usage statistics for a provider
type TopProviderStats struct {
	ProviderCode string `json:"provider_code"`
	ProviderName string `json:"provider_name"`
	RequestCount int64  `json:"request_count"`
	Color        string `json:"color,omitempty"`
}

// handleTopProviders returns the top N providers by request count
// GET /api/admin/top-providers?limit=6&days=7
func (h *Handler) handleTopProviders(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	if h.db == nil {
		writeError(w, http.StatusServiceUnavailable, "database not configured")
		return
	}

	// Parse query parameters
	limitStr := r.URL.Query().Get("limit")
	daysStr := r.URL.Query().Get("days")

	limit := 6
	if limitStr != "" {
		if l, err := parseInt(limitStr); err == nil && l > 0 && l <= 20 {
			limit = l
		}
	}

	days := 7
	if daysStr != "" {
		if d, err := parseInt(daysStr); err == nil && d > 0 && d <= 90 {
			days = d
		}
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	// Query to get top providers by request count in the last N days
	query := `
		SELECT 
			COALESCE(p.catalog_code, '') AS provider_code,
			COALESCE(p.display_name, p.catalog_code, 'Unknown') AS provider_name,
			COUNT(*) AS request_count
		FROM request_logs rl
		LEFT JOIN providers p ON rl.provider_id = p.id
		WHERE rl.ts >= NOW() - INTERVAL '1 day' * $1
			AND p.catalog_code IS NOT NULL
			AND p.catalog_code != ''
			AND p.enabled = TRUE
		GROUP BY p.catalog_code, p.display_name
		ORDER BY request_count DESC
		LIMIT $2
	`

	rows, err := h.db.Query(ctx, query, days, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "query failed: "+err.Error())
		return
	}
	defer rows.Close()

	var results []TopProviderStats
	for rows.Next() {
		var stat TopProviderStats
		if err := rows.Scan(&stat.ProviderCode, &stat.ProviderName, &stat.RequestCount); err != nil {
			continue
		}
		// Assign color based on provider (will be refined on frontend)
		stat.Color = assignProviderColor(stat.ProviderCode)
		results = append(results, stat)
	}

	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "scan failed: "+err.Error())
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"top_providers": results,
		"limit":         limit,
		"days":          days,
	})
}

// assignProviderColor assigns a default color to a provider based on its code
func assignProviderColor(code string) string {
	// Color palette for top providers
	colors := []string{
		"#4d8df7", // blue
		"#a379f7", // purple
		"#f97316", // orange
		"#10b981", // green
		"#f59e0b", // amber
		"#ec4899", // pink
	}

	// Map known providers to colors
	switch code {
	case "openai":
		return "#4d8df7" // blue
	case "anthropic":
		return "#a379f7" // purple
	case "zhipu", "moonshot", "minimax", "baichuan", "01ai":
		return "#f97316" // orange
	case "deepseek", "alibaba":
		return "#10b981" // green
	default:
		// Use hash-based color assignment for others
		hash := 0
		for _, c := range code {
			hash = (hash*31 + int(c)) % len(colors)
		}
		return colors[hash]
	}
}

func parseInt(s string) (int, error) {
	return strconv.Atoi(s)
}
