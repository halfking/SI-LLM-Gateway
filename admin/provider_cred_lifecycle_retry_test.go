package admin

// provider_cred_lifecycle_retry_test.go — unit tests for the admin
// health-check retry classifier (shouldRetryAdminFetchErr).
//
// 2026-06-29 audit: the manual /check-health endpoint must absorb the
// same transient blips the background probe does, otherwise operators
// will see "unreachable" between attempts that the cycle would have
// forgiven. These tests lock the policy.

import (
	"context"
	"errors"
	"fmt"
	"testing"
)

func TestShouldRetryAdminFetchErr_Retryable(t *testing.T) {
	// Transient conditions — must retry.
	cases := []error{
		fmt.Errorf(`models endpoint returned 500: internal server error`),
		fmt.Errorf(`models endpoint returned 502: bad gateway`),
		fmt.Errorf(`models endpoint returned 503: service unavailable`),
		fmt.Errorf(`models endpoint returned 504: gateway timeout`),
		fmt.Errorf(`models endpoint returned 408: request timeout`),
		fmt.Errorf(`models endpoint returned 425: too early`),
		fmt.Errorf(`models endpoint returned 429: rate limited`),
		fmt.Errorf(`Get "https://api.example.com/v1/models": dial tcp: lookup api.example.com: no such host`),
		fmt.Errorf(`Get "https://api.example.com/v1/models": dial tcp 1.2.3.4:443: connect: connection refused`),
		fmt.Errorf(`no models found from any candidate URL`),
	}
	for _, c := range cases {
		if !shouldRetryAdminFetchErr(c) {
			t.Errorf("expected retry for: %q", c.Error())
		}
	}
}

func TestShouldRetryAdminFetchErr_FailFast(t *testing.T) {
	// Clear business failures — must fail fast.
	cases := []error{
		fmt.Errorf(`models endpoint returned 400: bad request`),
		fmt.Errorf(`models endpoint returned 401: invalid api key`),
		fmt.Errorf(`models endpoint returned 402: payment required`),
		fmt.Errorf(`models endpoint returned 403: forbidden`),
		fmt.Errorf(`models endpoint returned 404: not found`),
		fmt.Errorf(`models endpoint returned 422: validation error`),
	}
	for _, c := range cases {
		if shouldRetryAdminFetchErr(c) {
			t.Errorf("expected fail-fast for: %q", c.Error())
		}
	}
}

func TestShouldRetryAdminFetchErr_Nil(t *testing.T) {
	if shouldRetryAdminFetchErr(nil) {
		t.Error("nil error: should be treated as success (no retry needed)")
	}
}

func TestShouldRetryAdminFetchErr_CtxCancel(t *testing.T) {
	// Context cancellation is a stop signal, not a transient failure.
	// Wrapping or direct context.Canceled must short-circuit retry.
	cases := []error{
		context.Canceled,
		context.DeadlineExceeded,
		fmt.Errorf("Get \"https://x.example.com\": %w", context.Canceled),
		errors.Join(errors.New("connection refused"), context.DeadlineExceeded),
	}
	for _, c := range cases {
		if shouldRetryAdminFetchErr(c) {
			t.Errorf("ctx-cancel error %q: should be fail-fast (stop signal)", c.Error())
		}
	}
}

func TestShouldRetryAdminFetchErr_NoStatusCode_DefaultsToRetryable(t *testing.T) {
	// Errors with no extractable status code are assumed network/transport
	// level → retryable. The shared classifier treats status==0 as retry.
	cases := []error{
		errors.New("no models found from any candidate URL"),
		errors.New("net/http: invalid response"),
		errors.New("some weird unrelated error"),
	}
	for _, c := range cases {
		if !shouldRetryAdminFetchErr(c) {
			t.Errorf("expected retry (no status visible) for: %q", c.Error())
		}
	}
}
