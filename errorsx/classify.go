package errorsx

import (
	"context"
	"errors"
	"net/http"
	"strings"
)

type ErrorKind string

const (
	KindTransient    ErrorKind = "transient"
	KindTimeout      ErrorKind = "timeout"
	KindNetwork      ErrorKind = "network"
	KindRateLimit    ErrorKind = "rate_limit"
	KindAuth         ErrorKind = "auth"
	KindQuota        ErrorKind = "quota"
	KindUpstreamDown ErrorKind = "upstream_down"
)

func ClassifyError(err error, resp *http.Response) ErrorKind {
	if err != nil {
		if errors.Is(err, context.Canceled) {
			return ""
		}
		msg := err.Error()
		if strings.Contains(msg, "timeout") || strings.Contains(msg, "deadline") {
			return KindTimeout
		}
		if strings.Contains(msg, "connection") || strings.Contains(msg, "refused") ||
			strings.Contains(msg, "no such host") || strings.Contains(msg, "reset") {
			return KindNetwork
		}
		return KindTransient
	}
	if resp == nil {
		return KindUpstreamDown
	}
	switch {
	case resp.StatusCode == 429:
		return KindRateLimit
	case resp.StatusCode == 401 || resp.StatusCode == 403:
		return KindAuth
	case resp.StatusCode == 402:
		return KindQuota
	case resp.StatusCode >= 500:
		return KindUpstreamDown
	default:
		return KindTransient
	}
}

func IsRetryable(kind ErrorKind) bool {
	switch kind {
	case KindTransient, KindTimeout, KindNetwork, KindUpstreamDown, KindRateLimit:
		return true
	default:
		return false
	}
}
