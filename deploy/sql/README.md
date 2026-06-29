# LLM Gateway 数据库结构与 SQL 资产

本目录是 `llm_gateway` 数据库所有 SQL 资产的集中管理目录，包含表结构、初始化数据、迁移脚本、诊断工具及实时结构快照。

---

## 目录结构

```text
deploy/sql/
├── README.md                               # 本文件
├── VERSION.md                              # 数据库版本与初始化前提
│
├── 00_schema/                              # 按功能拆分的表结构（可执行初始化）
│   ├── 001_base_tables.sql                 # tenants, users, applications, system_identity_pool
│   ├── 002_providers_and_models.sql        # providers, provider_models, models_canonical
│   ├── 003_routing_tables.sql              # credential_model_bindings, routing_* 等路由表
│   ├── 004_tuning_and_work_types.sql       # work_type_config, work_type_model_route, tuning_*
│   ├── 005_maas_billing.sql                # maas_settings, model_credit_rates, billing_orders
│   ├── 006_request_logs.sql                # request_logs (分区表)
│   ├── 007_archive_and_ledger.sql          # request_logs_archive, credit_ledger, usage_ledger
│   ├── 008_tools_registry.sql              # tool_registry, tool_call_events, tool_usage_stats
│   └── full_schema.sql                      # 🔗 生产数据库 pg_dump --schema-only 实时快照
│
├── 01_functions/                           # 函数/触发器（可执行初始化）
│   └── functions.sql
│
├── 02_seed_data/                           # 最小初始化数据（可执行初始化）
│   ├── 001_basic.sql
│   ├── 002_providers.sql
│   └── 003_work_types.sql
│
├── objects/                                # 📦 逐对象拆分（来自生产数据库的 pg_dump 解析）
│   ├── tables/                             #   138 个表，每文件一个 CREATE TABLE
│   ├── indexes/                            #   413 个索引
│   ├── constraints/                        #   88 个约束（CHECK, UNIQUE, PK）
│   ├── sequences/                          #   65 个序列
│   ├── defaults/                           #   64 个默认值 / SEQUENCE OWNED BY
│   ├── policies/                           #   64 个 RLS 策略
│   ├── functions/                          #   37 个函数/存储过程
│   ├── views/                              #   17 个视图
│   ├── triggers/                           #   16 个触发器
│   ├── fkeys/                              #   8 个外键
│   ├── misc/                               #   17 个 ATTACH PARTITION 等杂项
│   ├── extensions/                         #   4 个扩展
│   ├── matviews/                           #   2 个物化视图
│   └── types/                              #   0 个自定义类型
│
├── migrations/                             # 🔄 历史迁移脚本（原 db/migrations/）
│   ├── 001_users_table.sql                 #   按编号顺序排列
│   ├── 002_work_types.sql
│   │   ...
│   ├── 910_request_logs_archive.sql
│   └── completed/                          #   已完成的历史迁移
│       └── 032_session_tenant_binding.sql  #     （来自项目根 migrations/）
│
├── db_scripts/                             # 🛠 数据库运维脚本（原 db/scripts/）
│   ├── diagnose_and_clean_request_logs.sql
│   ├── pre_migration_check.sql
│   └── verify_request_logs_unique.sql
│
├── adhoc/                                  # 🧪 临时诊断/修复脚本
│   ├── add_production_data.sql             #   （原项目根目录）
│   ├── diagnose_routing_v2_stats.sql       #   （原项目根目录）
│   ├── fix_routing_issue.sql               #   （原项目根目录）
│   ├── init_database.sql                   #   （原项目根目录）
│   ├── bootstrap_full_schema.sql           #   （原 scripts/）
│   ├── diagnose-fpslot-db-queries.sql      #   （原 scripts/）
│   ├── emergency_fix_credentials.sql       #   （原 scripts/）
│   ├── fix_credentials_state.sql           #   （原 scripts/）
│   ├── fix-fpslot-limit.sql                #   （原 scripts/）
│   ├── patch_all_missing_columns.sql       #   （原 scripts/）
│   ├── seed_mock_providers.sql             #   （原 scripts/）
│   ├── verify-provider-model-join.sql      #   （原 scripts/）
│   └── verify_request_logs.sql             #   （原 scripts/）
│
├── docs/                                   # 📄 文档 / 变更记录 SQL
│   ├── 2026-06-14-peak-stats.sql
│   ├── 2026-06-15-auto-route-mode.sql
│   ├── 2026-06-15-auto-route-mode.down.sql
│   ├── 2026-06-15-auto-route-mode-cost-table.sql
│   ├── 2026-06-15-auto-route-mode-cost-table.down.sql
│   ├── 2026-06-15-auto-route-mode-realtime-trigger.sql
│   ├── 2026-06-15-auto-route-mode-realtime-trigger.down.sql
│   ├── 2026-06-15-auto-route-mode-realtime-trigger-fix.sql
│   ├── 2026-06-22-explicit-model-stats.sql
│   ├── 2026-06-22-explicit-model-stats.down.sql
│   ├── 2026_06_12_pricing_refresh_log.sql  #   （原 deploy/k8s/cron/）
│   ├── pricing/
│   │   ├── 2026-06-12-audit-fixes.sql
│   │   ├── 2026-06-12-cny-fix.sql
│   │   ├── 2026-06-12-cny-fix-all-credentials.sql
│   │   ├── 2026-06-12-plan-meta.sql
│   │   ├── 2026-06-12-pricing-plans.sql
│   │   └── 2026-06-12-tier2/
│   │       └── xiaomi_tokenplan_tier2.sql
│   │
│   └── README.md                          # (docs/ 下原有文档, 非 SQL 文件保留原位置)
│
├── tests/                                  # 🧪 测试用 SQL
│   └── 038_adaptive_probe_test.sql         #   （原 tests/）
│
├── scripts/                                # ⚙️ 工具脚本
│   ├── init-db.sh                          #   数据库初始化脚本
│   └── split_pg_dump.py                    #   pg_dump 按对象拆分工具
│
└── hotfix_background_tasks_pk.sql          # 独立热修复
```

---

## 各子目录说明

### 00_schema/ （可执行初始化）
按功能拆分的表结构，用于**单机目标库初始化**，包含完整的 CREATE TABLE/INDEX 语句。配合 `01_functions/` 和 `02_seed_data/` 可完成全量初始化。

### full_schema.sql
来自生产 PostgreSQL 数据库（Kubernetes 命名空间）的 `pg_dump --schema-only --no-owner --no-privileges --no-comments` 实时快照。
**这是生产数据库当前结构的权威参考。**

### objects/（逐对象拆分）
由 `scripts/split_pg_dump.py` 从 `full_schema.sql` 解析生成，**每文件一个数据库对象**。
- 文件命名: `{schema}.{object_name}.{type?}.sql`
- 每个文件包含源出处注释
- 包含 933 个文件，覆盖 154 个表/视图 + 索引/函数/触发器/策略等

适用场景：快速查阅某张表的精确列定义，或按对象类型对比差异。

### migrations/（迁移历史）
原 `db/migrations/` 目录物理迁移至此，按编号顺序排列，是完整的 DDL 变更流水线。
- 包含 50 个迁移文件（含 `.down.sql` 回滚文件）
- `completed/` 下收纳了原本分散在项目根 `migrations/` 下的历史迁移

> ⚠️ `db/db.go` 中的注释引用了 `db/migrations/xxx.sql` 路径，这些是文档注释，不影响编译。
> 引用关系在代码中仅用作文档说明，无实际文件读取。

### db_scripts/（运维脚本）
原 `db/scripts/` 目录物理迁移，包含数据库运维和诊断工具。

### adhoc/（临时脚本）
项目各处散落的诊断、修复、临时初始化脚本统一定位。

### docs/（文档 SQL）
记录式变更 SQL 与定价相关 SQL，保持原始子目录 `pricing/` 和 `2026-06-12-tier2/` 结构。
`deploy/k8s/cron/` 下的 SQL 也移入此目录（cron job YAML 不引用本地 SQL 路径）。

### tests/（测试 SQL）
放在 `tests/` 目录下的测试用 SQL。

### scripts/（工具脚本）
- `init-db.sh` — 数据库初始化脚本
- `split_pg_dump.py` — pg_dump 按对象拆分工具

---

## 初始化顺序

```bash
psql -h <host> -U <user> -d <db> -f deploy/sql/00_schema/001_base_tables.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/00_schema/002_providers_and_models.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/00_schema/003_routing_tables.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/00_schema/004_tuning_and_work_types.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/00_schema/005_maas_billing.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/00_schema/006_request_logs.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/00_schema/007_archive_and_ledger.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/00_schema/008_tools_registry.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/01_functions/functions.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/02_seed_data/001_basic.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/02_seed_data/002_providers.sql
psql -h <host> -U <user> -d <db> -f deploy/sql/02_seed_data/003_work_types.sql
```

也可使用 `scripts/init-db.sh` 自动化完成。

---

## 与生产数据库结构同步

如需重新获取生产数据库结构快照：

```bash
# 1. 导出完整 schema（通过 SSH 连入生产 Kubernetes 集群）
ssh <生产服务器>
kubectl exec -n <命名空间> <postgres-pod> -c <容器名> -- \
  pg_dump -U <用户名> -d <数据库名> --schema-only \
  --no-owner --no-privileges --no-comments > deploy/sql/00_schema/full_schema.sql

# 2. 重新按对象拆分
python3 deploy/sql/scripts/split_pg_dump.py \
  deploy/sql/00_schema/full_schema.sql \
  deploy/sql/objects
```

---

## 数据策略

### 保留的初始化数据
- `tenants`: 仅 `default`
- `users`: 仅 `admin`
- `applications`: 仅 `admin` / `applicant`
- `providers`: 仅标准 provider 配置，不含 credentials，不含详细业务化自定义条目
- `work_type_config` / `work_type_model_route`

### 不初始化的数据
- `api_keys`
- `credentials`
- `request_logs*` 实际请求数据
- `request_wal*` 实际 WAL 数据
- `credit_ledger*` / `usage_ledger*` / `billing_orders`
- 详细审计、监控、运营、业务明细数据

---

## 使用边界

- `00_schema/` + `01_functions/` + `02_seed_data/` 用于单机目标库初始化。
- `objects/` 是生产数据库实时结构的精确镜像（只读参考），不可直接用于初始化（存在顺序依赖）。
- `migrations/` 是历史 DDL 变更记录，**不保证幂等**，应按顺序执行。
- `adhoc/` + `docs/` 中的脚本多为一次性操作，执行前请仔细阅读。

---

详见 [VERSION.md](./VERSION.md) 了解数据库版本、扩展要求和分区管理建议。
