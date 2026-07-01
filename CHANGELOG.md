# Changelog

> 简明变更历史。仅记录高阶业务/架构级变更，不含文件路径、内部提交哈希、命令、密钥或事件细节。

## V2.3.3 — 附件归档与部署自动化

### 部署自动化
- `bump-version.sh`: 5 文件原子同步机制 (VERSION / version.json / web/public / web/dist / .deploy_seq)
- `deploy-71.sh`: 一键部署脚本 (自动 stop → 编译 → 上传 → restart)
- `.deploy_seq` 文件作为 build_seq 单一数据源，修复前端编译次数显示不同步问题
- 交叉编译 linux/amd64 自动化 + systemd 服务重启

### 附件功能
- 内联 base64 图片自动归档到本地存储
- 附件缩略图点击全屏预览 (Vue Teleport + 模态框 + ESC 关闭)
- 修复 3 个静默失败: nil pool 返回、dedupe 不回写 request_id、null 序列化白屏
- `storage_path` 锚定到绝对路径，修复容器挂载路径不一致问题
- 附件元数据显示 (media_type / file_size / hash)

### 电路熔断器
- 瞬时故障阈值提升 3→10，冷却期缩短 (V3.2.0)
- 按模型变体隔离电路状态，避免单模型故障导致全局熔断 (V3.2.1)
- circuit-open 级联正确分类为 `KindCircuitOpen` 而非 unknown

### 诊断与修复工具
- `credentials_pkey` 序列失序诊断和自动修复脚本
- `request_logs.in_progress` 卡死修复 (3 个根因: 未设 status / 流中断未标记 / INSERT 失败静默)
- 凭据创建故障排查 SQL + 自动建议修复步骤
- 部署验证脚本套件 (attachments / version display / circuit fix)

### 性能优化
- `request_logs` 列表/详情分离投影 (避免全字段扫描)
- `provider_model` 反规范化到 `request_logs` (migration 057，消除 LATERAL JOIN)
- `request_status` 物化字段，移除读路径 COALESCE
- GIN trgm 索引支持 `?q=` 全文搜索
- listing-path 索引优化 (migration 056)

### 凭据与密钥管理
- NULL `key_ciphertext` 容错处理 (避免解密崩溃)
- `/api/keys/{id}/reveal` 结构化错误码
- 凭据+模型状态统一模块 (`credentialstate`)

### 版本显示
- `/api/system/version` 返回完整版本字符串 + build_seq
- 前端顶部栏简化显示为 `vX.X.X · #build_seq`
- 修复 VERSION 文件与 .deploy_seq 不同步导致的编译次数错误

### 日志与可观测性
- 大小限定的旋转日志文件 (`observability/rotate`)
- `UpstreamStatusCode` 字段补充到 `RequestLogEntry`
- 详细的 schema 迁移错误日志

### 路由与会话
- 凭据 disable 时清除会话偏好，避免 sticky session 卡住 (V3.1.1)
- 凭据+模型双重验证防抖动 (anti-flap)
- session preference 一致性修复

### Bug 修复
- Unicode 特殊字符 (§ 等) 导致的 SQL 语法错误
- PostgreSQL 兼容性: `ADD CONSTRAINT IF NOT EXISTS` → DO 块
- `model_aliases` 主键重复检查
- SQL schema 缩进和 WHERE 子句错误

### 文档
- 标准部署流程文档 (`DEPLOYMENT_STANDARD.md`)
- 20+ 部署报告、审计报告、验证脚本
- 各功能完整实施报告 (attachments / circuit / version display)

## V2.3 — 性能与会话管理

### 性能
- Provider 列表页加载耗时从 ~1s 降至 ~30ms（下降约 97%）
- 流式响应分片惰性解析优化
- 协议转换性能提升

### 会话管理
- 三个端点（chat / messages / responses）统一会话解析逻辑
- 滑动窗口会话过期机制（同时更新 TTL）
- 断线重连配置框架（默认禁用，按需启用）
- `request_logs` 增加 `client_request_id` 字段用于跨系统追踪

### 探活与重试
- 5 级 fallback 探活：手动 pin → request_logs 最常用 → featured_models 优先 → 随机 → 空
- 2s + 5s 短间隔重试机制专门吸收瞬时抖动（与长间隔重试互补）
- 4xx fail-fast 分类：除 400/401/402/403/404/422 外均重试
- 22 个新单元测试覆盖重试与 fallback 行为

## V2.2 — Schema 文档化与归档

### 数据库
- 完整 SQL schema 文档化（8 个模块化文件，按功能拆分）
- `request_logs_archive` 分层存储架构（heap → columnar 迁移）
- 历史数据按月分区 + 列式存储优化
- 150+ 数据库对象按类型逐个拆分为独立 SQL 文件

### 凭据指纹槽
- LRU 预占用 + 30 分钟自动回收
- 槽位上限默认 5 → 20
- 并发与指纹槽联合约束
- 自动建议值（`max(1, concurrency/4)`）由数据库触发器接管
- "恢复到建议值" UI 按钮
- 长期指纹占用稳定身份

### 路由 V2 统计
- 模型路由诊断工具 + Heatmap 热力图
- 指定模型（`__specified__`）请求统计
- `auto_route/analytics` Matrix + Flow 接口
- 路由质量门控（多层降级 + 成功率阈值）

## V2.1 — 可靠性与可观测性

### 错误分类
- 7 类错误处理矩阵（TRANSIENT / TIMEOUT / NETWORK / RATE_LIMIT / AUTH / QUOTA / UPSTREAM_DOWN）
- 不同恢复策略：临时 / 周期性（指数退避） / 永久（quarantine）
- 熔断器三态机：active → cooling → half_open → active
- 凭据级熔断 + 凭证池隔离

### 上游挂起硬超时
- 新增 `doUpstreamWithHardTimeout` 通过 goroutine + context 桥接
- 修复 `http.Client.Timeout` 失效问题
- 首次响应挂起时间从 200s+ 降至 130s 返回 503，断路器 44ms 返回

### 错误码修正
- `missing_model` 错误码统一从 503 改为 400
- 字段缺失/空串/空白/null 一致处理

### 可观测性
- CEF 日志格式 + FileSink 落地（SIEM 集成）
- LLM-as-judge 内容审核（Armor）
- Prometheus 指标扩展
- 审计流水线：事件通道 → 批量写入 → 死信回退

## V2.0 — 双路线架构

### 架构
- Python 控制面（供应商 / 凭据 / 模型 / 策略 / 日志查询）
- Go 数据面（身份隧道 / 流式中继 / 并发控制 / 审计）
- 4 阶段灰度上线策略（Python only → Go 旁路 → Go 主 Python 备用 → Go 全量）

### 身份隧道
- 同一 client_profile + device_seed 跨请求生成稳定 identity_hash
- 身份绑定连接池（虚拟身份 + 供应商 + 凭据共同决定池键）
- virtual_ip / virtual_mac 派生与上游头注入
- Go 与 Python 互操作性验证

### 凭据解密
- Fernet 对称加密（与 Python 兼容）
- 内存中明文 key TTL = 5 分钟
- 使用后栈帧覆写

## V1.0 — 基础

- Memora Gateway 起步：Go 高性能内存网关 for AI agents
- 基础路由与解析
- HTTP 请求生命周期
- 初始数据库 schema
