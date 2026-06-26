# LLM Gateway 版本变更总结

> **分支**: github (原 server-71)  
> **变更范围**: 自 `30d92e3d` (github 分叉点) 至 `9ee56d70` (最新)  
> **生成日期**: 2026-06-27

---

## 📊 统计概览

| 指标 | 数量 |
|------|------|
| 总提交数 | 47 个提交 |
| 新增文件 | 54 个 |
| 代码变更 | +7,468 / -10,968 行 |
| 主要模块 | telemetry, db, admin, web, relay |

---

## 🔧 核心功能改进

### 1. 数据库架构增强

#### 1.1 请求日志归档系统
- ✅ `request_logs_archive` 分层存储架构
- ✅ 支持按月分区存储历史数据
- ✅ 减少主表数据量，提升查询性能
- **文件**: `db/migrations/910_request_logs_archive.sql`, `db/request_logs_archive_schema.go`

#### 1.2 唯一约束修复
- ✅ 修复 `request_logs` 表 `UNIQUE(request_id)` 约束问题
- ✅ 支持分区表兼容性
- ✅ 添加 `client_request_id` 字段
- **文件**: `db/migrations/054_request_logs_client_request_id.sql`

#### 1.3 SQL Schema 文档化
- ✅ 完整数据库架构文档 (`deploy/sql/00_schema/`)
- ✅ 8 个 Schema 模块:
  - `001_base_tables.sql` - 基础表结构
  - `002_providers_and_models.sql` - 提供商和模型
  - `003_routing_tables.sql` - 路由表
  - `004_tuning_and_work_types.sql` - 调优和工作类型
  - `005_maas_billing.sql` - 计费系统
  - `006_request_logs.sql` - 请求日志
  - `007_archive_and_ledger.sql` - 归档和账本
  - `008_tools_registry.sql` - 工具注册表

#### 1.4 数据库函数
- ✅ 核心业务函数库 (`deploy/sql/01_functions/functions.sql`)
- ✅ 初始化脚本 (`deploy/sql/scripts/init-db.sh`)

---

### 2. 凭据管理增强

#### 2.1 槽位管理 (Fingerprint Slot)
- ✅ LRU 预占用机制
- ✅ 30分钟自动回收
- ✅ 5分钟活跃门限
- ✅ 槽位限制: 5 → 20
- **文件**: `admin/provider_credential.go`, `admin/provider_credential_test.go`

#### 2.2 凭据健康监控
- ✅ 4-tab 详情页面
- ✅ 6 个模型字段
- ✅ `manual_disabled` 抽屉入口
- ✅ 探针状态持久化 (`unavailable_recover_at`)

---

### 3. 路由系统改进

#### 3.1 路由 V2 统计
- ✅ 模型路由统计诊断工具
- ✅ Heatmap 热力图优化
- ✅ 指定模型请求统计 (`__specified__`)
- ✅ 401 重定向修复
- **文件**: `admin/auto_route_stats.go`, `web/src/views/routing/*`

#### 3.2 路由质量门控
- ✅ 多层质量降级策略
- ✅ `loadCandidatesDB` 多层降级包装
- ✅ `successRateThreshold` 参数传递修复
- ✅ Prometheus 指标集成

---

### 4. 可观测性增强

#### 4.1 CEF 日志格式
- ✅ SIEM 集成支持
- ✅ FileSink 输出
- ✅ NOW-4 Phase 1

#### 4.2 遥测数据改进
- ✅ 自动请求标识修复 (`is_auto_request`)
- ✅ 每次尝试延迟记录
- ✅ 真实 `request_id` 健康追踪
- ✅ `raw_model` + `window_start` 支持

---

### 5. 前端改进

#### 5.1 凭据详情页重构
- ✅ 基础信息强化
- ✅ 模型 Tab 左右布局
- ✅ 3 个状态图标
- ✅ 双层槽位信息卡片

#### 5.2 路由仪表盘优化
- ✅ 无滚动条自然高度
- ✅ 模型列表单列显示

#### 5.3 首页改版
- ✅ 企业 AI 与 Agent 网关定位
- ✅ 图标重设计
- ✅ 路线图展示

---

### 6. 部署工具

#### 6.1 P0 热修复工具
- ✅ `deploy_p0_hotfix.sh` - P0 修复部署脚本
- ✅ `verify_p0_hotfix.sh` - 验证脚本
- ✅ `DRY_RUN` 支持
- ✅ `P0_INCIDENT_SUMMARY.md` - 事件总结
- ✅ `CRITICAL_BUG_ANALYSIS.md` - Bug 分析

#### 6.2 部署文档
- ✅ `DEPLOYMENT_GUIDE.md` - 完整部署指南
- ✅ `DEPLOYMENT_READY.md` - 部署就绪检查
- ✅ `DEPLOY_CHECKLIST.md` - 部署检查清单

---

## 🐛 Bug 修复清单

| 编号 | 描述 | 严重性 |
|------|------|--------|
| B001 | `request_logs` 重复记录和 `in_progress` 状态问题 | P0 |
| B002 | `model_offers` VIEW 上 `ALTER` 语句问题 | P1 |
| B003 | `credential_model_call_history` hypertable 列解析 | P1 |
| B004 | `credential_monitor` LATERAL join 优化 | P1 |
| B005 | 探针状态 `broken_confirmed` 恢复 | P1 |
| B006 | `specified-model` 统计 PR 审计修复 | P2 |
| B007 | LEFT JOIN vs CROSS JOIN LATERAL 兼容性 | P2 |
| B008 | `updated_at`/`unavailable_recover_at` 移除 | P2 |
| B009 | JSONB 列类型转换 (`::text`) | P2 |
| B010 | `secret_ciphertext` 类型转换 | P2 |
| B011 | 路由过滤器同步实际行为 | P2 |
| B012 | 模板 `Invalid end tag` 错误 | P2 |
| B013 | 会话路由黏性绑定保持 | P2 |

---

## 🔨 构建改进

- ✅ 版本管理规范化
- ✅ `VERSION` 解析为 4 段
- ✅ Dockerfile 移除 git-describe 后缀
- ✅ `build_seq` 升级至 652

---

## 📁 新增文件清单

### 数据库相关
```
deploy/sql/00_schema/*.sql           (8 个文件)
deploy/sql/01_functions/functions.sql
deploy/sql/02_seed_data/*.sql         (3 个文件)
deploy/sql/scripts/init-db.sh
db/migrations/910_request_logs_archive.sql
db/request_logs_archive_schema.go
```

### 部署脚本
```
deploy_p0_hotfix.sh
verify_p0_hotfix.sh
deploy/sql/hotfix_background_tasks_pk.sql
```

### 文档
```
DEPLOYMENT_GUIDE.md
DEPLOYMENT_READY.md
P0_INCIDENT_SUMMARY.md
CRITICAL_BUG_ANALYSIS.md
HOTFIX_REVERT_ON_CONFLICT.md
DEPLOY_REQUEST_LOGS_UNIQUE_ID.md
CHANGELOG_credential_fp_slot_constraint.md
CHANGELOG_request_logs_unique_id.md
```

### 诊断工具
```
diagnose_credential_check.sh
```

---

## 🚀 部署说明

### 部署前检查
```bash
# 1. 验证代码
git pull origin github

# 2. 运行数据库迁移
psql $DATABASE_URL -f db/migrations/910_request_logs_archive.sql

# 3. 编译
go build -o bin/llm-gateway ./cmd/gateway

# 4. 重启服务
sudo systemctl restart llm-gateway
```

### 验证命令
```bash
# 检查 Matrix 接口
curl "https://llm.kxpms.cn/api/admin/auto-route/analytics/matrix?window=7d&metric=count&row=task_type"

# 检查 Flow 接口
curl "https://llm.kxpms.cn/api/admin/auto-route/analytics/flow?window=7d"

# 访问前端
https://llm.kxpms.cn/routing-v2
```

---

## 🔄 相关版本

- **当前版本**: V2.2.0-xxx (build_seq: 707+)
- **目标版本**: V2.2.9
- **代码仓库**: 
  - GitHub: `github.com:halfking/SI-LLM-Gateway.git` (分支: github)
  - Codeup: `https://codeup.aliyun.com/kaixuan/official-deploy/llm-gateway-go.git` (分支: github)

---

## 📞 支持

如有问题，请参考：
- 完整部署指南: `DEPLOYMENT_GUIDE.md`
- 问题诊断: `CRITICAL_BUG_ANALYSIS.md`
- 部署检查清单: `DEPLOYMENT_READY.md`