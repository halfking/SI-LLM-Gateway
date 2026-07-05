# MiniMax-M3 错误分析报告
**日期**: 2026-06-30  
**分析时间范围**: 最近24小时  
**测试环境**: llm.kxpms.cn (生产环境)

## 一、错误率总览

### 整体统计
- **总请求数**: 256
- **错误请求数**: 66
- **总体错误率**: 25.78%

这个错误率确实偏高，需要重点关注。

---

## 二、错误分类详细分析

### 2.1 按错误类型分布

| 错误类型 | 数量 | 占比 | 描述 |
|---------|------|------|------|
| transient (暂态错误) | 24 | 36.4% | 上游服务暂时性故障 |
| empty_response (空响应) | 14 | 21.2% | 收到3个chunk但内容为空 |
| unknown (未知错误) | 10 | 15.2% | 上游返回未知错误 |
| no_candidate (无候选) | 9 | 13.6% | 路由阶段未找到可用凭证 |
| canceled (取消) | 5 | 7.6% | 请求被取消 |
| provider_error (供应商错误) | 1 | 1.5% | MiniMax API错误 |
| rate_limit_exceeded (限流) | 1 | 1.5% | 超过速率限制 |
| 其他 | 2 | 3.0% | 未分类错误 |

### 2.2 按失败阶段分布

| 失败阶段 | 数量 | 平均延迟(ms) |
|---------|------|--------------|
| upstream (上游) | 25 | 2,511 |
| upstream_empty_response | 14 | 2,331 |
| upstream (unknown) | 10 | 557 |
| gateway (路由层) | 10 | 20 |

---

## 三、按凭证(Credential)分析

### 3.1 各凭证错误率对比

| Credential ID | 总请求 | 错误数 | 错误率 | 状态 |
|--------------|--------|--------|--------|------|
| NULL (无凭证) | 10 | 10 | 100.00% | ⚠️ **严重** |
| 18 | 21 | 12 | 57.14% | ⚠️ **高** |
| 19 | 17 | 6 | 35.29% | ⚠️ **中** |
| 6 | 192 | 37 | 19.27% | ✅ **可接受** |
| 8 | 21 | 3 | 14.29% | ✅ **良好** |

### 3.2 关键发现

#### 🔴 问题1: credential_id = NULL (10个请求，100%失败)
- **错误类型**: 
  - `no_candidate`: 9个 - 路由层未找到可用凭证
  - `rate_limit_exceeded`: 1个 - 超过限流
- **根本原因**: 路由配置问题，部分请求无法匹配到有效的凭证
- **建议**: 检查model_routes表中minimax-m3的路由规则

#### 🔴 问题2: credential_id = 18 (57.14%错误率)
- **主要错误**: `empty_response` (12个中的10个)
- **特征**:
  - 使用outbound_model: `minimaxai/minimax-m3`
  - 所有empty_response请求都收到了3个stream chunk
  - stream_done_received = true (完整接收)
  - 平均延迟: 1,000ms左右
  - response_body为空
- **根本原因**: 该凭证使用的是`minimaxai`前缀的模型路由，可能配置了错误的API base或协议转换有问题

#### 🟡 问题3: credential_id = 19 (35.29%错误率)
- 使用outbound_model: `minimaxai/minimax-m3`
- 存在similar issues as credential 18

#### ✅ 良好表现: credential_id = 6 (19.27%错误率)
- **特点**:
  - 使用outbound_model: `MiniMax-M3` (不带前缀)
  - 处理了最多的请求量(192个)
  - 虽然有37个错误，但主要是transient错误(暂态)
  - 错误率相对可接受

---

## 四、按Outbound Model分析

### 4.1 模型路由对比

| Outbound Model | 错误类型 | 错误数 | 平均延迟 |
|---------------|---------|-------|---------|
| `MiniMax-M3` | transient | 27 | 2,498ms |
| `MiniMax-M3` | unknown | 10 | 557ms |
| `minimaxai/minimax-m3` | **empty_response** | **14** | **2,331ms** |
| `minimaxai/minimax-m3` | canceled | 5 | 25,355ms |
| `minimaxai/minimax-m3` | provider_error | 1 | 120,104ms |

### 4.2 关键对比

**`MiniMax-M3` (credential 6,8使用)**
- ✅ 主要错误是transient，属于可恢复的暂态错误
- ✅ 大部分请求能正常完成
- ✅ 响应有实际内容

**`minimaxai/minimax-m3` (credential 18,19使用)**
- ❌ 主要错误是empty_response，流接收完整但内容为空
- ❌ 存在长时间超时(canceled, provider_error)
- ❌ 表明该路由配置存在严重问题

---

## 五、时间趋势分析

### 按小时错误率

| 时间段 | 总请求 | 错误数 | 错误率 |
|--------|--------|--------|--------|
| 2026-06-30 09:00 | 154 | 35 | 22.73% |
| 2026-06-30 08:00 | 39 | 2 | 5.13% ✅ |
| 2026-06-30 07:00 | 6 | 2 | 33.33% |
| 2026-06-30 06:00 | 15 | 10 | **66.67%** ⚠️ |
| 2026-06-30 05:00 | 21 | 1 | 4.76% ✅ |
| 2026-06-30 04:00 | 19 | 12 | **63.16%** ⚠️ |
| 2026-06-29 22:00 | 9 | 6 | **66.67%** ⚠️ |

**发现**: 
- 凌晨4点和6点错误率激增(60%+)
- 上午8点和凌晨5点表现良好(5%左右)
- 说明可能存在credential轮换或资源竞争问题

---

## 六、具体错误案例

### 案例1: empty_response错误
```
request_id: d18e50e9c9bb09ca82167ac74e0f4c2a
credential_id: 18
outbound_model: minimaxai/minimax-m3
stream_chunk_count: 3
stream_done_received: true
latency_ms: 1,537
response_body: (empty)
```

**分析**: 
- 流式传输看起来正常(接收到3个chunk，done信号正常)
- 但response_body为空，说明chunk解析或内容提取有问题
- 可能是该credential对应的API格式与预期不符

### 案例2: transient错误
```
credential_id: 6
outbound_model: MiniMax-M3
error_kind: transient
avg_latency: 2,498ms
```

**分析**:
- 延迟较长但在可接受范围
- 暂态错误通常是MiniMax服务端负载或网络抖动导致
- 需要重试机制来处理

---

## 七、根本原因总结

### 🔴 严重问题

1. **`minimaxai/minimax-m3` 路由配置错误**
   - credential 18和19使用此路由
   - 导致14个empty_response错误
   - 可能原因：
     - API base URL配置错误
     - 协议转换(litellm)配置问题
     - 该前缀对应的provider配置不正确

2. **路由匹配失败 (no_candidate)**
   - 10个请求无法找到可用凭证
   - 路由规则配置不完整

### 🟡 次要问题

3. **transient错误**
   - 27个暂态错误
   - 可能是MiniMax API服务端问题
   - 需要更好的重试策略

4. **unknown错误**
   - 10个未知错误
   - 需要增强错误日志记录，获取更详细的错误信息

---

## 八、修复建议

### 优先级1 (立即修复)

1. **检查credential 18和19的配置**
   ```sql
   SELECT id, provider_id, api_base, auth_type 
   FROM credentials 
   WHERE id IN (18, 19);
   ```
   - 验证API base URL是否正确
   - 检查是否应该使用`MiniMax-M3`而非`minimaxai/minimax-m3`

2. **修复路由匹配问题**
   ```sql
   SELECT * FROM model_routes 
   WHERE client_model LIKE '%minimax%';
   ```
   - 确保minimax-m3有完整的路由规则
   - 添加fallback路由避免no_candidate错误

3. **暂时禁用问题凭证**
   - 考虑暂时禁用credential 18和19
   - 将流量路由到表现良好的credential 6和8

### 优先级2 (短期优化)

4. **增强错误日志**
   - 记录更详细的upstream响应内容
   - 特别是empty_response情况下的原始chunk内容

5. **改进重试策略**
   - 对transient错误自动重试
   - 使用不同的credential重试

6. **添加健康检查**
   - 实时监控各credential的成功率
   - 自动将高错误率的credential降级

### 优先级3 (长期改进)

7. **负载均衡优化**
   - credential 6承载了75%的流量
   - 需要更均衡的流量分配

8. **告警机制**
   - 错误率超过20%时告警
   - 特定时段(凌晨4-6点)错误率监控

---

## 九、下一步行动

### 立即行动
1. [ ] 查询credential 18和19的详细配置
2. [ ] 检查`minimaxai/minimax-m3`与`MiniMax-M3`的路由差异
3. [ ] 检查model_routes表，确认minimax-m3的路由规则
4. [ ] 查看应用日志中empty_response错误的详细信息

### 监控
1. [ ] 持续监控各credential的错误率
2. [ ] 观察不同时段的错误率变化
3. [ ] 记录修复后的效果

### 验证
1. [ ] 修复后进行端到端测试
2. [ ] 目标：将错误率降至10%以下
3. [ ] 确保所有请求都能找到有效凭证

---

## 十、附录：查询语句

### 查看实时错误率
```sql
SELECT 
  COUNT(*) as total,
  COUNT(CASE WHEN NOT success THEN 1 END) as errors,
  ROUND(100.0 * COUNT(CASE WHEN NOT success THEN 1 END) / COUNT(*), 2) as error_rate
FROM request_logs 
WHERE client_model LIKE '%minimax%' 
  AND ts > NOW() - INTERVAL '1 hour';
```

### 查看各credential表现
```sql
SELECT 
  credential_id,
  COUNT(*) as total,
  COUNT(CASE WHEN success THEN 1 END) as success,
  COUNT(CASE WHEN NOT success THEN 1 END) as errors,
  ROUND(100.0 * COUNT(CASE WHEN NOT success THEN 1 END) / COUNT(*), 2) as error_rate
FROM request_logs 
WHERE client_model LIKE '%minimax%' 
  AND ts > NOW() - INTERVAL '1 hour'
GROUP BY credential_id
ORDER BY error_rate DESC;
```

### 查看具体错误详情
```sql
SELECT 
  request_id, credential_id, outbound_model, 
  error_kind, latency_ms, stream_chunk_count, 
  response_preview
FROM request_logs 
WHERE client_model LIKE '%minimax%' 
  AND NOT success 
  AND ts > NOW() - INTERVAL '1 hour'
ORDER BY ts DESC 
LIMIT 20;
```
