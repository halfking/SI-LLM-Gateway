# LLM Gateway 数据库 SQL 资产

本目录包含 LLM Gateway 数据库的所有 SQL 定义和初始化脚本。

---

## 🚀 快速开始

```bash
# 初始化数据库（包含种子数据）
./init.sh

# 跳过种子数据
./init.sh --skip-seed

# 指定数据库连接
./init.sh -h localhost -p 5432 -u postgres -d llm_gateway

# 使用环境变量
export PGPASSWORD=your_password
./init.sh
```

---

## 📁 目录结构

```
deploy/sql/
├── README.md                    # 本文件
├── init.sh                      # 统一初始化脚本
│
├── schema/                      # 表结构（157张表，按业务模块分类）
│   ├── core/                    # 核心表（6张）
│   │   ├── users.sql
│   │   ├── tenants.sql
│   │   ├── applications.sql
│   │   ├── agents.sql
│   │   ├── agent_relationships.sql
│   │   └── attachments.sql
│   │
│   ├── request/                 # 请求日志（16张，包含分区表）
│   │   ├── request_logs.sql
│   │   ├── request_wal.sql
│   │   └── ...
│   │
│   ├── credential/              # 凭据管理（26张）
│   │   ├── credentials.sql
│   │   ├── api_keys.sql
│   │   ├── credential_model_bindings.sql
│   │   └── ...
│   │
│   ├── model/                   # 模型管理（13张）
│   │   ├── models_canonical.sql
│   │   ├── model_aliases.sql
│   │   └── ...
│   │
│   ├── provider/                # 提供商（8张）
│   │   ├── providers.sql
│   │   ├── provider_models.sql
│   │   └── ...
│   │
│   ├── routing/                 # 路由决策（13张）
│   │   ├── routing_policy.sql
│   │   ├── routing_decision_log.sql
│   │   └── ...
│   │
│   ├── billing/                 # 计费相关（26张，包含分区表）
│   │   ├── credit_ledger.sql
│   │   ├── usage_ledger.sql
│   │   ├── tenant_subscriptions.sql
│   │   └── ...
│   │
│   ├── session/                 # 会话管理（6张）
│   │   ├── session_summaries.sql
│   │   └── ...
│   │
│   ├── audit/                   # 审计日志（17张）
│   │   ├── security_audit_log.sql
│   │   ├── output_compliance_audit.sql
│   │   └── ...
│   │
│   ├── tool/                    # 工具注册（8张）
│   │   ├── tool_registry.sql
│   │   └── ...
│   │
│   └── system/                  # 系统表（18张）
│       ├── schema_migrations.sql
│       ├── background_tasks.sql
│       └── ...
│
├── functions/                   # 函数（46个，按功能分类）
│   ├── partition/               # 分区管理（9个）
│   │   ├── ensure_request_logs_partition.sql
│   │   ├── create_next_month_partitions.sql
│   │   └── ...
│   │
│   ├── archive/                 # 归档清理（4个）
│   │   ├── archive_request_logs.sql
│   │   ├── cleanup_old_credential_model_index.sql
│   │   └── ...
│   │
│   └── business/                # 业务逻辑（28个）
│       ├── diagnose_failure_kind.sql
│       ├── update_api_key_model_cost.sql
│       └── ...
│
├── views/                       # 视图（18个）
│   ├── customer_cost_view.sql
│   ├── model_offers.sql
│   ├── v_model_health_dashboard.sql
│   └── ...
│
├── indexes/                     # 索引（82个，按表分组）
│   ├── users_indexes.sql
│   ├── credentials_indexes.sql
│   ├── request_logs_indexes.sql
│   └── ...
│
├── extensions/                  # PostgreSQL扩展
│   └── extensions.sql           # citus_columnar, btree_gist, pgcrypto
│
├── seed/                        # 初始化数据（3个文件）
│   ├── 01_system.sql            # 系统配置
│   ├── 02_providers.sql         # 提供商配置
│   └── 03_work_types.sql        # 工作类型配置
│
├── migrations/                  # 历史迁移脚本（88个）
│   ├── 001_users_table.sql
│   ├── 002_work_types.sql
│   └── ...
│
├── adhoc/                       # 临时脚本（9个）
├── db_scripts/                  # 运维脚本（3个）
├── tests/                       # 测试SQL（1个）
│
└── docs/                        # 文档
    ├── MIGRATION_GUIDE.md       # 迁移指南
    ├── archive/                 # 历史文档
    └── examples/                # SQL示例
```

---

## 📊 统计信息

| 类别 | 数量 | 说明 |
|------|------|------|
| **表** | 157 | 按11个业务模块分类 |
| **函数** | 46 | 按3种功能分类 |
| **视图** | 18 | 业务数据视图 |
| **索引组** | 82 | 按表分组的索引定义 |
| **种子数据** | 3 | 系统初始化必需数据 |

---

## 🗂 按业务模块分类

### Core（核心）- 6张表
用户、租户、应用、Agent等核心实体

### Request（请求）- 16张表
请求日志、WAL日志，**包含分区表**

### Credential（凭据）- 26张表
API密钥、凭据、模型绑定、健康检查

### Model（模型）- 13张表
模型目录、别名、生命周期管理

### Provider（提供商）- 8张表
提供商配置、模型映射、质量评分

### Routing（路由）- 13张表
路由策略、决策日志、粘性会话

### Billing（计费）- 26张表
信用账本、使用量、订阅、定价，**包含分区表**

### Session（会话）- 6张表
会话摘要、标题、审计记录

### Audit（审计）- 17张表
安全审计、合规性、提示注入检测

### Tool（工具）- 8张表
工具注册表、调用事件、使用统计

### System（系统）- 18张表
迁移记录、后台任务、配置、调优参数

---

## 🔧 初始化顺序

`init.sh` 按以下顺序执行：

1. **检查连接** - 验证数据库可访问
2. **安装扩展** - `extensions/extensions.sql`
3. **创建表结构** - 按模块顺序执行 `schema/*/` 
4. **创建函数** - 执行 `functions/*/` 
5. **创建视图** - 执行 `views/` 
6. **创建索引** - 执行 `indexes/` 
7. **初始化数据** - 执行 `seed/` （可选）

---

## 🔐 安全说明

### 已脱敏
- ✅ 无服务器IP地址
- ✅ 无数据库密码
- ✅ 无API密钥实际值
- ✅ 无第三方凭据
- ✅ 无用户敏感数据

### 仅包含
- ✅ 表结构定义
- ✅ 函数和视图定义
- ✅ 索引定义
- ✅ 最小化种子数据

### 需单独配置
生产环境的敏感数据需要通过安全的配置管理流程单独部署：
- API密钥（`api_keys`表）
- 第三方凭据（`credentials`表）
- 用户密码（`users`表）
- 租户配置（`tenants`表）

---

## 📖 扩展阅读

- **[迁移指南](docs/MIGRATION_GUIDE.md)** - 从旧结构迁移到新结构
- **[数据库版本](VERSION.md)** - 版本信息和分区管理
- **历史文档** - `docs/archive/` 目录

---

## 🆘 常见问题

### Q: 如何初始化一个全新的数据库？
```bash
createdb llm_gateway
./init.sh
```

### Q: 如何只创建表结构，不插入种子数据？
```bash
./init.sh --skip-seed
```

### Q: 如何添加新表？
在对应的 `schema/<模块>/` 目录下创建新的 `.sql` 文件。

### Q: 如何更新现有表结构？
在 `migrations/` 目录下创建新的迁移文件。

### Q: 旧的 `00_schema/`、`01_functions/` 目录去哪了？
已重构为新的目录结构。参见 [迁移指南](docs/MIGRATION_GUIDE.md)。

---

## 🔄 与历史版本的关系

| 版本 | 时间 | 结构 | 状态 |
|------|------|------|------|
| v1.0 | 2026-06 | `00_schema/` 8个文件 | ❌ 已废弃 |
| v2.0 | 2026-07-05 上午 | `tables/` 14个文件 | ❌ 已废弃 |
| **v3.0** | **2026-07-05 下午** | **`schema/` 按模块** | **✅ 当前** |

---

最后更新: 2026-07-05
