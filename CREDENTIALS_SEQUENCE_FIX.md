# Credentials 序列不同步问题修复报告

## 问题描述

在向 `https://llm.kxpms.cn/api/providers/24/credentials` 添加新凭据时出现错误：

```
create failed: ERROR: duplicate key value violates unique constraint "credentials_pkey" (SQLSTATE 23505)
POST https://llm.kxpms.cn/api/providers/24/credentials 500 (Internal Server Error)
```

## 根本原因

PostgreSQL 序列 `credentials_id_seq` 与 `credentials` 表中的实际最大 ID 值不同步。

这通常发生在以下情况：
1. 数据库恢复/导入时，数据被导入但序列没有正确重置
2. 曾经手动插入过指定 ID 的记录
3. 多个数据库实例之间的数据同步问题

### 技术细节

- `credentials` 表的 `id` 字段使用 `credentials_id_seq` 序列自动生成
- 代码中的 INSERT 语句不指定 ID，依赖序列自动递增：
  ```sql
  INSERT INTO credentials (provider_id, label, secret_ciphertext, status, ...)
  VALUES ($1, $2, $3, 'active', ...)
  RETURNING id
  ```
- 当序列值 ≤ 表中已存在的最大 ID 时，就会触发主键冲突

## 解决方案

### 快速修复（推荐）

在 71 服务器的数据库中执行以下 SQL：

```sql
SELECT setval('credentials_id_seq', COALESCE((SELECT MAX(id) FROM credentials), 1), true);
```

这条命令会：
1. 查找 `credentials` 表中的最大 ID
2. 将序列重置为该值
3. 下次插入将使用 `max_id + 1`

### 使用脚本修复

我已经创建了两个修复脚本：

#### 1. Shell 脚本（自动化）

```bash
cd /path/to/llm-gateway-go-2
./scripts/fix_credentials_sequence.sh
```

需要配置环境变量：
- `DB_HOST`: 数据库主机（默认 localhost）
- `DB_PORT`: 数据库端口（默认 5432）
- `DB_NAME`: 数据库名（默认 llm_gateway）
- `DB_USER`: 数据库用户（默认 postgres）

#### 2. SQL 脚本（手动执行）

```bash
psql -h <host> -U <user> -d llm_gateway -f scripts/fix_credentials_sequence.sql
```

### 诊断步骤

在修复之前，可以先诊断问题：

```sql
-- 查看序列当前值
SELECT last_value FROM credentials_id_seq;

-- 查看表中最大 ID
SELECT MAX(id) FROM credentials;

-- 如果 last_value < MAX(id)，说明序列不同步
```

## 验证修复

修复后，验证序列状态：

```sql
SELECT 
    last_value as current_seq_value, 
    (SELECT MAX(id) FROM credentials) as max_table_id 
FROM credentials_id_seq;
```

预期结果：`current_seq_value` 应该等于 `max_table_id`

然后重试添加凭据操作，应该能成功。

## 预防措施

为避免将来再次出现此问题：

1. **数据导入/恢复时**：确保同时导入序列状态
   ```bash
   pg_dump --data-only --inserts your_db > dump.sql
   # 或使用 pg_dump 的 --column-inserts 选项
   ```

2. **避免手动指定 ID**：不要执行类似的插入：
   ```sql
   -- 不推荐
   INSERT INTO credentials (id, provider_id, ...) VALUES (999, ...);
   ```

3. **定期检查**：创建监控脚本定期检查序列状态
   ```sql
   SELECT 
       'credentials' as table_name,
       last_value as seq_value,
       (SELECT MAX(id) FROM credentials) as max_id,
       CASE 
           WHEN last_value < (SELECT MAX(id) FROM credentials) 
           THEN 'MISMATCH - NEEDS FIX'
           ELSE 'OK'
       END as status
   FROM credentials_id_seq;
   ```

## 其他受影响的凭据问题

关于 "used manifest fallback (3 models)" 的警告：

这是一个不同的问题，表明：
- 健康检查时无法从 API 获取模型列表
- 系统使用了预定义的模型清单作为后备方案
- 这不会阻止凭据的使用，但可能影响模型可用性检测

建议：
1. 检查该凭据的 `health_status` 和 `health_error` 字段
2. 查看 `api_models_error` 字段了解具体错误
3. 手动触发健康检查：POST `/api/providers/{id}/credentials/{cid}/check-health`

## 相关文件

- 修复脚本：`scripts/fix_credentials_sequence.sh`
- SQL 脚本：`scripts/fix_credentials_sequence.sql`
- 凭据处理代码：`admin/provider_credential.go:82-86`
- 表定义：`deploy/sql/00_schema/003_routing_tables.sql:12-82`

## 时间线

- **2026-07-02**: 发现问题并创建修复脚本

---

如有问题，请联系开发团队。
