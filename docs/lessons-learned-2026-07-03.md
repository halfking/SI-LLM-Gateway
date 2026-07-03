# 经验教训总结：71服务器实时请求流数据丢失问题

**日期**: 2026-07-03  
**提交**: d628ffcf + 2a7a8f25 + 9d33f291  
**影响范围**: llm.kxpms.cn 网关服务

---

## 问题概述

71服务器上的 llm.kxpms.cn 网关首页"实时请求流"功能没有数据显示。经过系统排查，发现了多个级联问题：

1. **Invalid or expired API key 错误**: Claude-opus-4-8请求失败
2. **实时请求流无数据**: 首页dashboard无显示

---

## 根本原因分析

### 问题1: 环境配置覆盖导致加密密钥丢失

**症状**: 所有 provider credentials 无法解密，API请求返回 "Invalid or expired API key"

**根本原因**: 
- `scripts/deploy-71-data-bindmounts.sh` 脚本在重写 `/etc/llm-gateway-go/env` 时遗漏了 `LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY`
- 缺少加密密钥导致网关无法解密数据库中的 provider credentials

**教训**:
- 部署脚本的 env 模板必须包含所有必需的环境变量
- 修改前应备份现有配置，修改后应验证配置完整性

### 问题2: Citus Columnar表UPDATE失败导致数据库被禁用

**症状**: 数据库连接被禁用，所有依赖数据库的功能（路由、认证、telemetry）失效

**根本原因**:
- `db/db.go` 中的 `ensureRequestLogSchema()` 包含对 `request_logs` 表的 UPDATE 语句
- Citus columnar表不支持带CTID扫描的 UPDATE 操作
- UPDATE失败导致 `db.Open()` 返回错误
- 整个数据库连接被禁用，级联影响所有功能

**教训**:
- Schema migration 代码必须容错处理不同数据库存储引擎的限制
- 单个操作的失败不应阻断整个数据库初始化
- 需要了解底层数据库特性（Citus columnar、PG分区等）

### 问题3: pg_trgm扩展缺失导致索引创建失败

**症状**: 实时请求流无数据，所有telemetry无法写入数据库

**根本原因**:
- `ensureRequestLogSchema()` 尝试创建使用 `pg_trgm` 的 GIN 索引
- 71服务器的数据库没有安装 `pg_trgm` 扩展
- 索引创建失败导致整个数据库初始化失败
- 数据库连接被禁用，所有请求无法记录

**教训**:
- 扩展依赖应该检查可用性，不可用时应优雅降级
- 关键索引创建失败不应阻断整个数据库初始化
- 需要支持不同环境的差异（生产环境可能缺少某些扩展）

---

## 关键经验教训

### 1. 数据库初始化必须容错

**原则**: Schema migration 中的单个操作失败不应该阻断整个数据库初始化。

**实践**:
```sql
-- ❌ 错误做法：单个失败导致整个初始化失败
CREATE INDEX idx_xxx ON xxx USING gin (col public.gin_trgm_ops);

-- ✅ 正确做法：异常处理，优雅降级
DO $$
BEGIN
    CREATE INDEX idx_xxx ON xxx USING gin (col public.gin_trgm_ops);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'index creation skipped: %', SQLERRM;
END $$;
```

### 2. 部署脚本配置必须完整

**原则**: 部署脚本的 env 模板必须包含所有必需的环境变量。

**实践**:
- ✅ 备份现有配置后再修改
- ✅ 修改后验证配置完整性
- ✅ 使用配置检查脚本验证所有必需变量
- ❌ 不要在不知道现有配置的情况下覆盖 env 文件

### 3. 必须理解系统架构设计

**原则**: 修改前必须充分理解系统的架构设计。

**本案例的正确架构**:
- `request_logs` 是分区表，PARTITION BY RANGE(ts)
- 新数据写入 `request_logs_default` (heap分区)
- 定期批量迁移到columnar分区（用于历史数据存储，压缩比高）
- columnar分区不支持INSERT/UPDATE，只用于SELECT

**错误做法**: 
- ❌ 试图将columnar分区转为heap分区
- ❌ 误解分区设计意图

### 4. 数据操作前必须确认

**原则**: 涉及数据删除、表结构修改的操作必须先确认，得到用户批准后再执行。

**实践**:
- ✅ 在执行 DROP TABLE、ALTER TABLE 之前先告知用户
- ✅ 解释每个操作的影响（数据丢失风险）
- ✅ 等待用户明确确认
- ❌ 不要在没有确认的情况下执行破坏性操作
- ❌ 不要在用户未确认时执行多个连续的操作

### 5. 问题诊断要系统性

**原则**: 问题诊断应该从根本原因开始，而不是症状。

**本案例的问题链条**:
```
pg_trgm扩展缺失 → 索引创建失败 → 数据库初始化失败 → 数据库被禁用
→ telemetry无法写入 → 实时请求流无数据
```

**诊断步骤**:
1. 查看服务日志，识别错误模式
2. 检查数据库状态（连接、表结构）
3. 验证关键功能路径（telemetry、认证、路由）
4. 识别级联失败的根本原因

### 6. 修改必须可回滚

**原则**: 任何修改都必须可以安全回滚。

**实践**:
- ✅ 数据库修改前先备份
- ✅ 保留原始文件副本
- ✅ 修改后验证可以回滚
- ✅ 记录所有操作步骤

---

## 改进建议

### 代码层面

1. **统一错误处理模式**
   - 所有 schema migration 操作都应使用 DO/EXCEPTION 包装
   - 创建迁移工具库，统一处理不同数据库的限制

2. **配置完整性检查**
   - 启动时验证所有必需的环境变量
   - 提供配置检查脚本

3. **架构文档化**
   - 记录分区表的设计意图
   - 说明 columnar 表的使用场景和限制

### 流程层面

1. **部署前检查清单**
   - [ ] 备份现有配置
   - [ ] 验证 env 文件包含所有必需变量
   - [ ] 数据库健康检查
   - [ ] 关键功能验证

2. **问题升级流程**
   - 数据删除/表修改操作必须先确认
   - 涉及多个系统的修改需要分步执行
   - 每个步骤后进行验证

3. **知识共享**
   - 记录常见问题和解决方案
   - 建立故障排查知识库

---

## 修复总结

### 修改的文件

1. **scripts/deploy-71-data-bindmounts.sh**
   - 添加 `LLM_GATEWAY_SECRET_KEY` 和 `LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY`
   - 确保env文件包含所有必需配置

2. **db/db.go**
   - 将 `request_status backfill UPDATE` 包装在 DO/EXCEPTION 中
   - 将 `pg_trgm` 索引创建包装在 DO/EXCEPTION 中
   - 所有 schema migration 操作变得容错

### 验证结果

- ✅ 服务正常启动
- ✅ 数据库连接成功
- ✅ Routing executor 启用
- ✅ API key 认证启用
- ✅ Telemetry 数据正常写入
- ✅ 实时请求流正常显示数据

### 部署信息

- **版本**: 2.3.3-d628ffcf-20260703-782
- **提交**: d628ffcf
- **服务器**: root@14.103.174.71:25022 (llm.kxpms.cn)
- **部署时间**: 2026-07-03 16:49

---

## 引用

- 提交 d628ffcf: 修复pg_trgm索引创建容错
- 提交 2a7a8f25: 修复Citus columnar UPDATE和恢复加密密钥
- 提交 9d33f291: 健康状态使用unreachable

**记住**: 永远先理解系统，再修改系统。永远先备份，再操作数据。
