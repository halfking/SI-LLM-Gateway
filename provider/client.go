package provider

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kaixuan/llm-gateway-go/secret"
	"golang.org/x/sync/singleflight"
)

type Candidate struct {
	CredentialID      int      `json:"credential_id"`
	ProviderID        int      `json:"provider_id"`
	BaseURL           string   `json:"base_url"`
	Protocol          string   `json:"protocol"`
	CatalogCode       string   `json:"catalog_code"`
	Tier              int      `json:"tier"`
	Weight            int      `json:"weight"`
	RawModel          string   `json:"model_name"`
	SuccessRate       float64  `json:"success_rate"`
	P95LatencyMs      int      `json:"p95_latency_ms"`
	ConcurrencyLimit  *int     `json:"concurrency_limit"`
	BalanceUSD        *float64 `json:"balance_usd"`
	CircuitState      string   `json:"circuit_state"`
	AvailabilityState string   `json:"availability_state"`
	QuotaState        string   `json:"quota_state"`
	LifecycleStatus   string   `json:"lifecycle_status"`
	Routable          bool     `json:"runtime_routable"`
	BlockReason       *string  `json:"runtime_block_reason"`
	PriceInPer1M      *float64 `json:"unit_price_in_per_1m"`
	PriceOutPer1M     *float64 `json:"unit_price_out_per_1m"`
	APIKey            string   `json:"-"`
}

func (c *Candidate) IsAvailable() bool {
	if !c.Routable {
		return false
	}
	if c.LifecycleStatus != "" && c.LifecycleStatus != "active" {
		return false
	}
	switch c.AvailabilityState {
	case "suspended", "auth_failed":
		return false
	case "cooling", "rate_limited", "unreachable":
		return false
	}
	switch c.QuotaState {
	case "balance_exhausted", "permanently_exhausted":
		return false
	case "periodic_exhausted":
		return false
	}
	if c.BalanceUSD != nil && *c.BalanceUSD <= 0 {
		return false
	}
	return true
}

type Policy struct {
	AlgorithmVersion        int `json:"algorithm_version"`
	RetryPerCredential      int `json:"retry_per_credential"`
	TierFallbackMax         int `json:"tier_fallback_max"`
	CircuitOpenSeconds      int `json:"circuit_open_seconds"`
	CircuitFailureThreshold int `json:"circuit_failure_threshold"`
	CircuitMaxOpenSeconds   int `json:"circuit_max_open_seconds"`
	StickyTTLMilliseconds   int `json:"sticky_ttl_seconds"`
}

func DefaultPolicy() *Policy {
	return &Policy{
		AlgorithmVersion:        2,
		RetryPerCredential:      1,
		TierFallbackMax:         3,
		CircuitOpenSeconds:      300,
		CircuitFailureThreshold: 5,
		CircuitMaxOpenSeconds:   1800,
		StickyTTLMilliseconds:   1800,
	}
}

type resolveResponse struct {
	ClientModel    string   `json:"client_model"`
	CanonicalName  string   `json:"canonical_name"`
	CanonicalID    *int     `json:"canonical_id"`
	ResolutionPath string   `json:"resolution_path"`
	RawModels      []string `json:"raw_models"`
	PlanOrder      []struct {
		CredentialID int    `json:"credential_id"`
		ProviderID   int    `json:"provider_id"`
		RawModel     string `json:"raw_model"`
		Tier         int    `json:"tier"`
	} `json:"plan_order"`
	Candidates []json.RawMessage `json:"candidates"`
}

type revealResponse struct {
	CredentialID int    `json:"credential_id"`
	APIKey       string `json:"api_key"`
}

type policyResponse struct {
	AlgorithmVersion        int `json:"algorithm_version"`
	RetryPerCredential      int `json:"retry_per_credential"`
	TierFallbackMax         int `json:"tier_fallback_max"`
	CircuitOpenSeconds      int `json:"circuit_open_seconds"`
	CircuitFailureThreshold int `json:"circuit_failure_threshold"`
	CircuitMaxOpenSeconds   int `json:"circuit_max_open_seconds"`
	StickyTTLMilliseconds   int `json:"sticky_ttl_seconds"`
}

type cacheEntry[T any] struct {
	value   T
	expires time.Time
}

type Client struct {
	endpoint   string
	adminKey   string
	httpClient *http.Client
	dbPool     *pgxpool.Pool
	fernetKey  []byte

	mu        sync.RWMutex
	candCache map[string]cacheEntry[*resolveResponse]
	polCache  cacheEntry[*Policy]
	keyCache  map[int]cacheEntry[string]

	sf singleflight.Group
}

func NewClient(pythonEndpoint, adminAPIKey string) *Client {
	if pythonEndpoint == "" {
		return &Client{
			candCache: make(map[string]cacheEntry[*resolveResponse]),
			keyCache:  make(map[int]cacheEntry[string]),
		}
	}
	return &Client{
		endpoint: strings.TrimRight(pythonEndpoint, "/"),
		adminKey: adminAPIKey,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		candCache: make(map[string]cacheEntry[*resolveResponse]),
		keyCache:  make(map[int]cacheEntry[string]),
	}
}

func (c *Client) Enabled() bool {
	return c.endpoint != ""
}

func (c *Client) SetDB(pool *pgxpool.Pool, secretKey, credentialEncryptionKey string) {
	c.dbPool = pool
	if key, err := secret.FernetKeyFromSecret(secretKey, credentialEncryptionKey); err == nil {
		c.fernetKey = key
	} else if pool != nil {
		slog.Warn("credential fernet key unavailable; reveal will use RPC fallback", "error", err)
	}
}

func (c *Client) GetCandidates(ctx context.Context, model, profile string) ([]Candidate, *Policy, error) {
	if !c.Enabled() {
		return nil, DefaultPolicy(), fmt.Errorf("provider client not configured")
	}

	key := model
	if profile != "" {
		key = model + "|" + profile
	}

	c.mu.RLock()
	if entry, ok := c.candCache[key]; ok && time.Now().Before(entry.expires) {
		c.mu.RUnlock()
		policy, _ := c.getPolicyCached(ctx)
		cands := c.enrichWithAPIKeys(ctx, entry.value)
		return cands, policy, nil
	}
	c.mu.RUnlock()

	v, err, _ := c.sf.Do("cand:"+key, func() (any, error) {
		resp, fetchErr := c.fetchCandidates(ctx, model, profile)
		if fetchErr != nil {
			return nil, fetchErr
		}

		c.mu.Lock()
		c.candCache[key] = cacheEntry[*resolveResponse]{
			value:   resp,
			expires: time.Now().Add(30 * time.Second),
		}
		c.mu.Unlock()
		return resp, nil
	})
	if err != nil {
		return nil, DefaultPolicy(), err
	}

	policy, _ := c.getPolicyCached(ctx)
	cands := c.enrichWithAPIKeys(ctx, v.(*resolveResponse))
	return cands, policy, nil
}

func (c *Client) GetPolicy(ctx context.Context) (*Policy, error) {
	if !c.Enabled() {
		return DefaultPolicy(), nil
	}
	return c.getPolicyCached(ctx)
}

func (c *Client) getPolicyCached(ctx context.Context) (*Policy, error) {
	c.mu.RLock()
	if c.polCache.value != nil && time.Now().Before(c.polCache.expires) {
		p := c.polCache.value
		c.mu.RUnlock()
		return p, nil
	}
	c.mu.RUnlock()

	v, err, _ := c.sf.Do("policy", func() (any, error) {
		pol, fetchErr := c.fetchPolicy(ctx)
		if fetchErr != nil {
			return DefaultPolicy(), nil
		}
		c.mu.Lock()
		c.polCache = cacheEntry[*Policy]{
			value:   pol,
			expires: time.Now().Add(10 * time.Second),
		}
		c.mu.Unlock()
		return pol, nil
	})
	if err != nil {
		return DefaultPolicy(), nil
	}
	return v.(*Policy), nil
}

func (c *Client) RevealAPIKey(ctx context.Context, providerID, credentialID int) (string, error) {
	c.mu.RLock()
	if entry, ok := c.keyCache[credentialID]; ok && time.Now().Before(entry.expires) {
		c.mu.RUnlock()
		return entry.value, nil
	}
	c.mu.RUnlock()

	v, err, _ := c.sf.Do(fmt.Sprintf("key:%d", credentialID), func() (any, error) {
		key, fetchErr := c.fetchReveal(ctx, providerID, credentialID)
		if fetchErr != nil {
			return "", fetchErr
		}
		c.mu.Lock()
		c.keyCache[credentialID] = cacheEntry[string]{
			value:   key,
			expires: time.Now().Add(5 * time.Minute),
		}
		c.mu.Unlock()
		return key, nil
	})
	if err != nil {
		return "", err
	}
	return v.(string), nil
}

func (c *Client) fetchCandidates(ctx context.Context, model, profile string) (*resolveResponse, error) {
	params := url.Values{"model": {model}}
	if profile != "" {
		params.Set("client_profile", profile)
	}
	fetchURL := fmt.Sprintf("%s/api/routing/resolve?%s", c.endpoint, params.Encode())

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fetchURL, nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	c.setAuth(req)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("http call: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("resolve returned %d: %s", resp.StatusCode, string(body))
	}

	var result resolveResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode: %w", err)
	}
	return &result, nil
}

func (c *Client) fetchPolicy(ctx context.Context) (*Policy, error) {
	fetchURL := c.endpoint + "/api/routing/policy"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fetchURL, nil)
	if err != nil {
		return nil, err
	}
	c.setAuth(req)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return DefaultPolicy(), nil
	}

	var pr policyResponse
	if err := json.NewDecoder(resp.Body).Decode(&pr); err != nil {
		return DefaultPolicy(), nil
	}

	pol := &Policy{
		AlgorithmVersion:        pr.AlgorithmVersion,
		RetryPerCredential:      pr.RetryPerCredential,
		TierFallbackMax:         pr.TierFallbackMax,
		CircuitOpenSeconds:      pr.CircuitOpenSeconds,
		CircuitFailureThreshold: pr.CircuitFailureThreshold,
		CircuitMaxOpenSeconds:   pr.CircuitMaxOpenSeconds,
		StickyTTLMilliseconds:   pr.StickyTTLMilliseconds,
	}
	if pol.AlgorithmVersion == 0 {
		pol.AlgorithmVersion = 2
	}
	if pol.RetryPerCredential == 0 {
		pol.RetryPerCredential = 1
	}
	if pol.TierFallbackMax == 0 {
		pol.TierFallbackMax = 3
	}
	if pol.CircuitOpenSeconds == 0 {
		pol.CircuitOpenSeconds = 300
	}
	if pol.CircuitFailureThreshold == 0 {
		pol.CircuitFailureThreshold = 5
	}
	if pol.CircuitMaxOpenSeconds == 0 {
		pol.CircuitMaxOpenSeconds = 1800
	}
	if pol.StickyTTLMilliseconds == 0 {
		pol.StickyTTLMilliseconds = 1800
	}
	return pol, nil
}

func (c *Client) fetchReveal(ctx context.Context, providerID, credentialID int) (string, error) {
	if c.dbPool != nil && len(c.fernetKey) == 32 {
		if apiKey, err := c.fetchRevealDB(ctx, providerID, credentialID); err == nil {
			return apiKey, nil
		} else {
			slog.Warn("credential reveal DB failed, falling back to RPC", "credential_id", credentialID, "error", err)
		}
	}
	if c.endpoint == "" {
		return "", fmt.Errorf("provider reveal not configured")
	}
	fetchURL := fmt.Sprintf("%s/api/providers/%d/credentials/%d/reveal", c.endpoint, providerID, credentialID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, fetchURL, nil)
	if err != nil {
		return "", err
	}
	c.setAuth(req)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("reveal returned %d for cred %d", resp.StatusCode, credentialID)
	}

	var rr revealResponse
	if err := json.NewDecoder(resp.Body).Decode(&rr); err != nil {
		return "", err
	}
	return rr.APIKey, nil
}

func (c *Client) fetchRevealDB(ctx context.Context, providerID, credentialID int) (string, error) {
	var ciphertext []byte
	err := c.dbPool.QueryRow(ctx, `
		SELECT secret_ciphertext
		FROM credentials
		WHERE id = $1 AND provider_id = $2 AND status <> 'disabled'
	`, credentialID, providerID).Scan(&ciphertext)
	if err != nil {
		if err == pgx.ErrNoRows {
			return "", fmt.Errorf("credential %d not found", credentialID)
		}
		return "", err
	}
	if len(ciphertext) == 0 {
		return "", fmt.Errorf("credential %d has no secret", credentialID)
	}
	return secret.DecryptFernet(ciphertext, c.fernetKey)
}

func (c *Client) enrichWithAPIKeys(ctx context.Context, rr *resolveResponse) []Candidate {
	if rr == nil {
		return nil
	}

	planSet := make(map[int]bool, len(rr.PlanOrder))
	for _, p := range rr.PlanOrder {
		planSet[p.CredentialID] = true
	}

	var cands []Candidate
	for _, raw := range rr.Candidates {
		var cand Candidate
		if err := json.Unmarshal(raw, &cand); err != nil {
			continue
		}
		if !planSet[cand.CredentialID] {
			continue
		}

		apiKey, err := c.RevealAPIKey(ctx, cand.ProviderID, cand.CredentialID)
		if err != nil {
			slog.Warn("failed to reveal api key",
				"credential_id", cand.CredentialID,
				"provider_id", cand.ProviderID,
				"error", err,
			)
			continue
		}
		cand.APIKey = apiKey
		cands = append(cands, cand)
	}

	planOrder := rr.PlanOrder
	orderMap := make(map[int]int, len(planOrder))
	for i, p := range planOrder {
		orderMap[p.CredentialID] = i
	}

	byID := make(map[int]*Candidate, len(cands))
	for i := range cands {
		byID[cands[i].CredentialID] = &cands[i]
	}

	ordered := make([]Candidate, 0, len(planOrder))
	for _, p := range planOrder {
		if cand, ok := byID[p.CredentialID]; ok {
			ordered = append(ordered, *cand)
		}
	}
	return ordered
}

func (c *Client) setAuth(req *http.Request) {
	if c.adminKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.adminKey)
	}
}
