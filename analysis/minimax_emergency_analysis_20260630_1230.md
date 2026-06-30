# 🚨 MiniMax-M3 紧急故障分析报告

**时间**: 2026-06-30 12:30 UTC  
**严重程度**: 🔴 **严重 - 错误率88.89%**  
**状态**: 已采取紧急措施

---

## 📊 当前状况

### 最近30分钟统计
- **总请求数**: 18
- **失败数**: 16
- **错误率**: **88.89%** 🔴
- **主要错误**: `unknown` (87.5%), upstream阶段失败

### 最近6小时趋势

| 时间段 | 总请求 | 成功 | 失败 | 错误率 | 状态 |
|--------|--------|------|------|--------|------|
| 12:00-13:00 | 21 | 2 | 19 | **90.48%** | 🔴 危急 |
| 11:00-12:00 | 7 | 0 | 7 | **100%** | 🔴 完全失败 |
| 10:00-11:00 | 242 | 187 | 55 | 22.73% | 🟡 可接受 |
| 09:00-10:00 | 436 | 327 | 109 | 25.00% | 🟡 可接受 |
| 08:00-09:00 | 39 | 37 | 2 | 5.13% | ✅ 正常 |
| 07:00-08:00 | 6 | 4 | 2 | 33.33% | 🟡 一般 |

**关键时间点**: **11:00 UTC** - 错误率突然飙升！

---

## 🔍 根本原因分析

### 1. 故障特征

**所有失败请求的共同特征**:
- ❌ `failure_stage = upstream` - 在upstream API调用阶段失败
- ❌ `stream_chunk_count = 0` - 没有收到任何响应chunk
- ❌ `response_body` 为空 - 没有错误详情
- ❌ `error_kind = unknown` - 错误分类为未知
- ⚠️ 延迟: 400-1400ms - 相对较短，说明快速失败

### 2. 影响范围

**所有credentials都受影响**:

| Credential | Provider | 最近2小时失败数 | 最后失败时间 | 状态 |
|-----------|---------|--------------|-------------|------|
| 6 (minimax-prod-1) | MiniMax | 47 | 12:28:03 | 🔴 大量失败 |
| 19 (endless) | NVIDIA | 17 | 12:30:03 | 🔴 持续失败 |
| 18 (nvidia-build-v2) | NVIDIA | 9 | 11:50:57 | 🟡 部分失败 |
| 8 (nvidia-build-new) | NVIDIA | 7 | 10:39:22 | 🟢 较早恢复 |

### 3. 可能原因

#### 原因A: MiniMax API服务端问题 (最可能)
**证据**:
- ✅ 11:00突然开始大量失败
- ✅ 影响所有credentials（包括官方MiniMax credential）
- ✅ 错误特征一致：upstream失败，无响应
- ✅ API端点可达（curl测试返回401认证错误）
- ✅ 之前时段（08:00-10:00）表现正常

**推测**: MiniMax API在11:00左右出现故障或限流

#### 原因B: 网络问题
**证据**:
- ⚠️ 快速失败（400-1400ms延迟）
- ⚠️ 没有收到任何响应数据
- ❌ 但API端点可达（curl测试成功）

**可能性**: 较低

#### 原因C: Gateway配置问题
**证据**:
- ❌ 11:00前后没有部署变更
- ❌ 所有credentials同时失败（不太可能是配置）
- ❌ Docker日志显示正常运行

**可能性**: 很低

#### 原因D: API Key配额耗尽
**证据**:
- ⚠️ Credential 6在10小时内有530个成功请求
- ⚠️ 可能触发了速率限制
- ❌ 但所有credentials同时失败（不同API key）

**可能性**: 中等

---

## ⚡ 已采取的紧急措施

### 1. 隔离高失败率Credentials ✅

```sql
-- 已执行
UPDATE credentials 
SET availability_state = 'cooling',
    cooling_until = NOW() + INTERVAL '10 minutes',
    state_reason_code = 'high_failure_rate',
    state_reason_detail = 'Credential showing 80%+ failure rate since 11:00'
WHERE id IN (6, 19);
```

**结果**:
- Credential 6 (minimax-prod-1) → cooling (10分钟)
- Credential 19 (endless) → cooling (10分钟)

### 2. 当前可用Credentials

| ID | Label | Provider | 状态 | 最近表现 |
|----|-------|---------|------|---------|
| 8 | nvidia-build-new | NVIDIA | ✅ Ready | 最后失败在10:39，之后无请求 |
| 18 | nvidia-build-v2 | NVIDIA | ✅ Ready | 10:00后有成功记录 |

---

## 🎯 后续行动计划

### 立即行动 (接下来10分钟)

**1. 监控当前请求**
```bash
# 每30秒检查一次
watch -n 30 "ssh prod-app \"PGPASSWORD='...' psql ... -c '
SELECT COUNT(*) as total, COUNT(CASE WHEN NOT success THEN 1 END) as errors
FROM request_logs 
WHERE client_model LIKE '\''%minimax%'\'' AND ts > NOW() - INTERVAL '\''5 minutes'\'';
'\""
```

**2. 如果请求继续进来且失败**
- 说明流量路由到了credentials 8/18
- 观察这两个credential的表现
- 如果也高错误率，考虑完全暂停MiniMax服务

**3. 10分钟后重新评估**
- Credential 6和19将自动从cooling恢复
- 查看是否有新请求
- 检查错误率是否改善

### 短期行动 (接下来1小时)

**4. 深入调查MiniMax API状态**
```bash
# 手动测试MiniMax API
ssh prod-app "
# 使用真实API key测试
curl -X POST 'https://api.minimaxi.com/v1/chat/completions' \
  -H 'Authorization: Bearer <REAL_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{\"model\":\"MiniMax-M3\",\"messages\":[{\"role\":\"user\",\"content\":\"test\"}],\"max_tokens\":5}'
"
```

**5. 检查MiniMax官方状态页**
- 查看是否有服务公告
- 确认API是否在维护

**6. 联系MiniMax技术支持**
- 报告11:00后的大量失败
- 询问是否有已知问题
- 确认API配额状态

### 中期行动 (今天内)

**7. 实施智能熔断**
```sql
-- 创建函数：自动标记高错误率credentials
CREATE OR REPLACE FUNCTION auto_cool_high_error_credentials() 
RETURNS void AS $$
DECLARE
    cred RECORD;
    err_rate NUMERIC;
BEGIN
    FOR cred IN 
        SELECT c.id, c.label,
               COUNT(*) as total,
               COUNT(CASE WHEN NOT r.success THEN 1 END) as errors
        FROM credentials c
        JOIN request_logs r ON r.credential_id = c.id
        WHERE r.ts > NOW() - INTERVAL '10 minutes'
          AND c.availability_state = 'ready'
        GROUP BY c.id, c.label
        HAVING COUNT(*) >= 5  -- 至少5个请求
    LOOP
        err_rate := 100.0 * cred.errors / cred.total;
        
        IF err_rate >= 70 THEN
            UPDATE credentials 
            SET availability_state = 'cooling',
                cooling_until = NOW() + INTERVAL '5 minutes',
                state_reason_code = 'auto_circuit_breaker',
                state_reason_detail = format('Auto-disabled: %s%% error rate', err_rate)
            WHERE id = cred.id;
            
            RAISE NOTICE 'Auto-cooled credential % (%) due to %% error rate',
                cred.id, cred.label, err_rate;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 每分钟执行一次
SELECT cron.schedule('auto-circuit-breaker', '*/1 * * * *', 
    'SELECT auto_cool_high_error_credentials()');
```

**8. 增强错误日志**
- 修改代码记录upstream的原始响应
- 特别是`unknown`错误的详细信息
- 帮助未来诊断

---

## 📊 实时监控指标

### 关键查询

**1. 实时错误率**
```sql
SELECT 
    COUNT(*) as total,
    COUNT(CASE WHEN NOT success THEN 1 END) as errors,
    ROUND(100.0 * COUNT(CASE WHEN NOT success THEN 1 END) / COUNT(*), 2) as error_rate,
    MAX(ts) as last_request
FROM request_logs
WHERE client_model LIKE '%minimax%'
  AND ts > NOW() - INTERVAL '5 minutes';
```

**2. 各Credential表现**
```sql
SELECT 
    c.id,
    c.label,
    c.availability_state,
    COUNT(r.id) as requests,
    COUNT(CASE WHEN r.success THEN 1 END) as success,
    ROUND(100.0 * COUNT(CASE WHEN NOT r.success THEN 1 END) / COUNT(r.id), 2) as error_rate
FROM credentials c
LEFT JOIN request_logs r ON r.credential_id = c.id 
    AND r.ts > NOW() - INTERVAL '10 minutes'
    AND r.client_model LIKE '%minimax%'
WHERE c.id IN (6, 8, 18, 19)
GROUP BY c.id, c.label, c.availability_state;
```

**3. Cooling状态恢复倒计时**
```sql
SELECT 
    id,
    label,
    availability_state,
    cooling_until,
    CASE 
        WHEN cooling_until IS NOT NULL AND cooling_until > NOW() 
        THEN EXTRACT(EPOCH FROM (cooling_until - NOW()))::INTEGER || ' seconds'
        ELSE 'ready to recover'
    END as time_to_recover
FROM credentials
WHERE id IN (6, 8, 18, 19);
```

---

## 🔮 预测与建议

### 情景A: MiniMax API恢复 (最可能)
**预期**: 
- 10分钟后credentials 6和19自动恢复
- 新请求开始成功
- 错误率降至正常水平(<20%)

**建议**: 
- 继续监控30分钟
- 如果稳定，无需额外操作

### 情景B: MiniMax API持续故障
**预期**:
- 10分钟后请求继续失败
- 所有credentials都无法工作
- 错误率维持在80%+

**建议**:
- 立即禁用所有MiniMax路由
- 返回503错误给用户，说明服务暂时不可用
- 每10分钟重试一次
- 联系MiniMax技术支持

### 情景C: 部分Credential可用
**预期**:
- Credentials 8/18表现良好
- Credentials 6/19继续失败

**建议**:
- 保持6和19在cooling状态
- 将所有流量路由到8和18
- 每小时尝试恢复6和19一次

---

## 📋 时间线

| 时间 | 事件 | 错误率 | 操作 |
|------|------|--------|------|
| 08:00 | 正常运行 | 5.13% | ✅ 无 |
| 09:00 | 开始升高 | 25% | 🟡 观察 |
| 10:00 | 继续高位 | 22.73% | 🟡 观察 |
| 11:00 | **突然飙升** | 100% | 🔴 **故障开始** |
| 12:00 | 持续故障 | 90.48% | 🔴 持续 |
| 12:30 | 采取措施 | 88.89% | ✅ 禁用高失败率credentials |
| 12:40 | 等待评估 | ? | ⏳ 监控中 |

---

## 🎯 决策树

```
当前时间: 12:30
    │
    ├─ 12:40 检查点
    │   │
    │   ├─ 错误率 < 20%? 
    │   │   └─ YES → 恢复正常 ✅
    │   │   └─ NO → 继续观察
    │   │
    │   ├─ 12:50 检查点
    │   │   │
    │   │   ├─ 错误率 < 20%?
    │   │   │   └─ YES → 恢复正常 ✅
    │   │   │   └─ NO → 执行计划B
    │   │   │
    │   │   └─ 计划B: 禁用所有MiniMax
    │   │       - UPDATE credentials SET lifecycle_status = 'suspended' WHERE id IN (6,8,18,19)
    │   │       - 返回503错误
    │   │       - 每30分钟自动重试
    │   │
    │   └─ 13:00 如果仍未恢复
    │       └─ 联系MiniMax支持
    │       └─ 发布用户公告
    │
    └─ 持续监控
```

---

## 📞 紧急联系

**监控命令**:
```bash
# 持续监控
watch -n 30 'ssh prod-app "PGPASSWORD=... psql ... -c \"
SELECT 
    COUNT(*) as total,
    COUNT(CASE WHEN NOT success THEN 1 END) as errors,
    ROUND(100.0 * COUNT(CASE WHEN NOT success THEN 1 END) / COUNT(*), 2) as error_rate
FROM request_logs 
WHERE client_model LIKE '\''%minimax%'\'' AND ts > NOW() - INTERVAL '\''5 minutes'\'';
\""'
```

**手动恢复命令**:
```sql
-- 如果确认MiniMax API恢复，立即恢复credentials
UPDATE credentials 
SET availability_state = 'ready',
    cooling_until = NULL,
    state_reason_code = NULL,
    state_reason_detail = NULL
WHERE id IN (6, 19) AND availability_state = 'cooling';
```

**完全禁用命令**:
```sql
-- 如果确认MiniMax完全不可用
UPDATE credentials 
SET lifecycle_status = 'suspended',
    manual_disabled = true,
    notes = 'Suspended due to MiniMax API outage on 2026-06-30'
WHERE id IN (6, 8, 18, 19);
```

---

## 总结

**当前状态**: 🔴 紧急 - MiniMax服务大面积故障  
**根本原因**: MiniMax API从11:00开始出现问题（推测）  
**已采取措施**: 隔离高失败率credentials (6, 19)  
**下一步**: 监控10分钟，等待自动恢复或执行计划B  
**预期恢复时间**: 12:40 (如果API恢复) 或需要人工干预

---

**报告生成时间**: 2026-06-30 12:32 UTC  
**下次更新**: 2026-06-30 12:42 UTC (10分钟后)
