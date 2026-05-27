package errorsx

import (
	"context"
	"errors"
	"net/http"
	"strings"
)

type ErrorKind string

const (
	KindTransient       ErrorKind = "transient"
	KindTimeout         ErrorKind = "timeout"
	KindNetwork         ErrorKind = "network"
	KindRateLimit       ErrorKind = "rate_limit"
	KindAuth            ErrorKind = "auth"
	KindQuota           ErrorKind = "quota"
	KindUpstreamDown    ErrorKind = "upstream_down"
	KindCanceled        ErrorKind = "canceled"
	KindConcurrent      ErrorKind = "concurrent"
	KindAuthRevoked     ErrorKind = "auth_revoked"
	KindQuotaPeriodic   ErrorKind = "quota_periodic"
	KindQuotaBalance    ErrorKind = "quota_balance"
	KindQuotaPermanent  ErrorKind = "quota_permanent"
	KindModelNotFound   ErrorKind = "model_not_found"
)

func ClassifyError(err error, resp *http.Response) ErrorKind {
	if err != nil {
		if errors.Is(err, context.Canceled) {
			return KindCanceled
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
	case KindTransient, KindTimeout, KindNetwork, KindUpstreamDown, KindRateLimit, KindConcurrent:
		return true
	default:
		return false
	}
}

func IsCredentialFatal(kind ErrorKind) bool {
	switch kind {
	case KindAuth, KindAuthRevoked, KindQuota, KindQuotaPeriodic, KindQuotaBalance, KindQuotaPermanent:
		return true
	default:
		return false
	}
}
