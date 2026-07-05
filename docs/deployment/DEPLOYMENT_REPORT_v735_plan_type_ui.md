# plan_type UI 部署报告 - 71 服务器 (v735)

**部署时间**: 2026-07-03 00:50 CST
**部署版本**: 2.3.3-c6bb0b59-20260702-735 (build_seq=735)
**目标服务器**: <prod-server-ip>:25022
**部署状态**: ✅ 成功
**关联事件**: v734 plan_incompatible 后续产品化（运维可观察可配置 plan_type）

---

## 背景

v734 修复（commit d2a3d7a5）解决了 `v_routable_credential_models` 视图的 plan_incompatible 规则触发问题——但运维只能通过 SQL 设置 `credentials.plan_type`，没有 UI 入口。

v735 把 plan_type 接入 `/providers/{id}` 凭据管理页面，从此：
- 路由适配通过 `credentials.plan_type`（凭据级）在 UI 可见可改
- `/pricing` 继续独立管理 `model_offers` 上每模型的价格（unit_price_in_per_1m 等）
- 两个职责清晰解耦

## 改动总览

| 文件 | 变更类型 | 简介 |
|---|---|---|
| `admin/provider_credential.go` | 改 | `listCredentials` SELECT/struct 加 `plan_type`；`updateCredential` 加 PATCH `plan_type` 分支（带 cmb 派生 + candCache 失效） |
| `admin/provider_credential_plan_type_test.go` | 新 | 5 个单元测试覆盖 allow-list、invalid 拒绝、empty/null 路径 |
| `web/src/api/providers.ts` | 改 | `ProviderCredential` 接口加 `plan_type?`；`updateCredential` 签名加 `plan_type` |
| `web/src/views/provider-detail/CredsTab.vue` | 改 | drawer 加 plan_type select + `setPlanType` handler（仿 `setLifecycle` 立即 PATCH）|
| `web/src/i18n/locales/{8 lang}/providerDetail.ts` | 改 | 11 个新键，8 种语言（zh-CN / zh-TW / ja-JP / de-DE / fr-FR / es-ES / ar-SA / en-US）|

## 后端契约

### GET /api/providers/{id}/credentials

每个 credential JSON 现在多了：
```json
{
  "id": 6,
  "label": "minimax-prod-1",
  "plan_type": "token_plan",  // ← v735 新字段
  ...
}
```

`null` 表示凭据从未设置过 plan_type，按 SQL CHECK 约束处理。

### PATCH /api/providers/{id}/credentials/{cid}

请求体新增字段：
```json
{ "plan_type": "token_plan" }   // 设置为 token_plan
{ "plan_type": "" }              // 清空（DB NULL）
{ "plan_type": null }            // 等价于空字符串
```

合法值（来自 `credentials.plan_type` CHECK 约束）：

| 值 | 含义 |
|---|---|
| `token` | 按量计费（默认）|
| `token_plan` | token 订阅套餐（minimax-prod-1 用的）|
| `code_plan` | 代码套餐 |
| `agent_plan` | Agent 套餐 |
| `request` | 按请求 |
| `seat` | 按席位 |
| `compute_time` | 按算力 |
| `flat_quota` | 固定配额 |
| `free` | 免费 |
| `""` / `null` | 清空（DB NULL）|

非法值（如 `hacker_plan`）→ 400 响应 `{"error":{"detail":"invalid plan_type '...'; expected one of ..."}}`。

### 副作用：cmb 派生 + candCache 失效

当 PATCH 包含 `plan_type` 时（且非空），handler 会：

```sql
-- 1) 写 credentials
UPDATE credentials SET plan_type = $1, updated_at = now() WHERE id = $2 AND provider_id = $3;

-- 2) 派生所有 cmb.billing_mode = 新 plan_type
UPDATE credential_model_bindings
SET billing_mode = $1, updated_at = now()
WHERE credential_id = $2 AND billing_mode <> $1;

-- 3) handler 末尾原有的 provider.InvalidateAllCandidateCache()
--    → candCache 30s → 5s（v733 修复）→ 同步（v735 NOTIFY listener）
```

如果 PATCH 不含 `plan_type` 字段，整个分支不执行（保持现有 patch-idempotency 语义）。

## 端到端验证（71 上 SQL 模拟，BEGIN/ROLLBACK）

| 操作 | 结果 |
|---|---|
| BEFORE | cred 6 / `token_plan` / cmb `token_plan` / `is_routable=t` |
| PATCH `plan_type=token` | 1 行 creds + 11 行 cmb 更新；`is_routable=t` |
| PATCH `plan_type=''` (clear) | 1 行 creds 改 NULL；cmb 保持 `token_plan`（**不**重派生）|
| PATCH `plan_type=token_plan` | 1 行 creds + 0 行 cmb（已是 token_plan）；`is_routable=t` |

## UI 位置

- 入口：左侧导航 → Providers → 选 provider 14 → "凭据" 子标签 → 凭据行点击打开 drawer
- Drawer 位置：状态（status / lifecycle_status）之下，手工禁用复选框之上
- UI 控件：标准 `<select>`，10 个选项（含"未设置"），改完立即 PATCH（不需点 Save 按钮）
- hint 文本：明示"cmb.billing_mode 将自动从此派生"（`planTypeHint` i18n key）

## 部署验证

```bash
$ curl -sf http://localhost:8781/healthz
{"status":"ok","version":"2.3.3-c6bb0b59-20260702-735",...}

$ ps -o pid,etime,cmd -p $(pgrep -f llm-gateway-go.v321 | head -1)
PID     ELAPSED CMD
3512171 01:30 /usr/bin/docker ... llm-gateway-go
```

## 单元测试

```text
=== RUN   TestUpdateCredentialBody_ParsesPlanType           PASS
=== RUN   TestUpdateCredentialBody_AcceptsNullPlanType       PASS
=== RUN   TestUpdateCredentialHandler_RejectsInvalidPlanType PASS
=== RUN   TestUpdateCredentialHandler_AbsentPlanType         PASS
=== RUN   TestPlanType_AllowList
    --- PASS: TestPlanType_AllowList/deny_hacker
    --- PASS: TestPlanType_AllowList/deny_token-plan-typo
    --- PASS: TestPlanType_AllowList/deny_TOKEN_PLAN
    --- PASS: TestPlanType_AllowList/deny_0
    --- PASS: TestPlanType_AllowList/deny_drop_table
    --- PASS: TestPlanType_AllowList/allow_token
    --- PASS: TestPlanType_AllowList/allow_token_plan
    --- PASS: TestPlanType_AllowList/allow_code_plan
    --- PASS: TestPlanType_AllowList/allow_agent_plan
    --- PASS: TestPlanType_AllowList/allow_request
    --- PASS: TestPlanType_AllowList/allow_seat
    --- PASS: TestPlanType_AllowList/allow_compute_time
    --- PASS: TestPlanType_AllowList/allow_flat_quota
    --- PASS: TestPlanType_AllowList/allow_free
    --- PASS: TestPlanType_AllowList/allow_   (empty → NULL)
PASS
ok      github.com/kaixuan/llm-gateway-go/admin
```

## Git 提交链

```
b1b117a0 chore: bump version to 2.3.3-c6bb0b59-20260702-735
c6bb0b59 feat(admin+web): plan_type UI on /providers/{id} credential drawer
be29f726 docs: cmb.billing_mode plan_incompatible fix deployment report v734
28dd7671 chore: bump version to 2.3.3-d2a3d7a5-20260702-734
d2a3d7a5 fix(modelcatalog): derive cmb.billing_mode from credentials.plan_type on upsert
```

## 业务价值

| 之前 | 现在 |
|---|---|
| plan_type 只能通过 SQL 修改 | UI drawer 一键改 |
| 修改后需手工跑 fix SQL 重派生 cmb | handler 自动重派生 |
| 路由变更延迟：~30s（candCache TTL）| < 100ms（NOTIFY 同步）|
| /pricing 混了路由和价格两个职责 | /pricing 只管价格，路由在 /providers/{id} |
| 路由问题排查需看 SQL | 运维可在 UI 直接看 plan_type 与 billing_mode 状态 |

## 不在本次范围

- `/providers` 列表页 (ProvidersView.vue) 加 plan_type 列（仅详情 drawer 已有，列表暂不动）
- 给 `/pricing` 加"只读"banner（用户已选择不动 /pricing）
- plan_type audit log（下次迭代）
- `/admin/routing/resolve` 把 plan_type 加入响应（route 端不需要）

## 监控

部署后观察：

```sql
-- 1. plan_type 分布
SELECT plan_type, count(*) FROM credentials GROUP BY plan_type ORDER BY 1;

-- 2. plan_type 异常 NULL 的凭据（可能漏配）
SELECT id, label, provider_id, plan_type
FROM credentials
WHERE plan_type IS NULL
  AND lifecycle_status = 'active'
  AND status = 'active';

-- 3. plan_type 与 cmb.billing_mode 不一致（漏派生或重派生失败）
SELECT c.id, c.label, c.plan_type, count(*) FILTER (WHERE cmb.billing_mode <> c.plan_type) AS mismatched
FROM credentials c
JOIN credential_model_bindings cmb ON cmb.credential_id = c.id
WHERE c.plan_type IN ('token_plan','code_plan','agent_plan')
GROUP BY c.id, c.label, c.plan_type
HAVING count(*) FILTER (WHERE cmb.billing_mode <> c.plan_type) > 0;
```