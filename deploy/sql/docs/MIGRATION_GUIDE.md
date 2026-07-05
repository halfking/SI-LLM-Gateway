# 数据库SQL目录重构迁移指南

## 变更日期
2026-07-05

## 变更概述
将deploy/sql目录从混合结构重构为清晰的按对象类型分层的结构。

## 旧结构 vs 新结构

### 旧结构（已废弃）
```
deploy/sql/
├── 00_schema/              # 8个模块化SQL文件
├── 01_functions/           # 单个大文件
├── 02_seed_data/           # 3个种子数据文件
├── tables/                 # 14个分类文件
├── functions/              # 46个独立文件
├── views/                  # 18个独立文件
├── indexes/                # 82个按表分组
└── ... (冗余)
```

### 新结构（推荐）
```
deploy/sql/
├── schema/                 # 表结构（157张表，按业务模块分类）
│   ├── core/              # 核心表（6张）
│   ├── request/           # 请求日志（16张）
│   ├── credential/        # 凭据管理（26张）
│   ├── model/             # 模型管理（13张）
│   ├── provider/          # 提供商（8张）
│   ├── routing/           # 路由决策（13张）
│   ├── billing/           # 计费相关（26张）
│   ├── session/           # 会话管理（6张）
│   ├── audit/             # 审计日志（17张）
│   ├── tool/              # 工具注册（8张）
│   └── system/            # 系统表（18张）
│
├── functions/             # 函数（46个，按功能分类）
│   ├── partition/         # 分区管理（9个）
│   ├── archive/           # 归档清理（4个）
│   └── business/          # 业务逻辑（28个）
│
├── views/                 # 视图（18个）
├── indexes/               # 索引（82个，按表分组）
├── extensions/            # PostgreSQL扩展
├── seed/                  # 初始化数据（3个文件）
├── migrations/            # 历史迁移（保持不变）
├── docs/                  # 文档和示例
└── init.sh                # 统一初始化脚本
```

## 主要改进

### 1. 表结构按业务模块组织
- **优势**: 每个业务领域独立管理，便于快速定位
- **示例**: 
  - `schema/core/users.sql` - 用户表
  - `schema/credential/credentials.sql` - 凭据表
  - `schema/request/request_logs.sql` - 请求日志表

### 2. 函数按功能分类
- **partition/** - 分区表管理函数
- **archive/** - 数据归档和清理
- **business/** - 业务逻辑函数

### 3. 简化的初始化数据
- `seed/01_system.sql` - 系统配置
- `seed/02_providers.sql` - 提供商配置
- `seed/03_work_types.sql` - 工作类型配置

## 迁移步骤

### 如果你使用旧的初始化脚本
**旧方式**（已废弃）:
```bash
bash deploy/sql/scripts/init-db.sh
```

**新方式**:
```bash
bash deploy/sql/init.sh
```

### 如果你手动执行SQL
**旧方式**:
```bash
psql -f deploy/sql/00_schema/001_base_tables.sql
psql -f deploy/sql/01_functions/functions.sql
```

**新方式**:
```bash
# 执行所有核心表
psql -f deploy/sql/schema/core/users.sql
psql -f deploy/sql/schema/core/tenants.sql
# ... 或使用新的 init.sh
```

## 脚本和代码更新

如果你的脚本引用了旧路径，需要更新：

```bash
# 旧路径（不再有效）
deploy/sql/00_schema/*.sql
deploy/sql/01_functions/functions.sql
deploy/sql/02_seed_data/*.sql
deploy/sql/tables/schema_*.sql

# 新路径
deploy/sql/schema/*/*.sql
deploy/sql/functions/*/*.sql
deploy/sql/seed/*.sql
```

## 已删除的目录

以下目录已在本次重构中删除：
- ❌ `00_schema/` - 已整合到 `schema/` 各子目录
- ❌ `01_functions/` - 已整合到 `functions/` 各子目录
- ❌ `02_seed_data/` - 已重命名为 `seed/`
- ❌ `tables/` - 已拆分到 `schema/` 各子目录
- ❌ `seed_data/` - 已重命名为 `seed/`
- ❌ `scripts/` - init.sh 移到根目录

## 向后兼容性

为保证平滑过渡，建议：

1. **更新所有引用旧路径的脚本**
2. **使用新的 `init.sh` 进行数据库初始化**
3. **文档中的SQL引用更新为新路径**

## 问题反馈

如果迁移过程中遇到问题，请检查：
1. 是否所有旧路径都已更新
2. 是否使用了新的初始化脚本
3. 是否按正确的顺序执行SQL（extensions → schema → functions → views → indexes → seed）
