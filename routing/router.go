package routing

import (
	"log/slog"
	"math/rand"
	"sort"

	"github.com/kaixuan/llm-gateway-go/limiter"
	"github.com/kaixuan/llm-gateway-go/provider"
)

var tierOrder = [4]int{1, 2, 3, 9}

type Router struct {
	Sticky  *StickyCache
	Limiter *limiter.Limiter
}

func NewRouter(sticky *StickyCache, lim *limiter.Limiter) *Router {
	return &Router{Sticky: sticky, Limiter: lim}
}

func (r *Router) PlanCandidates(
	candidates []provider.Candidate,
	stickyCredentialID *int,
	policy *provider.Policy,
	egressPreference []string,
) []provider.Candidate {
	available := filterAvailable(candidates)
	if len(available) == 0 {
		slog.Warn("router: all candidates unavailable", "total", len(candidates))
		return nil
	}

	byTier := make(map[int][]provider.Candidate)
	for _, c := range available {
		byTier[c.Tier] = append(byTier[c.Tier], c)
	}

	tiersUsed := 0
	var ordered []provider.Candidate
	for _, tier := range tierOrder {
		bucket := byTier[tier]
		if len(bucket) == 0 {
			continue
		}
		ordered = append(ordered, p2cOrder(bucket, r.Limiter)...)
		tiersUsed++
		if tiersUsed >= policy.TierFallbackMax {
			break
		}
	}

	maxTotal := 12
	if len(ordered) > maxTotal {
		ordered = ordered[:maxTotal]
	}

	if stickyCredentialID != nil {
		ordered = prioritizeSticky(ordered, *stickyCredentialID)
	}

	if len(egressPreference) > 0 {
		ordered = applyProtocolAffinity(ordered, egressPreference)
	}

	return ordered
}

func filterAvailable(cands []provider.Candidate) []provider.Candidate {
	var out []provider.Candidate
	for _, c := range cands {
		if c.IsAvailable() {
			out = append(out, c)
		}
	}
	return out
}

func p2cOrder(cands []provider.Candidate, lim *limiter.Limiter) []provider.Candidate {
	if len(cands) <= 1 {
		return cands
	}

	pool := make([]provider.Candidate, len(cands))
	copy(pool, cands)
	out := make([]provider.Candidate, 0, len(pool))

	for len(pool) > 0 {
		if len(pool) == 1 {
			out = append(out, pool[0])
			break
		}

		minCost := cheapestCost(pool)
		closePool := make([]provider.Candidate, 0, len(pool))
		for _, c := range pool {
			cost := blendedCost(c)
			if cost == 0 || cost <= minCost*1.10 {
				closePool = append(closePool, c)
			}
		}
		samplePool := closePool
		if len(samplePool) < 2 {
			samplePool = pool
		}

		a, b := randomPair(samplePool)
		chosen := a
		if loadScore(b, lim) < loadScore(a, lim) {
			chosen = b
		}

		out = append(out, chosen)
		pool = removeCandidate(pool, chosen)
	}
	return out
}

func blendedCost(c provider.Candidate) float64 {
	in := 0.0
	out := 0.0
	if c.PriceInPer1M != nil {
		in = *c.PriceInPer1M
	}
	if c.PriceOutPer1M != nil {
		out = *c.PriceOutPer1M
	}
	return in + out
}

func cheapestCost(pool []provider.Candidate) float64 {
	min := 0.0
	for _, c := range pool {
		cost := blendedCost(c)
		if cost > 0 {
			if min == 0 || cost < min {
				min = cost
			}
		}
	}
	return min
}

func loadScore(c provider.Candidate, lim *limiter.Limiter) float64 {
	w := c.Weight
	if w <= 0 {
		w = 1
	}
	quality := c.SuccessRate
	if quality <= 0 {
		quality = 0.9
	}
	if quality < 0.2 {
		quality = 0.2
	}

	latencyPenalty := float64(c.P95LatencyMs) / 1000.0
	if latencyPenalty < 1.0 {
		latencyPenalty = 1.0
	}

	inFlight := 0
	if cred := lim.Credential(c.ProviderID, c.CredentialID); cred != nil {
		inFlight = cred.Used()
	}

	return float64(inFlight) * latencyPenalty / (float64(w) * quality)
}

func randomPair(pool []provider.Candidate) (provider.Candidate, provider.Candidate) {
	n := len(pool)
	i := rand.Intn(n)
	j := rand.Intn(n - 1)
	if j >= i {
		j++
	}
	return pool[i], pool[j]
}

func removeCandidate(pool []provider.Candidate, target provider.Candidate) []provider.Candidate {
	for i, c := range pool {
		if c.CredentialID == target.CredentialID && c.ProviderID == target.ProviderID {
			return append(pool[:i], pool[i+1:]...)
		}
	}
	return pool
}

func prioritizeSticky(ordered []provider.Candidate, stickyID int) []provider.Candidate {
	var sticky, rest []provider.Candidate
	for _, c := range ordered {
		if c.CredentialID == stickyID {
			sticky = append(sticky, c)
		} else {
			rest = append(rest, c)
		}
	}
	return append(sticky, rest...)
}

func applyProtocolAffinity(ordered []provider.Candidate, pref []string) []provider.Candidate {
	if len(pref) == 0 || len(ordered) <= 1 {
		return ordered
	}
	prefIndex := make(map[string]int, len(pref))
	for i, p := range pref {
		prefIndex[p] = i
	}
	defaultRank := len(prefIndex)

	sort.SliceStable(ordered, func(i, j int) bool {
		ri := prefIndex[ordered[i].Protocol]
		if _, ok := prefIndex[ordered[i].Protocol]; !ok {
			ri = defaultRank
		}
		rj := prefIndex[ordered[j].Protocol]
		if _, ok := prefIndex[ordered[j].Protocol]; !ok {
			rj = defaultRank
		}
		if ri != rj {
			return ri < rj
		}
		return ordered[i].SuccessRate > ordered[j].SuccessRate
	})
	return ordered
}
