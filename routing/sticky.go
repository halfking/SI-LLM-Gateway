package routing

import (
	"crypto/sha256"
	"fmt"
	"sync"
	"time"
)

type StickyCache struct {
	mu    sync.RWMutex
	items map[string]stickyEntry
}

type stickyEntry struct {
	credentialID int
	expiresAt    time.Time
}

func NewStickyCache() *StickyCache {
	return &StickyCache{items: make(map[string]stickyEntry)}
}

func (s *StickyCache) Get(key string) (int, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	e, ok := s.items[key]
	if !ok || time.Now().After(e.expiresAt) {
		return 0, false
	}
	return e.credentialID, true
}

func (s *StickyCache) Set(key string, credentialID int, ttl time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items[key] = stickyEntry{
		credentialID: credentialID,
		expiresAt:    time.Now().Add(ttl),
	}
}

func (s *StickyCache) Delete(key string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.items, key)
}

func (s *StickyCache) Len() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.items)
}

func BuildStickyKey(tenantID string, appID, apiKeyID *int, endUser, fpSeed string) string {
	user := endUser
	if user == "" {
		user = "anonymous"
	}
	if len(user) > 256 {
		user = user[:256]
	}
	fpPart := ""
	if fpSeed != "" {
		h := sha256.Sum256([]byte(fpSeed))
		fpPart = fmt.Sprintf("%x", h[:8])
	}
	var app, key int
	if appID != nil {
		app = *appID
	}
	if apiKeyID != nil {
		key = *apiKeyID
	}
	if fpPart != "" {
		return fmt.Sprintf("%s:%d:%d:%s:%s", tenantID, app, key, fpPart, user)
	}
	return fmt.Sprintf("%s:%d:%d:%s", tenantID, app, key, user)
}
