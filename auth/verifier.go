package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/sync/singleflight"
)

type KeyInfo struct {
	ID                   int     `json:"id"`
	TenantID             string  `json:"tenant_id"`
	ApplicationID        int     `json:"application_id"`
	ApplicationCode      string  `json:"application_code"`
	DefaultClientProfile *string `json:"default_client_profile"`
	OwnerUser            *string `json:"owner_user"`
	RateLimitRPM         *int    `json:"rate_limit_rpm"`
	BudgetUSD            *float64 `json:"budget_usd"`
}

type KeyVerifier struct {
	endpoint   string
	adminKey   string
	httpClient *http.Client

	cache  map[string]*keyCacheEntry
	mu     sync.RWMutex
	sfGroup singleflight.Group

	ttl time.Duration
}

type keyCacheEntry struct {
	info      *KeyInfo
	expiresAt time.Time
}

func NewKeyVerifier(pythonEndpoint, adminAPIKey string) *KeyVerifier {
	return &KeyVerifier{
		endpoint: pythonEndpoint,
		adminKey: adminAPIKey,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
		cache: make(map[string]*keyCacheEntry),
		ttl:   60 * time.Second,
	}
}

func (kv *KeyVerifier) Enabled() bool {
	return kv.endpoint != "" && kv.adminKey != ""
}

func (kv *KeyVerifier) Verify(ctx context.Context, rawKey string) (*KeyInfo, error) {
	if !kv.Enabled() {
		return nil, fmt.Errorf("key verifier not configured")
	}

	if info := kv.getCache(rawKey); info != nil {
		return info, nil
	}

	v, err, _ := kv.sfGroup.Do("key:"+rawKey, func() (any, error) {
		info, rpcErr := kv.callVerifyRPC(ctx, rawKey)
		if rpcErr != nil {
			return nil, rpcErr
		}
		kv.setCache(rawKey, info)
		return info, nil
	})
	if err != nil {
		return nil, err
	}
	return v.(*KeyInfo), nil
}

func (kv *KeyVerifier) getCache(key string) *KeyInfo {
	kv.mu.RLock()
	defer kv.mu.RUnlock()
	entry, ok := kv.cache[key]
	if !ok {
		return nil
	}
	if time.Now().After(entry.expiresAt) {
		return nil
	}
	return entry.info
}

func (kv *KeyVerifier) setCache(key string, info *KeyInfo) {
	kv.mu.Lock()
	defer kv.mu.Unlock()
	kv.cache[key] = &keyCacheEntry{
		info:      info,
		expiresAt: time.Now().Add(kv.ttl),
	}
	if len(kv.cache) > 10000 {
		now := time.Now()
		for k, e := range kv.cache {
			if now.After(e.expiresAt) {
				delete(kv.cache, k)
			}
		}
	}
}

func (kv *KeyVerifier) callVerifyRPC(ctx context.Context, rawKey string) (*KeyInfo, error) {
	reqBody := fmt.Sprintf(`{"api_key":"%s"}`, rawKey)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, kv.endpoint+"/api/keys/verify", strings.NewReader(reqBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+kv.adminKey)

	resp, err := kv.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("key verify RPC failed: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))

	if resp.StatusCode == http.StatusUnauthorized {
		return nil, &InvalidKeyError{Message: "Invalid or expired API key"}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("key verify RPC returned %d: %s", resp.StatusCode, string(body))
	}

	var info KeyInfo
	if err := json.Unmarshal(body, &info); err != nil {
		return nil, fmt.Errorf("key verify RPC invalid response: %w", err)
	}

	slog.Debug("key verified",
		"key_id", info.ID,
		"tenant_id", info.TenantID,
		"app_code", info.ApplicationCode,
	)
	return &info, nil
}

type InvalidKeyError struct {
	Message string
}

func (e *InvalidKeyError) Error() string {
	return e.Message
}
