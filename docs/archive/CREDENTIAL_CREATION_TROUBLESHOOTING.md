# 凭据创建失败排查清单

## 问题现象
- POST `/api/providers/24/credentials` 返回 500 错误
- 错误信息：`duplicate key value violates unique constraint "credentials_pkey"`

## 可能的原因和解决方案

### 1. 序列不同步（最常见）⭐

**症状**：
```
ERROR: duplicate key value violates unique constraint "credentials_pkey" (SQLSTATE 23505)
```

**原因**：数据库序列 `credentials_id_seq` 的值小于表中已存在的最大 ID

**快速修复**：
```sql
SELECT setval('credentials_id_seq', COALESCE((SELECT MAX(id) FROM credentials), 1), true);
```

**验证**：
```sql
SELECT 
    last_value as 序列值,
    (SELECT MAX(id) FROM credentials) as 表最大ID
FROM credentials_id_seq;
-- 序列值应该 >= 表最大ID
```

---

### 2. Label 重复

**症状**：
```
ERROR: duplicate key value violates unique constraint "credentials_unique_provider_label"
```

**原因**：尝试在同一 provider 和 tenant 下创建相同 label 的凭据

**约束定义**：
```sql
UNIQUE (provider_id, tenant_id, label)
```

**检查是否重复**：
```sql
SELECT id, provider_id, tenant_id, label, status
FROM credentials
WHERE provider_id = 24 
  AND tenant_id = 'default'  -- 默认值
  AND label = 'default';      -- 你要添加的 label
```

**解决方案**：
- 使用不同的 label 名称
- 或删除/禁用旧凭据：`UPDATE credentials SET status = 'disabled' WHERE id = xxx`

---

### 3. Provider 不存在

**症状**：可能返回 404 或其他错误

**检查**：
```sql
SELECT id, name, provider_type, base_url 
FROM providers 
WHERE id = 24;
```

**解决方案**：使用正确的 provider_id

---

### 4. Base URL 错误（导致探活失败）

**症状**：
- 凭据创建成功，但 `health_status = 'unreachable'`
- 日志显示：`used manifest fallback (3 models)`

**检查**：
```sql
SELECT id, name, base_url, provider_type 
FROM providers 
WHERE id = 24;
```

**修复**：
```sql
UPDATE providers 
SET base_url = 'https://正确的.api.url' 
WHERE id = 24;
```

**注意**：base_url 错误不会阻止凭据创建，只会影响健康检查

---

### 5. fp_slot_limit 约束冲突

**症状**：
```
ERROR: new row violates check constraint "credentials_fp_slot_vs_concurrency"
```

**原因**：`fp_slot_limit > concurrency_limit`

**约束定义**：
```sql
CHECK (fp_slot_limit IS NULL OR concurrency_limit IS NULL OR fp_slot_limit <= concurrency_limit)
```

**解决方案**：
- 不指定 `fp_slot_limit`（推荐，会自动计算）
- 或确保 `fp_slot_limit <= concurrency_limit`

---

## 完整诊断流程

### 在 71 服务器上执行

```bash
# 1. 使用自动诊断脚本（推荐）
cd /path/to/llm-gateway-go-2
./scripts/diagnose_and_fix_credentials.sh

# 2. 或手动执行 SQL 诊断
psql -h localhost -U postgres -d llm_gateway -f scripts/diagnose_credential_creation.sql

# 3. 或快速修复序列（最常见问题）
psql -h localhost -U postgres -d llm_gateway -c \
  "SELECT setval('credentials_id_seq', COALESCE((SELECT MAX(id) FROM credentials), 1), true);"
```

---

## 添加凭据的正确方式

### 通过 API（推荐）

```bash
curl -X POST https://llm.kxpms.cn/api/providers/24/credentials \
  -H "Content-Type: application/json" \
  -d '{
    "api_key": "sk-4yvbe7jBk16mXLc4xEKiLushtRlQmnxK",
    "label": "my-credential-name",
    "concurrency_limit": 10
  }'
```

### 参数说明

- `api_key`：必填，凭据密钥
- `label`：可选，默认 "default"（注意不要重复）
- `concurrency_limit`：可选，默认 10
- `fp_slot_limit`：可选，不指定时自动计算为 `max(1, concurrency_limit/4)`

### 避免的错误

❌ **不要使用重复的 label**
```json
{"label": "default"}  // 如果已存在会失败
```

✅ **使用唯一的 label**
```json
{"label": "credential-2024-07-02"}
{"label": "prod-key-1"}
```

❌ **不要让 fp_slot_limit > concurrency_limit**
```json
{
  "concurrency_limit": 5,
  "fp_slot_limit": 10  // 会失败！
}
```

✅ **省略 fp_slot_limit 让系统自动计算**
```json
{
  "concurrency_limit": 10
  // fp_slot_limit 会自动设为 2 或 3
}
```

---

## 验证凭据创建成功

### 1. 检查 HTTP 响应
```json
{
  "id": 123,
  "message": "ok"
}
```

### 2. 查询数据库
```sql
SELECT 
    id,
    label,
    status,
    health_status,
    concurrency_limit,
    fp_slot_limit,
    created_at
FROM credentials
WHERE provider_id = 24
ORDER BY id DESC
LIMIT 5;
```

### 3. 查看健康状态
```sql
SELECT 
    id,
    label,
    health_status,
    health_error,
    api_models_error
FROM credentials
WHERE id = {刚创建的ID};
```

---

## 修复探活失败

如果凭据创建成功但健康检查失败：

### 1. 修正 Provider 的 base_url
```sql
UPDATE providers 
SET base_url = 'https://correct-api-url.com' 
WHERE id = 24;
```

### 2. 手动触发健康检查
```bash
curl -X POST https://llm.kxpms.cn/api/providers/24/credentials/{cred_id}/check-health
```

### 3. 查看检查结果
```bash
curl https://llm.kxpms.cn/api/providers/24/credentials/{cred_id}/check-health
```

---

## 常见问题 FAQ

**Q: 为什么会出现序列不同步？**
A: 通常是因为数据库备份恢复、手动插入指定 ID 的记录，或从其他数据库迁移数据时序列没有同步更新。

**Q: 修复序列会影响现有数据吗？**
A: 不会。修复序列只是更新下一个要使用的 ID 值，不会修改任何现有记录。

**Q: 探活失败会阻止凭据创建吗？**
A: 不会。探活是异步执行的（fire-and-forget goroutine），不会影响凭据创建本身。

**Q: 如何批量导入凭据？**
A: 建议通过 API 逐个添加，或使用脚本循环调用 API。避免直接 INSERT 到数据库以防止序列不同步。

---

## 相关文件

- 诊断脚本：`scripts/diagnose_and_fix_credentials.sh`
- SQL 诊断：`scripts/diagnose_credential_creation.sql`
- 序列修复：`scripts/fix_credentials_sequence.sh`
- 代码实现：`admin/provider_credential.go:37-107`
- 表结构：`deploy/sql/00_schema/003_routing_tables.sql:12-92`

---

**最后更新**: 2026-07-02
