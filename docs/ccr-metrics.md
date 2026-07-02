# CCR Prometheus Metrics

This document describes the Prometheus metrics exposed by the CCR (Columnar Content Repository) module for monitoring the three-tier cache performance.

## Available Metrics

### Cache Hit/Miss Counters

```
llm_gateway_ccr_cache_hits_total{tier="L1|L2|L3"}
```
Total number of cache hits by tier.
- `tier="L1"`: In-memory sync.Map hits
- `tier="L2"`: Redis hits
- `tier="L3"`: PostgreSQL hits

```
llm_gateway_ccr_cache_misses_total{tier="L1|L2|L3"}
```
Total number of cache misses by tier.

### Operation Counters

```
llm_gateway_ccr_puts_total
```
Total number of CCR Put operations (storing compressed data).

```
llm_gateway_ccr_gets_total
```
Total number of CCR Get operations (retrieving compressed data).

```
llm_gateway_ccr_errors_total
```
Total number of CCR errors (L2/L3 failures, unauthorized access, etc.).

### Hit Ratio Gauges

```
llm_gateway_ccr_hit_ratio{tier="L1|L2|L3"}
```
Cache hit ratio by tier (0.0 to 1.0). Updated every 10 seconds.

```
llm_gateway_ccr_hit_ratio_overall
```
Overall cache hit ratio across all tiers (0.0 to 1.0). Updated every 10 seconds.

## Example Queries

### Overall cache performance
```promql
# Overall hit rate
llm_gateway_ccr_hit_ratio_overall

# Total requests
rate(llm_gateway_ccr_gets_total[5m])

# Error rate
rate(llm_gateway_ccr_errors_total[5m]) / rate(llm_gateway_ccr_gets_total[5m])
```

### L1 (In-Memory) performance
```promql
# L1 hit rate
llm_gateway_ccr_hit_ratio{tier="L1"}

# L1 hits per second
rate(llm_gateway_ccr_cache_hits_total{tier="L1"}[5m])

# L1 misses per second
rate(llm_gateway_ccr_cache_misses_total{tier="L1"}[5m])
```

### L2 (Redis) performance
```promql
# L2 hit rate (among L1 misses)
llm_gateway_ccr_hit_ratio{tier="L2"}

# L2 hits per second
rate(llm_gateway_ccr_cache_hits_total{tier="L2"}[5m])
```

### L3 (PostgreSQL) performance
```promql
# L3 hit rate (among L1+L2 misses)
llm_gateway_ccr_hit_ratio{tier="L3"}

# L3 hits per second
rate(llm_gateway_ccr_cache_hits_total{tier="L3"}[5m])
```

### Cache efficiency analysis
```promql
# What percentage of requests are served by L1? (hot cache)
rate(llm_gateway_ccr_cache_hits_total{tier="L1"}[5m]) / 
rate(llm_gateway_ccr_gets_total[5m])

# What percentage need to go to L2 or L3? (cold cache)
1 - (rate(llm_gateway_ccr_cache_hits_total{tier="L1"}[5m]) / 
     rate(llm_gateway_ccr_gets_total[5m]))
```

## Grafana Dashboard

Example panels:

1. **Cache Hit Ratio by Tier** (Gauge)
   - Metric: `llm_gateway_ccr_hit_ratio`
   - Group by: `tier`

2. **Overall Hit Ratio** (Gauge)
   - Metric: `llm_gateway_ccr_hit_ratio_overall`

3. **Requests per Second** (Graph)
   - Gets: `rate(llm_gateway_ccr_gets_total[5m])`
   - Puts: `rate(llm_gateway_ccr_puts_total[5m])`

4. **Cache Performance by Tier** (Stacked Graph)
   - L1 hits: `rate(llm_gateway_ccr_cache_hits_total{tier="L1"}[5m])`
   - L2 hits: `rate(llm_gateway_ccr_cache_hits_total{tier="L2"}[5m])`
   - L3 hits: `rate(llm_gateway_ccr_cache_hits_total{tier="L3"}[5m])`
   - Misses: `rate(llm_gateway_ccr_cache_misses_total{tier="L3"}[5m])`

5. **Error Rate** (Graph)
   - Metric: `rate(llm_gateway_ccr_errors_total[5m])`
   - Alert threshold: > 0.01 (1% error rate)

## Alerts

Recommended alert rules:

```yaml
- alert: CCRHighErrorRate
  expr: rate(llm_gateway_ccr_errors_total[5m]) / rate(llm_gateway_ccr_gets_total[5m]) > 0.05
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "CCR error rate is above 5%"

- alert: CCRLowHitRatio
  expr: llm_gateway_ccr_hit_ratio_overall < 0.5
  for: 10m
  labels:
    severity: info
  annotations:
    summary: "CCR overall hit ratio is below 50% (consider tuning cache sizes)"

- alert: CCRL1LowHitRatio
  expr: llm_gateway_ccr_hit_ratio{tier="L1"} < 0.3
  for: 10m
  labels:
    severity: info
  annotations:
    summary: "L1 hit ratio is low, consider increasing L1 cache size"
```

## Tuning Guide

Based on metrics:

- **High L1 miss rate**: Increase L1 cache size or implement LRU eviction
- **High L2 miss rate**: Increase Redis TTL or memory limit
- **High L3 miss rate**: Check L3 eviction policy or increase PostgreSQL cache
- **High error rate**: Check Redis/PostgreSQL connectivity and logs
- **Low overall hit ratio**: Review Headroom compression thresholds

## Implementation Notes

- Metrics are updated atomically on each cache operation
- Gauge metrics (hit ratios) are computed every 10 seconds by a background goroutine
- Counter metrics are monotonically increasing (use `rate()` for per-second rates)
- All metrics are prefixed with `llm_gateway_ccr_` for namespace isolation
