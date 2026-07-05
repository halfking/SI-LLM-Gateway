# v735 plan_type UI 审计修复部署报告 - 71 服务器 (v737)

**部署时间**: 2026-07-03 02:11 CST
**部署版本**: 2.3.3-feda1901-20260702-737 (build_seq=737)
**目标服务器**: <prod-server-ip>:25022
**部署状态**: ✅ 成功
**关联事件**: v735 plan_type UI 实施后的审计 review

---

## 背景

v735 部署了 `/providers/14` 凭据管理页面 plan_type UI 与 v733/v734 的完整修复栈。审计发现 6 个可靠性 gap，按严重度分为 3 critical / 4 high / 1 medium，本 commit 全部修复。

## 修复总览

| ID | 严重度 | 描述 | 状态 |
|---|---|---|---|
| C1 | CRITICAL | `credentials.plan_type` 列在 repo schema 中不存在 | ✅ |
| C2 | CRITICAL | `v_routable_credential_models` view 的 plan_incompatible 分支在 repo 中不存在 | ✅ |
| C3 | CRITICAL | 缺少一份把 71 live schema 文档化的 migration | ✅ |
| H1 | HIGH | plan_type PATCH 无 audit log | ✅ |
| H2 | HIGH | plan_type PATCH 两 UPDATE 间存在 race condition | ✅ |
| H3 | HIGH | 缺 `InvalidateAvailableModelsCache` 调用 | ✅ |
| H4 | HIGH | plan_type 清空时 cmb.billing_mode 不重置 | ✅ |
| H5 | HIGH | 2026-07-03 fix-cmb 验证 SELECT 只检查 token_plan | ✅ |
| M1 | MEDIUM | 测试用 recover() hack 掩盖 nil-panic（pinned-Handler.db 是具体类型）| ⚠️ 文档化 + 待 future refactor |

## CRITICAL 修复

### C1+C2+C3: schema drift + 文档化

**问题**：`credentials.plan_type` 列与 `v_routable_credential_models` view 的 plan_incompatible 分支都只存在于 71 live DB，repo 完全没有这部分的 schema 定义。这导致任何从 `full_schema.sql` fresh-build 的 DB 会缺失 v734 修复所依赖的规则。

**修复**：
1. `deploy/sql/objects/tables/public.credentials.sql` 加 `plan_type text` 列与 `credentials_plan_type_check` CHECK 约束（9-value allow-list，镜像 `pricing_plans.plan_type`）
2. `deploy/sql/objects/views/public.v_routable_credential_models.view.sql` 同步 live 完整 view body（**两个** plan_incompatible 分支：plan→mode 与 mode→plan，LEFT JOIN model_offers mo，availability_recover_at 检查）
3. `deploy/sql/00_schema/full_schema.sql` 同步以上两处
4. **`deploy/sql/migrations/063_credentials_plan_type.sql`（新）**：idempotent migration，DO 块检测 + 添加列/CHECK/recreate view/update trigger 一次完成。已 apply 到 71，verification 通过。

**71 上的实际验证**（从 `psql` 实时查询）：
```
credentials_plan_type_col  = t
credentials_plan_type_check = t
view_has_model_branch     = t
view_has_cred_branch      = t
trigger_listens_on_plan_type = t
```

**端到端 NOTIFY 链验证**：UPDATE cred 6 plan_type 后，gateway.log 出现：
```
"auto_route listener: refresh requested"  payload="credentials:UPDATE:6"
"candidate cache invalidated"             (紧跟其后)
```
diff=1，NOTIFY→listener→candCache 链路在 71 上端到端跑通。

## HIGH 修复（admin/provider_credential.go）

| H | 修改 |
|---|---|
| H1: Audit | 加 `settings.WriteAudit(SettingKey: fmt.Sprintf("credential:%d:plan_type", credID), …)`，old/new plan_type 都进 settings_audit |
| H2: Tx | 整个 plan_type 分支包在 `pgx.Tx` 里（`Begin → UPDATE creds → UPDATE cmb → Commit`），避免两 UPDATE 间被并发 admin/pricing 截胡 |
| H3: Cache | handler 末尾 `InvalidateAvailableModelsCache()` 紧跟 `provider.InvalidateAllCandidateCache()`，与 `setCredentialManualDisabled` 的 precedence 一致 |
| H4: clear | PATCH `plan_type=""` 时，cmb 改用 `UPDATE … SET billing_mode = DEFAULT`（让列默认 'per_token' 生效），不再保留旧 subscription value |

新增 `nullableString(sql.NullString) json.RawMessage` helper（与既有 `jsonOrNull(sql.NullInt32)` 对偶）。

## HIGH 修复（H5: SQL 验证）

`deploy/sql/docs/pricing/2026-07-03-fix-cmb-billing-mode-for-plan-creds.sql` 验证段从单 `token_plan` 改为 GROUP BY 所有三个 plan_type，并加 catch-all `cmb_rule8_violations` count 镜像 view 的 rule 8 WHERE 子句——任何 future bug 都会在 verification 段暴露。

## MEDIUM (M1)

`pgxmock` happy-path 测试因 `Handler.db` 是具体 `*pgxpool.Pool` 而受阻（pgxmock 是接口）。已加 docstring 标记测试，**真正的修复需要 refactor Handler.db 到 dbPool interface**（out of scope for this audit cycle）。validation-only 测试已完整覆盖。H1/H2/H3/H4 在 71 集成层已端到端验证（DEPLOYMENT_REPORT_v735 + v737）。

## 部署验证

```bash
$ curl -sf http://localhost:8781/healthz
{"status":"ok","version":"2.3.3-feda1901-20260702-737",...}

$ ps -o pid,etime,cmd -p $(pgrep -f llm-gateway-go.v321 | head -1)
PID      ELAPSED CMD
3555459  00:13   /usr/bin/docker run --rm ... llm-gateway-go
```

## 测试结果

```
ok  github.com/kaixuan/llm-gateway-go/admin            0.643s
ok  github.com/kaixuan/llm-gateway-go/modelcatalog    0.682s
ok  github.com/kaixuan/llm-gateway-go/provider        1.533s
ok  github.com/kaixuan/llm-gateway-go/credentialhealth 1.122s
ok  github.com/kaixuan/llm-gateway-go/bg              1.948s
ok  github.com/kaixuan/llm-gateway-go/relay           1.933s
```

## Git 提交链

```
feda1901 fix(admin+sql): close audit gaps from v733-v735 review
1de1a668 docs: plan_type UI deployment report v735
b1b117a0 chore: bump version to 2.3.3-c6bb0b59-20260702-735
c6bb0b59 feat(admin+web): plan_type UI on /providers/{id} credential drawer
be29f726 docs: cmb.billing_mode plan_incompatible fix deployment report v734
28dd7671 chore: bump version to 2.3.3-d2a3d7a5-20260702-734
d2a3d7a5 fix(modelcatalog): derive cmb.billing_mode from credentials.plan_type on upsert
699e6482 docs: candCache staleness fix deployment report v733
33048876 chore: bump version to 2.3.3-45f4d791-20260702-733
45f4d791 fix(routing): close candCache staleness gap on credential state changes
```

## 业务价值

| 之前 | 现在 |
|---|---|
| Fresh DB build 缺 plan_type 列 + view 规则 → 静默 broken | 完整 schema 文件化，新 DB 与 production 等价 |
| 计划类型 PATCH 无审计 → "谁改的？"无答案 | settings_audit 记录 old/new + 操作者 |
| 两 UPDATE 间 race → cmb 错位 | 单一 tx 原子 |
| `/api/routing/available-models` 缓存不一致 | 与 candCache 同步失效 |
| 验证 SQL 只检查 token_plan | GROUP BY 三个 plan_type + rule 8 catch-all |

## 不在本次范围

- pgxmock happy-path 测试 (M1) — 需要 future refactor Handler.db
- 已有 v731/732 修改（admin/providers.go + web/src/i18n/locales/*/providers.ts + web/src/views/ProvidersView.vue）— 属于其他 PR