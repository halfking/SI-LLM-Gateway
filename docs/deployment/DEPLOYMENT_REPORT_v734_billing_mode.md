# cmb.billing_mode plan_incompatible 修复 - 71 服务器 (v734)

**部署时间**: 2026-07-03 00:30 CST
**部署版本**: 2.3.3-d2a3d7a5-20260702-734 (build_seq=734)
**目标服务器**: <prod-server-ip>:25022
**部署状态**: ✅ 成功
**关联事件**: request a69a71a05e6610adcf55df32f2618797（minimax-m3 路由不可用）

---

## 背景

v733 部署的 candCache 失效修复（commit 45f4d791）解决了状态传播延迟问题，但是把 cmb.available 翻回 TRUE 后，另一个隐藏 bug 暴露：

**`v_routable_credential_models.is_routable = FALSE`，`unavailable_reason = 'plan_incompatible_model_requires_per_token'`**

用户的凭据（cred 6 / minimax-prod-1）状态完全健康：
- `availability_state = ready`
- `health_status = healthy`
- `manual_disabled = false`
- `quota_state = ok`

但 SQL `v_routable_credential_models` 视图的 rule 8 仍然把它的模型全部判为不可路由。

---

## 根因

`v_routable_credential_models` 视图有一条契约：

```sql
WHEN ((c.plan_type = ANY (ARRAY['token_plan', 'code_plan', 'agent_plan']))
      AND (mo.billing_mode <> ALL (ARRAY['token_plan', 'code_plan', 'agent_plan'])))
THEN false
```

即：credential 是订阅套餐 (`token_plan`/`code_plan`/`agent_plan`) 时，模型 offer 的 `billing_mode` 必须也在该集合里，否则视图判不可路由。

但是：

1. `cmb.billing_mode` 列默认值为 `per_token`（见 `deploy/sql/objects/tables/public.credential_model_bindings.sql:26`）
2. `modelcatalog.UpsertCredentialModel` 写新 cmb 行时**没有指定** `billing_mode`，全部走列默认 → `per_token`
3. `2026-06-12-cny-fix-all-credentials.sql` 脚本把 `per_token` 改成 `token`（不是 `token_plan`），治标不治本
4. 后来 `credentials.plan_type` 被改为 `token_plan`，但 cmb 的 `billing_mode` 没跟着改 → 触发 plan_incompatible

**SQL 模拟 GetCandidates 验证：**

修复前：
```
 credential_id | label | raw_model_name | available | is_routable | unavailable_reason
             6 | minimax-prod-1 | MiniMax-M3 | t | f | plan_incompatible_model_requires_per_token
```

修复后：
```
 credential_id | label | raw_model_name | available | is_routable | unavailable_reason
             6 | minimax-prod-1 | MiniMax-M3 | t | t | (空)
```

---

## 影响范围（不止 cred 6）

```
 plan_type  | current_billing_mode | row_count
------------+----------------------+-----------
 token_plan | per_token            |       155
 token_plan | token                |       255
```

**410 行 cmb 全部受影响**，涵盖所有 `plan_type=token_plan` 的凭据（minimax-prod-1, scnet-acrbo3aajx 等）。

---

## 修复内容

### 1. 数据修复 (一次性 SQL 迁移)

文件：`deploy/sql/docs/pricing/2026-07-03-fix-cmb-billing-mode-for-plan-creds.sql`

在 71 上执行：

```sql
UPDATE credential_model_bindings cmb
SET billing_mode = 'token_plan', updated_at = now()
FROM credentials c
WHERE cmb.credential_id = c.id
  AND c.tenant_id = 'default'
  AND c.plan_type = 'token_plan'
  AND cmb.billing_mode <> 'token_plan';
-- ... 类似 code_plan / agent_plan
```

执行结果：
- 410 行受影响
- `token_plan_cmb_total = 545`, `correct = 545`, `still_wrong = 0`
- 验证：cred 6 / MiniMax-M3 现在 `is_routable = t, unavailable_reason = (空)`

### 2. 代码修复 (回归防御)

`modelcatalog.UpsertCredentialModel` 的 INSERT 现在从 `credentials.plan_type` 派生 `billing_mode`：

```sql
CASE cred.plan_type
    WHEN 'token_plan' THEN 'token_plan'
    WHEN 'code_plan'  THEN 'code_plan'
    WHEN 'agent_plan' THEN 'agent_plan'
    ELSE 'token'
END
```

这样**未来** discovery 发现新模型时，cmb 行会带着正确的 `billing_mode` 进来，不会再触发 plan_incompatible。

UPDATE 分支**不**碰 `billing_mode` —— admin/pricing 路径可以单独覆盖，一次性 fix SQL 也不被覆写。

### 3. 测试

新加 `TestUpsertCredentialModelSQL_DerivesBillingMode`（静态 SQL 字符串断言），覆盖：

- 4 种 plan_type → billing_mode 映射都出现在 SQL 里
- SQL 里**不**硬编码 `billing_mode = 'per_token'`

---

## Git 提交链

```
28dd7671 chore: bump version to 2.3.3-d2a3d7a5-20260702-734
d2a3d7a5 fix(modelcatalog): derive cmb.billing_mode from credentials.plan_type on upsert
699e6482 docs: candCache staleness fix deployment report v733
33048876 chore: bump version to 2.3.3-45f4d791-20260702-733
45f4d791 fix(routing): close candCache staleness gap on credential state changes
```

---

## 部署验证

### 健康检查
```
$ curl -sf http://localhost:8781/healthz
{"status":"ok","version":"2.3.3-d2a3d7a5-20260702-734",...}

$ ps -o pid,etime,cmd -p $(pgrep -f llm-gateway-go.v321 | head -1)
    PID     ELAPSED CMD
3473147       00:18 docker run llm-gateway-go ...
```

### SQL 层验证（修复后）
```
 cred_id | label | raw_model_name | available | is_routable | unavailable_reason
       6 | minimax-prod-1 | MiniMax-M3 | t | t | (空)
      14 | scnet-acrbo3aajx | MiniMax-M3 | t | t | (空)
```

`v_routable_credential_models` 现在对这两个凭据返回 TRUE。

### End-to-end 测试
请求 `minimax-m3` 模型时，`GetCandidates` 现在返回 cred 6 和 cred 14 作为候选（SQL 模拟验证 8 行候选）。

---

## 监控与回归告警

部署后观察：

```bash
# 1. 路由层能否成功选到 cred 6 / cred 14 (request_logs)
psql $DB_DSN -c "
SELECT credential_id, success, error_kind, count(*)
FROM request_logs
WHERE ts > now() - INTERVAL '1 hour'
  AND credential_id IN (6, 14)
  AND (outbound_model = 'MiniMax-M3' OR client_model = 'MiniMax-M3')
GROUP BY credential_id, success, error_kind;
"

# 2. 是否再有新的 token_plan cmb 行带着错误的 billing_mode（应该 0）
psql $DB_DSN -c "
SELECT count(*)
FROM credential_model_bindings cmb
JOIN credentials c ON c.id = cmb.credential_id
WHERE c.plan_type IN ('token_plan','code_plan','agent_plan')
  AND cmb.billing_mode NOT IN ('token_plan','code_plan','agent_plan');
"
```

---

## 复盘

为什么 v733 没发现这个 bug？

- v733 之前 `cmb.available = FALSE` 在视图的更早分支 (`WHEN cmb.available IS NOT TRUE`) 触发，掩埋了 plan_incompatible 规则
- v733 的修复让 `cmb.available` 翻回 TRUE，plan_incompatible 规则就跳出来
- 这种"埋藏 bug"在路由/可用性逻辑里很常见：上游的 deny rule 把下游 deny rule 的诊断信息遮蔽了

建议未来路由诊断工具：

1. 优先报告**最后**匹配的 unavailable_reason（最具体的）
2. 或在视图里按严重度排序所有 deny 原因，不只返回第一个