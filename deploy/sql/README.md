# LLM Gateway 数据库结构与 SQL 资产

本目录是 `llm_gateway` 数据库所有 SQL 资产的集中管理目录，包含表结构、初始化数据、迁移脚本、诊断工具及实时结构快照。

---

## 修改日志

- **2026-07-05**: 从测试数据库导出完整schema，重新组织目录结构，将SQL对象按类型拆分到独立目录，清理过期文件，完成敏感信息脱敏

---

## 目录结构

```text
deploy/sql/
├── README.md                               # 本文件
├── VERSION.md                              # 数据库版本与初始化前提
│
├── tables/                                 # 🆕 表结构定义（按业务模块分类，14个文件）
│   ├── schema_01-request.sql               #   请求日志相关（16张表，包含分区表）
│   ├── schema_02-credential.sql            #   凭据管理（30张表）
│   ├── schema_03-model.sql                 #   模型目录（12张表）
│   ├── schema_04-provider.sql              #   提供商配置（8张表）
│   ├── schema_05-routing.sql               #   路由决策（11张表，包含分区表）
│   ├── schema_06-tenant.sql                #   租户管理（7张表）
│   ├── schema_07-billing.sql               #   计费相关（12张表，包含分区表）
│   ├── schema_08-session.sql               #   会话管理（4张表）
│   ├── schema_09-api-key.sql               #   API密钥（3张表）
│   ├── schema_10-tool.sql                  #   工具注册（8张表）
│   ├── schema_11-audit.sql                 #   审计日志（9张表）
│   ├── schema_12-core.sql                  #   核心业务（users, agents, applications, attachments）
│   ├── schema_13-system.sql                #   系统表（schema_migrations, background_tasks）
│   └── schema_14-others.sql                #   其他业务表（30张表）
│
├── functions/                              # 🆕 函数定义（46个函数，每函数一个文件）
│   ├── archive_credential_model_index.sql
│   ├── archive_request_logs.sql
│   ├── ensure_request_logs_partition.sql
│   ├── diagnose_failure_kind.sql
│   └── ... (其他42个函数)
│
├── views/                                  # 🆕 视图定义（18个视图，每视图一个文件）
│   ├── customer_cost_view.sql
│   ├── model_offers.sql
│   ├── v_model_health_dashboard.sql
│   └── ... (其他15个视图)
│
├── indexes/                                # 🆕 索引定义（按表分组，82个文件）
│   ├── request_logs_indexes.sql
│   ├── credentials_indexes.sql
│   ├── api_keys_indexes.sql
│   └── ... (其他79个文件)
│
├── extensions/                             # 🆕 PostgreSQL扩展
│   └── extensions.sql                      #   citus_columnar, btree_gist, pgcrypto
│
├── seed_data/                              # 🆕 初始化种子数据
│   └── seed-data.sql                       #   系统初始化必需的最小数据集
│
├── 00_schema/                              # 按功能拆分的表结构（可执行初始化）
│   ├── 001_base_tables.sql                 #   tenants, users, applications
│   ├── 002_providers_and_models.sql
│   ├── 003_routing_tables.sql
│   ├── 004_tuning_and_work_types.sql
│   ├── 005_maas_billing.sql
│   ├── 006_request_logs.sql
│   ├── 007_archive_and_ledger.sql
│   └── 008_tools_registry.sql
│
├── 01_functions/                           # 原有函数目录（保留用于向后兼容）
│   └── functions.sql
│
├── 02_seed_data/                           # 原有种子数据（保留用于向后兼容）
│   ├── 001_basic.sql
│   ├── 002_providers.sql
│   └── 003_work_types.sql
│
├── migrations/                             # 🔄 历史迁移脚本（原 db/migrations/）
│   ├── 001_users_table.sql
│   ├── 002_work_types.sql
│   │   ...
│   └── 910_request_logs_archive.sql
│
├── db_scripts/                             # 🛠 数据库运维脚本
│   ├── diagnose_and_clean_request_logs.sql
│   ├── pre_migration_check.sql
│   └── verify_request_logs_unique.sql
│
├── adhoc/                                  # 🧪 临时诊断/修复脚本（已精简）
│   ├── init_database.sql
│   ├── add_production_data.sql
│   ├── bootstrap_full_schema.sql
│   ├── fix_credentials_state.sql
│   ├── patch_all_missing_columns.sql
│   ├── seed_mock_providers.sql
│   └── verify_*.sql
│
├── docs/                                   # 📄 文档 / 变更记录 SQL（已精简）
│   ├── 2026_06_12_pricing_refresh_log.sql
│   ├── 2026-06-14-peak-stats.sql
│   ├── 2026-06-15-auto-route-mode*.sql
│   ├── 2026-06-22-explicit-model-stats.sql
│   ├── archive/                            #   历史文档已归档
│   └── pricing/                            #   定价相关SQL
│
├── tests/                                  # 🧪 测试用 SQL
│   └── 038_adaptive_probe_test.sql
│
├── scripts/                                # ⚙️ 工具脚本
│   ├── init-db.sh
│   └── split_pg_dump.py
│
└── hotfix_background_tasks_pk.sql          # 独立热修复
```

---

## 🆕 新目录结构说明（2026-07-05重构）

### tables/ - 表结构按业务模块分类
- **优点**: 每个文件对应一个业务模块，便于快速定位和维护
- **使用**: 数据库初始化时按顺序执行01到14的文件
- **总计**: 14个文件，157张表

### functions/ - 函数独立文件
- **优点**: 每个函数单独管理，便于查找和修改
- **使用**: 可以单独创建或更新某个函数
- **总计**: 46个函数文件

### views/ - 视图独立文件
- **优点**: 每个视图单独管理
- **使用**: 可以单独创建或更新某个视图
- **总计**: 18个视图文件

### indexes/ - 索引按表分组
- **优点**: 每张表的索引集中管理
- **使用**: 创建表后执行对应的索引文件
- **总计**: 82个索引文件（按表分组）

### extensions/ - 数据库扩展
- **必需扩展**:
  - `citus_columnar` - 列式存储（用于归档分区表）
  - `btree_gist` - GiST索引支持
  - `pgcrypto` - 加密函数

### seed_data/ - 最小化种子数据
- **内容**: 系统启动必需的最小数据集
- **不包含**: 用户数据、凭据、API密钥等敏感信息

---

## 数据库初始化流程

### 方法一：使用新的分类结构（推荐）

```bash
# 1. 创建数据库
createdb -h <host> -U <user> llm_gateway

# 2. 安装扩展（必须先执行）
psql -h <host> -U <user> -d llm_gateway -f deploy/sql/extensions/extensions.sql

# 3. 创建表结构（按顺序执行）
for f in deploy/sql/tables/schema_*.sql; do
  echo "Loading $f..."
  psql -h <host> -U <user> -d llm_gateway -f "$f"
done

# 4. 创建函数
for f in deploy/sql/functions/*.sql; do
  psql -h <host> -U <user> -d llm_gateway -f "$f"
done

# 5. 创建视图
for f in deploy/sql/views/*.sql; do
  psql -h <host> -U <user> -d llm_gateway -f "$f"
done

# 6. 创建索引
for f in deploy/sql/indexes/*.sql; do
  psql -h <host> -U <user> -d llm_gateway -f "$f"
done

# 7. 插入种子数据
psql -h <host> -U <user> -d llm_gateway -f deploy/sql/seed_data/seed-data.sql
```

### 方法二：使用原有00_schema结构（向后兼容）

```bash
# 按原有流程执行
psql -h <host> -U <user> -d llm_gateway -f deploy/sql/00_schema/001_base_tables.sql
psql -h <host> -U <user> -d llm_gateway -f deploy/sql/00_schema/002_providers_and_models.sql
# ... 继续其他文件
psql -h <host> -U <user> -d llm_gateway -f deploy/sql/01_functions/functions.sql
psql -h <host> -U <user> -d llm_gateway -f deploy/sql/02_seed_data/001_basic.sql
# ... 其他seed文件
```

---

## 数据策略

### 保留的初始化数据
- `tenants`: 仅 `default`
- `users`: 仅 `admin`
- `applications`: 仅 `admin` / `applicant`
- `providers`: 仅标准 provider 配置
- `work_type_config` / `work_type_model_route`
- `tool_categories`: 工具分类
- `schema_migrations`: 迁移版本追踪

### 不初始化的数据（需单独配置）
- `api_keys` - 包含敏感的API密钥
- `credentials` - 包含第三方提供商凭据
- `request_logs*` - 实际请求数据
- `request_wal*` - WAL数据
- `credit_ledger*` / `usage_ledger*` - 计费数据
- 详细审计、监控、运营数据

---

## 目录清理说明

本次重构（2026-07-05）进行了以下清理：

### 已移除
- ❌ `objects/` - 冗余的逐对象拆分目录
- ❌ `diagnostics/` - 诊断脚本已整合到db_scripts
- ❌ `00_schema/full_schema.sql` - 避免与tables/冗余

### 已精简
- `adhoc/` - 移除了大量临时诊断和修复脚本
- `docs/` - Markdown文档移至archive子目录
- `docs/pricing/` - 移除tier2子目录

### 已脱敏
- ✅ 所有文件中的服务器IP地址已替换为通用描述
- ✅ "71服务器" 替换为 "测试服务器"
- ✅ "Production database" 替换为 "Test database"

---

## 安全说明

所有导出的SQL文件已完成敏感信息检查和脱敏处理：
- ✅ 不包含数据库密码
- ✅ 不包含服务器IP地址
- ✅ 不包含API密钥实际值
- ✅ 不包含第三方提供商凭据
- ✅ 不包含用户敏感数据
- ✅ 仅包含表结构、函数、视图、索引定义

生产环境的敏感数据需要通过安全的配置管理流程单独部署。

---

## 与测试数据库结构同步

如需重新获取数据库结构快照：

```bash
# 从测试服务器导出
ssh postgres@TEST_SERVER

# 导出表结构
pg_dump -U llm_gateway -h 127.0.0.1 -p 5432 -d llm_gateway \
  --schema-only --no-owner --no-privileges \
  > /tmp/schema_dump.sql

# 然后使用本地脚本拆分
# （参考本次导出使用的shell脚本）
```

---

## 使用边界

- **tables/ + functions/ + views/ + indexes/ + extensions/ + seed_data/** - 用于全新数据库初始化（推荐）
- **00_schema/ + 01_functions/ + 02_seed_data/** - 原有初始化方式（向后兼容）
- **migrations/** - 历史DDL变更记录，**不保证幂等**，应按顺序执行
- **adhoc/** - 临时操作脚本，执行前请仔细阅读
- **docs/** - 文档和记录性质的SQL，非初始化必需

---

详见 [VERSION.md](./VERSION.md) 了解数据库版本、扩展要求和分区管理建议。
