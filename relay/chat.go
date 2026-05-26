package relay

import (
	"log/slog"
	"net/url"
	"os"
)

var upstream *url.URL

func init() {
	target := os.Getenv("LLM_GATEWAY_UPSTREAM")
	if target == "" {
		target = "http://127.0.0.1:8780"
	}
	var err error
	upstream, err = url.Parse(target)
	if err != nil {
		slog.Error("invalid LLM_GATEWAY_UPSTREAM", "url", target, "error", err)
		upstream, _ = url.Parse("http://127.0.0.1:8780")
	}
}
