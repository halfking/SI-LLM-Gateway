# Deployment

> 高层部署说明。具体服务器地址、密钥、命令参数不在此处记录。

## 部署前准备

- PostgreSQL 15.x（含 `pg_trgm`、`citus_columnar` 扩展）
- Redis（用于限流与粘性会话）
- Go 1.21+ 构建工具链
- 容器运行时（Docker / k3s / 宿主机 systemd 任选其一）

## 数据库初始化

数据库 schema 全部资产位于 [`deploy/sql/`](./deploy/sql/) 目录下，按以下顺序执行：

```text
deploy/sql/
├── 00_schema/           # 表结构（按功能拆分，8 个文件）
├── 01_functions/        # 函数与触发器
├── 02_seed_data/        # 最小初始化数据
├── migrations/          # 历史迁移（按编号顺序执行）
├── objects/             # 生产数据库实时对象快照（只读参考）
├── docs/                # 文档 SQL
├── adhoc/               # 临时/诊断脚本
└── scripts/init-db.sh   # 自动化初始化脚本
```

### 全新数据库初始化

依次执行 `00_schema/` 8 个文件 → `01_functions/` → `02_seed_data/`。或直接运行 `init-db.sh`：

```bash
DB_HOST=... DB_USER=... DB_NAME=llm_gateway ./deploy/sql/scripts/init-db.sh
```

### 增量更新（已有库）

按编号顺序执行 `deploy/sql/migrations/*.sql` 中的迁移文件。`db.Open()` 启动时也会自动应用部分幂等 DDL 收敛 schema。

## 应用编译

```bash
go build -o bin/llm-gateway ./cmd/gateway
```

前端（Vue 3 + Vite）：

```bash
cd web && npm install && npm run build
```

## 服务启动

网关进程读取 `DATABASE_URL`、`REDIS_URL` 等环境变量。具体密钥与端点配置在外部 secret 管理工具中维护。

启动方式三选一：

- **容器**：`docker run` / `kubectl apply` / k3s manifest
- **systemd**：`systemctl restart llm-gateway`
- **裸进程**：`./bin/llm-gateway`

## 健康检查

| 端点 | 用途 |
|---|---|
| `GET /healthz` | 进程存活 |
| `GET /readyz` | 数据库/Redis 依赖就绪 |
| `GET /api/health` | 业务级健康概览 |

## 升级流程

1. 拉取最新代码
2. 重启前先停止流量（或使用灰度发布）
3. 重启进程（`db.Open()` 自动收敛幂等 DDL）
4. 健康检查通过后恢复流量
5. 监控关键指标：P99 延迟、错误率、`no_candidates` 路由空集告警

## 数据归档

`request_logs` 按月分区写入。历史数据可由以下函数迁移到列式存储：

- `archive_request_logs(month)` — 迁移单月数据到 `request_logs_archive`
- `ensure_next_month_archive_partition()` — 预创建下月列式分区

## 故障恢复

| 场景 | 措施 |
|---|---|
| 进程崩溃 | systemd / k8s 自动重启 |
| 数据库不可达 | 健康检查失败 → 流量切换备用网关 |
| 凭据级熔断打开 | 自动冷却 → 探测 → 自动恢复 |
| 上游持续 5xx | 触发指数退避，最长 30 分钟冷却 |

详见 [`deploy/sql/README.md`](./deploy/sql/README.md) 与 [`ARCHITECTURE.md`](./ARCHITECTURE.md)。
