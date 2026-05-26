package routing

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/kaixuan/llm-gateway-go/audit"
	"github.com/kaixuan/llm-gateway-go/circuit"
	"github.com/kaixuan/llm-gateway-go/errorsx"
	"github.com/kaixuan/llm-gateway-go/identity"
	"github.com/kaixuan/llm-gateway-go/limiter"
	"github.com/kaixuan/llm-gateway-go/pool"
	"github.com/kaixuan/llm-gateway-go/provider"
	"github.com/kaixuan/llm-gateway-go/relay"
	"github.com/kaixuan/llm-gateway-go/resolve"
	"github.com/kaixuan/llm-gateway-go/transform"
	upstreampkg "github.com/kaixuan/llm-gateway-go/upstream"
)

type ExecuteResult struct {
	Response  *http.Response
	Candidate provider.Candidate
	LatencyMs int
}

type ExecuteError struct {
	LastErr   error
	Tried     int
	Exhausted bool
}

func (e *ExecuteError) Error() string {
	if e.LastErr != nil {
		return fmt.Sprintf("all %d candidates failed: %v", e.Tried, e.LastErr)
	}
	return fmt.Sprintf("all %d candidates failed", e.Tried)
}

type Executor struct {
	Router     *Router
	Circuit    *circuit.Manager
	Limiter    *limiter.Limiter
	Pools      *pool.PoolManager
	Upstream   *upstreampkg.Client
	Normalizer *relay.Normalizer
	Auditor    audit.Sink
}

func NewExecutor(
	router *Router,
	cm *circuit.Manager,
	lim *limiter.Limiter,
	pools *pool.PoolManager,
	upstream *upstreampkg.Client,
	norm *relay.Normalizer,
	auditor audit.Sink,
) *Executor {
	if auditor == nil {
		auditor = &audit.LogSink{}
	}
	return &Executor{
		Router:     router,
		Circuit:    cm,
		Limiter:    lim,
		Pools:      pools,
		Upstream:   upstream,
		Normalizer: norm,
		Auditor:    auditor,
	}
}

type ExecParams struct {
	W             http.ResponseWriter
	R             *http.Request
	BodyBytes     []byte
	IsStream      bool
	ClientModel   string
	OutboundModel string
	ClientID      identity.ClientIdentity
	Transform     *transform.TransformResult
	Resolution    *resolve.Resolution
	Candidates    []provider.Candidate
	Policy        *provider.Policy
	AuditBuilder  *audit.EventBuilder
}

func (e *Executor) Execute(params *ExecParams) (*ExecuteResult, error) {
	candidates := e.Router.PlanCandidates(
		params.Candidates,
		nil,
		params.Policy,
		egressPref(params.Transform),
	)
	if len(candidates) == 0 {
		return nil, &ExecuteError{Tried: 0, Exhausted: true}
	}

	tTotal := time.Now()
	retryPerCred := params.Policy.RetryPerCredential
	var lastErr error
	tried := 0

	for _, cand := range candidates {
		tried++

		if !e.Circuit.Allow(cand.ProviderID, cand.CredentialID) {
			slog.Debug("executor: circuit open, skipping candidate",
				"credential_id", cand.CredentialID,
				"provider_id", cand.ProviderID,
			)
			lastErr = fmt.Errorf("circuit open for credential %d", cand.CredentialID)
			continue
		}

		release, acquireErr := e.Limiter.AcquireAll(
			params.R.Context(),
			cand.ProviderID,
			cand.CredentialID,
			params.ClientID.IdentityHash,
		)
		if acquireErr != nil {
			slog.Debug("executor: concurrency limit, skipping candidate",
				"credential_id", cand.CredentialID,
			)
			lastErr = acquireErr
			continue
		}

		result, execErr := e.tryCandidate(params, cand, retryPerCred, tTotal)
		release()

		if execErr == nil {
			return result, nil
		}

		lastErr = execErr
		kind := errorsx.ClassifyError(execErr, nil)
		if kind == errorsx.KindAuth || kind == errorsx.KindQuota {
			e.Circuit.RecordFailure(cand.ProviderID, cand.CredentialID, kind)
			continue
		}
		e.Circuit.RecordFailure(cand.ProviderID, cand.CredentialID, kind)
	}

	return nil, &ExecuteError{LastErr: lastErr, Tried: tried, Exhausted: true}
}

func (e *Executor) tryCandidate(
	params *ExecParams,
	cand provider.Candidate,
	maxRetries int,
	tTotal time.Time,
) (*ExecuteResult, error) {
	outboundModel := params.OutboundModel
	if outboundModel == "" {
		outboundModel = cand.RawModel
	}

	bodyBytes := params.BodyBytes
	if outboundModel != params.ClientModel {
		bodyBytes = relay.ReplaceModelInRequestBody(bodyBytes, outboundModel)
	}

	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			delay := time.Duration(500*(1<<(attempt-1))) * time.Millisecond
			select {
			case <-params.R.Context().Done():
				return nil, params.R.Context().Err()
			case <-time.After(delay):
			}
		}

		upstreamURL := cand.BaseURL + "/v1/chat/completions"
		if cand.Protocol == "anthropic-messages" {
			upstreamURL = cand.BaseURL + "/v1/messages"
		}

		req, err := http.NewRequestWithContext(
			params.R.Context(),
			http.MethodPost,
			upstreamURL,
			bytes.NewReader(bodyBytes),
		)
		if err != nil {
			return nil, err
		}

		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+cand.APIKey)
		if params.IsStream {
			req.Header.Set("Accept", "text/event-stream")
		}
		req.Header.Set("X-Request-Id", params.R.Header.Get("X-Request-Id"))
		req.Header.Set("X-Virtual-Client-Id", params.ClientID.VirtualClientID)
		req.Header.Set("X-Virtual-IP", params.ClientID.VirtualIP)
		req.Header.Set("X-Virtual-MAC", params.ClientID.VirtualMAC)

		if params.Transform != nil {
			for _, h := range params.Transform.StripHeaders {
				req.Header.Del(h)
			}
			for k, v := range params.Transform.InjectHeaders {
				req.Header.Set(k, v)
			}
		}

		var httpClient *http.Client
		if e.Pools != nil {
			poolKey := pool.PoolKey{
				IdentityHash:  params.ClientID.IdentityHash,
				ProviderID:    cand.ProviderID,
				CredentialID:  cand.CredentialID,
			}
			if p := e.Pools.GetOrCreate(poolKey, ""); p.State() == pool.PoolActive {
				httpClient = p.Client()
			}
		}
		if httpClient == nil {
			httpClient = http.DefaultClient
		}

		timeout := relay.UpstreamTimeout()
		if params.IsStream {
			timeout = relay.StreamTimeout()
		}
		ctx, cancel := context.WithTimeout(params.R.Context(), timeout)
		defer cancel()
		req = req.WithContext(ctx)

		if e.Upstream != nil {
			req.GetBody = func() (io.ReadCloser, error) {
				return io.NopCloser(bytes.NewReader(bodyBytes)), nil
			}
		}

		var resp *http.Response
		var uErr *upstreampkg.Error
		if e.Upstream != nil {
			resp, uErr = e.Upstream.Do(req)
		} else {
			var doErr error
			resp, doErr = httpClient.Do(req)
			if doErr != nil {
				uErr = &upstreampkg.Error{Kind: errorsx.ClassifyError(doErr, nil), Message: doErr.Error(), Err: doErr}
			}
		}

		if uErr != nil && (resp == nil || resp.StatusCode >= 500) {
			errKind := errorsx.ErrorKind("")
			if uErr != nil {
				errKind = uErr.Kind
			}
			if errKind != errorsx.KindCanceled {
				e.Circuit.RecordFailure(cand.ProviderID, cand.CredentialID, errKind)
				if errKind == errorsx.KindRateLimit {
					e.Limiter.Shrink(cand.ProviderID, cand.CredentialID)
				}
			}
			if !errorsx.IsRetryable(errKind) || attempt >= maxRetries {
				return nil, uErr
			}
			continue
		}

		if resp != nil && resp.StatusCode >= 400 {
			defer resp.Body.Close()
			body := make([]byte, 4096)
			n, _ := resp.Body.Read(body)
			errKind := errorsx.ClassifyError(nil, resp)

			for k, vs := range resp.Header {
				for _, v := range vs {
					params.W.Header().Add(k, v)
				}
			}
			params.W.WriteHeader(resp.StatusCode)
			if n > 0 {
				params.W.Write(body[:n])
			}

			if resp.StatusCode >= 400 && resp.StatusCode < 500 &&
				resp.StatusCode != 429 && resp.StatusCode != 401 &&
				resp.StatusCode != 403 && resp.StatusCode != 402 {
				e.Circuit.RecordSuccess(cand.ProviderID, cand.CredentialID)
			} else {
				e.Circuit.RecordFailure(cand.ProviderID, cand.CredentialID, errKind)
				if errKind == errorsx.KindRateLimit {
					e.Limiter.Shrink(cand.ProviderID, cand.CredentialID)
				}
			}
			if !errorsx.IsRetryable(errKind) || attempt >= maxRetries {
				return nil, fmt.Errorf("upstream %d", resp.StatusCode)
			}
			continue
		}

		e.Circuit.RecordSuccess(cand.ProviderID, cand.CredentialID)
		latencyMs := int(time.Since(tTotal).Milliseconds())

		if params.IsStream {
			relay.StreamChat(params.W, resp, params.ClientModel, outboundModel, e.Normalizer)
		} else {
			defer resp.Body.Close()
			respBody, err := io.ReadAll(io.LimitReader(resp.Body, int64(relay.MaxBodySize())+1))
			if err != nil {
				return nil, err
			}
			if len(respBody) > relay.MaxBodySize() {
				slog.Warn("upstream response truncated", "size", len(respBody))
				respBody = respBody[:relay.MaxBodySize()]
			}
			if params.ClientModel != "" {
				respBody = relay.ReplaceModelInResponseBody(respBody, params.ClientModel)
			}
			if e.Normalizer != nil {
				respBody = e.Normalizer.NormalizeChunk(respBody, false)
			}
			for k, vs := range resp.Header {
				for _, v := range vs {
					params.W.Header().Add(k, v)
				}
			}
			params.W.WriteHeader(resp.StatusCode)
			params.W.Write(respBody)
		}

		return &ExecuteResult{
			Response:  resp,
			Candidate: cand,
			LatencyMs: latencyMs,
		}, nil
	}
	return nil, fmt.Errorf("exhausted %d retries for credential %d", maxRetries, cand.CredentialID)
}

func egressPref(tx *transform.TransformResult) []string {
	if tx == nil || len(tx.EgressPreference) == 0 {
		return nil
	}
	return tx.EgressPreference
}

// Ensure compatibility with existing relay functions that we need to expose.
// We add small wrappers to expose what executor needs.
