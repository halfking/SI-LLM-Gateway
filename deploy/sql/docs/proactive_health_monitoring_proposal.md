# 主动健康监控改进方案

**日期**: 2026-06-30  
**问题**: NVIDIA credentials对MiniMax模型的支持不稳定，需要主动探测而非被动等待业务请求失败  
**目标**: 实现主动探测机制，在用户请求前发现问题并自动标记/隔离故障credentials

---

## 📊 当前状态分析

### 发现的问题

1. **NVIDIA Credentials对MiniMax的支持是间歇性的**
   - Credential 8: 85.7% 成功率 (18成功/3失败)
   - Credential 18: 42.9% 成功率 (9成功/12失败)
   - Credential 19: 64.7% 成功率 (11成功/6失败)
   - 某些时段100%成功，某些时段完全失败

2. **现有探测机制的不足**
   - Model discovery主要用于发现/v1/models列表
   - 很多探测超时(context deadline exceeded)
   - 没有针对特定模型的定期健康检查
   - 探测失败后没有自动标记credential状态

3. **被动故障检测的问题**
   - 需要实际用户请求失败才知道credential有问题
   - Empty response错误影响用户体验
   - 路由层继续向有问题的credential发送请求

### 当前系统能力

✅ **已有的基础设施**:
- Circuit breaker机制 (熔断器)
- Credential health状态字段
- Model probe runs表
- Discovery服务(model列表发现)

❌ **缺失的能力**:
- 针对特定模型的定期探测
- 探测失败自动更新credential状态
- 基于探测结果的路由决策
- 探测结果可视化dashboard

---

## 🎯 改进方案

### 方案1: 增强Credential级别的主动探测 (推荐)

#### 1.1 设计原则

**主动探测 vs 被动等待**:
- ❌ 被动: 等用户请求失败 → 影响体验
- ✅ 主动: 定期探测 → 提前发现问题 → 标记状态 → 路由避开

**探测策略**:
- 针对每个credential，探测其支持的关键模型
- 探测频率根据历史稳定性动态调整
- 探测失败触发状态更新和路由调整

#### 1.2 实现方案

##### A. 数据库Schema扩展

```sql
-- 扩展credentials表，添加探测配置
ALTER TABLE credentials 
ADD COLUMN probe_enabled BOOLEAN DEFAULT true,
ADD COLUMN probe_interval_sec INTEGER DEFAULT 300,  -- 5分钟
ADD COLUMN probe_model TEXT,  -- 用于探测的模型名称
ADD COLUMN last_probe_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN last_probe_success BOOLEAN,
ADD COLUMN probe_consecutive_failures INTEGER DEFAULT 0,
ADD COLUMN probe_failure_threshold INTEGER DEFAULT 3;  -- 连续失败3次触发降级

-- 创建探测历史表
CREATE TABLE credential_probes (
    id BIGSERIAL PRIMARY KEY,
    credential_id BIGINT NOT NULL REFERENCES credentials(id),
    provider_id BIGINT NOT NULL,
    probe_model TEXT NOT NULL,
    success BOOLEAN NOT NULL,
    http_status INTEGER,
    latency_ms INTEGER,
    error_kind TEXT,
    error_message TEXT,
    response_preview TEXT,
    triggered_by TEXT,  -- 'scheduled', 'manual', 'circuit_recovery'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_credential_probes_cred_time ON credential_probes(credential_id, created_at DESC);
CREATE INDEX idx_credential_probes_success ON credential_probes(success, created_at DESC);

-- 创建探测配置表（每个credential可以探测多个模型）
CREATE TABLE credential_probe_configs (
    id BIGSERIAL PRIMARY KEY,
    credential_id BIGINT NOT NULL REFERENCES credentials(id),
    probe_model TEXT NOT NULL,
    priority INTEGER DEFAULT 1,  -- 优先级，用于决定探测顺序
    enabled BOOLEAN DEFAULT true,
    UNIQUE(credential_id, probe_model)
);
```

##### B. 探测服务实现

创建新的探测服务: `internal/credprobe/service.go`

```go
package credprobe

import (
    "context"
    "time"
    "github.com/jackc/pgx/v5/pgxpool"
)

// Service定期探测credentials的健康状态
type Service struct {
    db          *pgxpool.Pool
    interval    time.Duration
    stopCh      chan struct{}
    probeFunc   ProbeFunc  // 实际执行探测的函数
}

type ProbeFunc func(ctx context.Context, cred *Credential, model string) (*ProbeResult, error)

type Credential struct {
    ID          int64
    ProviderID  int64
    Label       string
    BaseURL     string
    APIKey      string  // 已解密
}

type ProbeResult struct {
    Success        bool
    HTTPStatus     int
    LatencyMs      int
    ErrorKind      string
    ErrorMessage   string
    ResponseBody   string
}

// Start启动探测服务
func (s *Service) Start(ctx context.Context) {
    go func() {
        ticker := time.NewTicker(s.interval)
        defer ticker.Stop()
        
        // 立即执行一次
        s.runProbeLoop(ctx)
        
        for {
            select {
            case <-ticker.C:
                s.runProbeLoop(ctx)
            case <-s.stopCh:
                return
            case <-ctx.Done():
                return
            }
        }
    }()
}

// runProbeLoop执行一轮探测
func (s *Service) runProbeLoop(ctx context.Context) {
    // 1. 查询需要探测的credentials
    creds, err := s.loadCredentialsForProbe(ctx)
    if err != nil {
        log.Error("load credentials failed", "error", err)
        return
    }
    
    // 2. 并发探测（限制并发数）
    sem := make(chan struct{}, 10)  // 最多10个并发探测
    
    for _, cred := range creds {
        sem <- struct{}{}
        go func(c *Credential) {
            defer func() { <-sem }()
            s.probeCredential(ctx, c)
        }(cred)
    }
}

// probeCredential探测单个credential
func (s *Service) probeCredential(ctx context.Context, cred *Credential) {
    // 1. 获取该credential的探测模型列表
    models, err := s.getProbeModels(ctx, cred.ID)
    if err != nil || len(models) == 0 {
        return
    }
    
    // 2. 选择第一个优先级最高的模型进行探测
    model := models[0]
    
    // 3. 执行探测
    result, err := s.probeFunc(ctx, cred, model)
    
    // 4. 记录探测结果
    s.recordProbeResult(ctx, cred.ID, model, result, err)
    
    // 5. 根据结果更新credential状态
    s.updateCredentialStatus(ctx, cred.ID, result)
}

// updateCredentialStatus根据探测结果更新credential状态
func (s *Service) updateCredentialStatus(ctx context.Context, credID int64, result *ProbeResult) {
    if result.Success {
        // 探测成功：重置失败计数，确保状态为active/ready
        _, err := s.db.Exec(ctx, `
            UPDATE credentials 
            SET probe_consecutive_failures = 0,
                last_probe_success = true,
                last_probe_at = NOW(),
                availability_state = 'ready',
                lifecycle_status = CASE 
                    WHEN lifecycle_status = 'suspended' AND manual_disabled = false 
                    THEN 'active' 
                    ELSE lifecycle_status 
                END
            WHERE id = $1
        `, credID)
        
        if err != nil {
            log.Error("update credential status failed", "cred_id", credID, "error", err)
        }
    } else {
        // 探测失败：增加失败计数
        var failures int
        err := s.db.QueryRow(ctx, `
            UPDATE credentials 
            SET probe_consecutive_failures = probe_consecutive_failures + 1,
                last_probe_success = false,
                last_probe_at = NOW()
            WHERE id = $1
            RETURNING probe_consecutive_failures, probe_failure_threshold
        `, credID).Scan(&failures, &threshold)
        
        if err != nil {
            return
        }
        
        // 如果连续失败次数超过阈值，标记为cooling状态
        if failures >= threshold {
            _, _ = s.db.Exec(ctx, `
                UPDATE credentials 
                SET availability_state = 'cooling',
                    cooling_until = NOW() + INTERVAL '5 minutes',
                    state_reason_code = 'probe_failed',
                    state_reason_detail = $2
                WHERE id = $1
            `, credID, fmt.Sprintf("Probe failed %d times consecutively", failures))
            
            log.Warn("credential marked as cooling due to probe failures",
                "cred_id", credID, "failures", failures)
        }
    }
}
```

##### C. 探测函数实现

```go
// ProbeCredentialWithModel实际执行HTTP探测
func ProbeCredentialWithModel(ctx context.Context, cred *Credential, model string) (*ProbeResult, error) {
    ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
    defer cancel()
    
    // 构造探测请求
    url := strings.TrimSuffix(cred.BaseURL, "/") + "/chat/completions"
    payload := map[string]interface{}{
        "model": model,
        "messages": []map[string]string{
            {"role": "user", "content": "probe"},
        },
        "max_tokens": 1,
        "stream": false,
    }
    
    body, _ := json.Marshal(payload)
    req, _ := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
    req.Header.Set("Authorization", "Bearer "+cred.APIKey)
    req.Header.Set("Content-Type", "application/json")
    
    start := time.Now()
    resp, err := httpClient.Do(req)
    latency := int(time.Since(start).Milliseconds())
    
    result := &ProbeResult{
        LatencyMs: latency,
    }
    
    if err != nil {
        result.Success = false
        result.ErrorKind = classifyError(err)
        result.ErrorMessage = err.Error()
        return result, nil
    }
    defer resp.Body.Close()
    
    result.HTTPStatus = resp.StatusCode
    bodyBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
    result.ResponseBody = string(bodyBytes)
    
    // 判断成功条件
    if resp.StatusCode >= 200 && resp.StatusCode < 300 {
        // 检查响应是否有效（不是空的choices）
        var chatResp map[string]interface{}
        if json.Unmarshal(bodyBytes, &chatResp) == nil {
            if choices, ok := chatResp["choices"].([]interface{}); ok && len(choices) > 0 {
                result.Success = true
                return result, nil
            }
        }
        // 响应200但内容为空
        result.Success = false
        result.ErrorKind = "empty_response"
        result.ErrorMessage = "HTTP 200 but empty or invalid response"
    } else {
        result.Success = false
        result.ErrorKind = classifyHTTPStatus(resp.StatusCode)
        result.ErrorMessage = fmt.Sprintf("HTTP %d", resp.StatusCode)
    }
    
    return result, nil
}
```

##### D. 路由集成

修改路由逻辑，考虑探测结果：

```go
// 在选择credentials时，过滤掉探测失败的
func (r *Router) SelectCredential(model string) (*Credential, error) {
    candidates := r.GetCandidates(model)
    
    // 过滤条件：
    // 1. lifecycle_status = 'active'
    // 2. availability_state = 'ready' (排除cooling状态)
    // 3. last_probe_success = true OR last_probe_at IS NULL (新credential未探测过可以尝试)
    
    validCreds := []Credential{}
    for _, cred := range candidates {
        if cred.LifecycleStatus == "active" && 
           cred.AvailabilityState == "ready" &&
           (cred.LastProbeSuccess || cred.LastProbeAt == nil) {
            validCreds = append(validCreds, cred)
        }
    }
    
    if len(validCreds) == 0 {
        return nil, ErrNoValidCredential
    }
    
    // 根据优先级、负载等选择
    return r.selectBest(validCreds)
}
```

#### 1.3 配置探测

为每个credential配置探测模型：

```sql
-- MiniMax credentials
INSERT INTO credential_probe_configs (credential_id, probe_model, priority) VALUES
(6, 'MiniMax-M3', 1),
(6, 'MiniMax-M2.7', 2);

-- NVIDIA credentials (探测MiniMax模型)
INSERT INTO credential_probe_configs (credential_id, probe_model, priority) VALUES
(8, 'minimaxai/minimax-m3', 1),
(18, 'minimaxai/minimax-m3', 1),
(19, 'minimaxai/minimax-m3', 1);

-- 设置探测频率
UPDATE credentials 
SET probe_interval_sec = 180,  -- 3分钟探测一次
    probe_failure_threshold = 2  -- 连续失败2次触发cooling
WHERE id IN (8, 18, 19);

-- MiniMax官方credential可以放宽探测频率
UPDATE credentials 
SET probe_interval_sec = 300,  -- 5分钟
    probe_failure_threshold = 3  -- 连续失败3次
WHERE id = 6;
```

---

### 方案2: 基于实时错误率的动态调整

#### 2.1 实时错误率监控

创建实时错误率计算函数：

```sql
-- 计算credential最近N分钟的错误率
CREATE OR REPLACE FUNCTION get_credential_recent_error_rate(
    p_credential_id BIGINT,
    p_minutes INTEGER DEFAULT 10,
    p_min_requests INTEGER DEFAULT 5
) RETURNS TABLE (
    total_requests BIGINT,
    error_count BIGINT,
    error_rate NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_requests,
        COUNT(CASE WHEN NOT success THEN 1 END) as error_count,
        ROUND(100.0 * COUNT(CASE WHEN NOT success THEN 1 END) / 
              NULLIF(COUNT(*), 0), 2) as error_rate
    FROM request_logs
    WHERE credential_id = p_credential_id
      AND ts > NOW() - (p_minutes || ' minutes')::INTERVAL
    HAVING COUNT(*) >= p_min_requests;  -- 至少有N个请求才计算
END;
$$ LANGUAGE plpgsql;

-- 创建定期任务更新credential状态
CREATE OR REPLACE FUNCTION update_credentials_by_error_rate() RETURNS void AS $$
DECLARE
    cred RECORD;
    stats RECORD;
BEGIN
    -- 遍历所有active credentials
    FOR cred IN 
        SELECT id, label 
        FROM credentials 
        WHERE lifecycle_status = 'active'
    LOOP
        -- 获取最近10分钟错误率
        SELECT * INTO stats 
        FROM get_credential_recent_error_rate(cred.id, 10, 5);
        
        IF FOUND AND stats.error_rate >= 50 THEN
            -- 错误率>=50%，标记为cooling
            UPDATE credentials 
            SET availability_state = 'cooling',
                cooling_until = NOW() + INTERVAL '5 minutes',
                state_reason_code = 'high_error_rate',
                state_reason_detail = format('Error rate: %s%% (%s/%s requests)', 
                    stats.error_rate, stats.error_count, stats.total_requests)
            WHERE id = cred.id;
            
            RAISE NOTICE 'Credential % marked as cooling due to high error rate: %%%', 
                cred.label, stats.error_rate;
                
        ELSIF FOUND AND stats.error_rate < 20 AND 
              EXISTS(SELECT 1 FROM credentials WHERE id = cred.id AND availability_state = 'cooling') THEN
            -- 错误率恢复到<20%，可以恢复
            UPDATE credentials 
            SET availability_state = 'ready',
                cooling_until = NULL,
                state_reason_code = NULL,
                state_reason_detail = NULL
            WHERE id = cred.id;
            
            RAISE NOTICE 'Credential % recovered, error rate: %%%', cred.label, stats.error_rate;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

#### 2.2 创建定时任务

使用pg_cron或外部调度器：

```sql
-- 每分钟执行一次错误率检查
SELECT cron.schedule('update-cred-status', '*/1 * * * *', 'SELECT update_credentials_by_error_rate();');
```

---

### 方案3: 增强Circuit Breaker (熔断器)

#### 3.1 当前Circuit Breaker改进

修改 `circuit/breaker.go`，添加主动探测恢复：

```go
// 在half_open状态时，使用探测而不是真实请求
func (b *Breaker) RecoverWithProbe(ctx context.Context) error {
    if atomic.LoadInt32((*int32)(&b.state)) != int32(StateHalfOpen) {
        return fmt.Errorf("not in half_open state")
    }
    
    // 执行探测
    result, err := b.probeFunc(ctx, b.credentialID, b.probeModel)
    
    if err == nil && result.Success {
        // 探测成功，关闭熔断器
        b.OnSuccess()
        return nil
    }
    
    // 探测失败，重新打开熔断器
    b.OnFailure(result.ErrorKind)
    return fmt.Errorf("probe failed: %s", result.ErrorMessage)
}
```

---

## 🚀 实施计划

### Phase 1: 快速修复 (已完成 ✅)

- [x] 重新启用NVIDIA credentials
- [x] 确认当前错误率恢复正常

### Phase 2: 数据库Schema (1天)

```sql
-- 1. 添加探测相关字段
ALTER TABLE credentials 
ADD COLUMN IF NOT EXISTS probe_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS probe_interval_sec INTEGER DEFAULT 300,
ADD COLUMN IF NOT EXISTS last_probe_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS last_probe_success BOOLEAN,
ADD COLUMN IF NOT EXISTS probe_consecutive_failures INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS probe_failure_threshold INTEGER DEFAULT 3;

-- 2. 创建探测配置表
CREATE TABLE IF NOT EXISTS credential_probe_configs (
    id BIGSERIAL PRIMARY KEY,
    credential_id BIGINT NOT NULL REFERENCES credentials(id),
    probe_model TEXT NOT NULL,
    priority INTEGER DEFAULT 1,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(credential_id, probe_model)
);

-- 3. 创建探测历史表
CREATE TABLE IF NOT EXISTS credential_probes (
    id BIGSERIAL PRIMARY KEY,
    credential_id BIGINT NOT NULL REFERENCES credentials(id),
    provider_id BIGINT NOT NULL,
    probe_model TEXT NOT NULL,
    success BOOLEAN NOT NULL,
    http_status INTEGER,
    latency_ms INTEGER,
    error_kind TEXT,
    error_message TEXT,
    response_preview TEXT,
    triggered_by TEXT DEFAULT 'scheduled',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- 创建分区（按月）
CREATE TABLE credential_probes_2026_06 PARTITION OF credential_probes
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE credential_probes_2026_07 PARTITION OF credential_probes
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

-- 创建索引
CREATE INDEX idx_credential_probes_cred_time ON credential_probes(credential_id, created_at DESC);
CREATE INDEX idx_credential_probes_success ON credential_probes(success, created_at DESC);
```

### Phase 3: 配置探测 (30分钟)

```sql
-- 为现有credentials配置探测
INSERT INTO credential_probe_configs (credential_id, probe_model, priority) VALUES
(6, 'MiniMax-M3', 1),
(8, 'minimaxai/minimax-m3', 1),
(18, 'minimaxai/minimax-m3', 1),
(19, 'minimaxai/minimax-m3', 1)
ON CONFLICT (credential_id, probe_model) DO NOTHING;

-- 设置探测参数
UPDATE credentials 
SET probe_enabled = true,
    probe_interval_sec = 180,  -- 3分钟
    probe_failure_threshold = 2
WHERE id IN (8, 18, 19);

UPDATE credentials 
SET probe_enabled = true,
    probe_interval_sec = 300,  -- 5分钟
    probe_failure_threshold = 3
WHERE id = 6;
```

### Phase 4: 实现探测服务 (2-3天)

1. 创建 `internal/credprobe/` 包
2. 实现探测服务逻辑
3. 集成到main.go启动流程
4. 添加单元测试

### Phase 5: 路由集成 (1天)

1. 修改路由逻辑，过滤探测失败的credentials
2. 添加降级策略
3. 测试路由行为

### Phase 6: 监控Dashboard (1-2天)

1. 创建探测结果查询API
2. 在web dashboard显示探测状态
3. 添加告警规则

---

## 📈 预期效果

### 改进前 (当前)
- ❌ 用户请求失败才知道credential有问题
- ❌ Empty response影响用户体验
- ❌ 错误率波动大(0-80%)

### 改进后
- ✅ 提前3-5分钟发现credential问题
- ✅ 自动标记并隔离问题credentials
- ✅ 路由自动避开不可用credentials
- ✅ 用户请求错误率显著降低(<5%)
- ✅ 可视化监控，问题一目了然

---

## 🎯 关键指标

### 探测指标
- 探测成功率 (目标: >95%)
- 探测延迟 (目标: <2000ms)
- 探测覆盖率 (目标: 100%关键credentials)

### 业务指标
- 用户请求错误率 (目标: <5%)
- Empty response错误 (目标: 0)
- 平均恢复时间 (目标: <5分钟)

### 运维指标
- 故障发现时间 (目标: <3分钟)
- 自动恢复成功率 (目标: >90%)
- 误报率 (目标: <2%)

---

## 🔄 持续优化

### 短期 (1个月内)
1. 收集探测数据，调整探测频率和阈值
2. 根据不同credential的稳定性调整策略
3. 优化探测模型选择

### 中期 (3个月内)
1. 实现智能探测频率调整（稳定的credential降低频率）
2. 添加预测性维护（基于历史模式预测故障）
3. 多区域探测（从不同地理位置探测）

### 长期 (6个月内)
1. ML模型预测credential可用性
2. 自动化credential生命周期管理
3. 智能路由优化

---

## 📝 附录

### A. 快速命令

```bash
# 查看探测配置
ssh prod-app "PGPASSWORD='...' psql -h 127.0.0.1 -U llm_gateway -d llm_gateway -c \"
SELECT c.id, c.label, c.probe_enabled, c.probe_interval_sec, 
       c.last_probe_at, c.last_probe_success, c.probe_consecutive_failures
FROM credentials c WHERE c.id IN (6, 8, 18, 19);
\""

# 查看最近探测结果
ssh prod-app "PGPASSWORD='...' psql -h 127.0.0.1 -U llm_gateway -d llm_gateway -c \"
SELECT credential_id, probe_model, success, http_status, latency_ms, created_at
FROM credential_probes 
WHERE credential_id IN (6, 8, 18, 19)
ORDER BY created_at DESC LIMIT 20;
\""

# 手动触发探测
curl -X POST http://localhost:8080/admin/credentials/8/probe

# 查看credential状态
ssh prod-app "PGPASSWORD='...' psql -h 127.0.0.1 -U llm_gateway -d llm_gateway -c \"
SELECT id, label, availability_state, state_reason_code, cooling_until
FROM credentials WHERE id IN (6, 8, 18, 19);
\""
```

### B. 告警规则

```yaml
# Prometheus告警规则
groups:
  - name: credential_probe
    rules:
      - alert: CredentialProbeFailure
        expr: credential_probe_success_rate{credential_id=~"8|18|19"} < 0.5
        for: 10m
        annotations:
          summary: "Credential {{$labels.credential_id}} probe success rate < 50%"
          
      - alert: CredentialAllProbesFailed
        expr: sum(credential_probe_success{credential_id=~"8|18|19"}) == 0
        for: 5m
        annotations:
          summary: "All NVIDIA credentials failing probes"
```

---

## 总结

这个方案通过**主动探测**替代**被动等待**，可以：
1. ✅ 提前发现credential问题（3-5分钟）
2. ✅ 自动标记和隔离故障credentials
3. ✅ 显著降低用户请求错误率
4. ✅ 提供可视化监控和告警

**建议立即实施Phase 2和Phase 3**，在1-2天内完成基础设施部署。
