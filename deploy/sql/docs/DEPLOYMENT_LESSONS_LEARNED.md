# 部署经验总结：从失败到成功的完整复盘

> 日期：2026-06-30
> 编译号：716 → 718
> 目标：部署路由修复代码到生产环境 `llm.kxpms.cn`

---

## 一、架构理解（最重要）

### 生产架构
```
用户浏览器
    ↓ HTTPS
56服务器 ([PROD_SERVER_IP_56]) — 只运行 nginx，反向代理
    ↓ proxy_pass
71服务器 ([PROD_SERVER_IP_71]) — Docker 容器运行 llm-gateway-go
    ↓ 监听 :8781
容器内：/usr/local/bin/llm-gateway-go
```

### 关键认知
- **56服务器上没有 llm-gateway 实例**，它只是 nginx 跳转
- **71服务器才是真实部署**，通过 Docker 容器 + systemd 管理
- 在错误的机器上部署 = 白做

---

## 二、版本号的4个来源（核心教训）

前端网页显示的版本号来自 `/api/system/version` API，它的数据链路涉及 **4个独立的位置**：

| # | 文件/变量 | 用途 | 在哪里更新 |
|---|----------|------|-----------|
| 1 | `main.BuildNumber` (ldflags) | 启动日志中的 `build_number` | 编译时 `-ldflags` |
| 2 | `/opt/llm-gateway-go/VERSION` | `/healthz` API 返回的 version | Dockerfile `RUN echo` |
| 3 | `/opt/llm-gateway-go/web/dist/version.json` | 前端静态文件（备用） | Dockerfile `COPY` |
| 4 | **`/opt/llm-gateway-go/.deploy_seq`** | **`/api/system/version` 返回的 `build_seq`** | Dockerfile `RUN echo` |

### 版本号读取链路
```
前端 Vue.js
    ↓
fetch("/api/system/version")     ← 网页登录后调用
    ↓
admin/handler.go: handleSystemVersion()
    ↓
admin/misc.go: loadVersionInfo()
    ├── parseVersionString(VERSION文件) → version, git_sha, build_date
    └── loadDeploySeq() → 读取 .deploy_seq 文件 → build_seq
    ↓
返回 {"build_seq": N}    ← 前端显示的就是这个 N
```

### 教训
**只更新 VERSION 文件不够！** `.deploy_seq` 是独立的文件，必须同时更新。

---

## 三、编译注意事项

### 交叉编译（macOS → Linux）
```bash
# 必须指定目标平台
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -ldflags "-X 'main.Version=...' -X 'main.BuildNumber=718' ..." \
    -o bin/llm-gateway ./cmd/gateway
```

### ldflags 变量名
Go 的 ldflags 对变量名大小写敏感：
- ✅ 正确：`main.Version`、`main.BuildNumber`、`main.GitCommit`、`main.BuildTime`
- ❌ 错误：`main.version`（小写）、`main.build`

---

## 四、正确的 Docker 镜像构建

### 完整的 Dockerfile（增量构建）
```dockerfile
FROM kx-llm-gateway-go:gitsha-<旧commit>   # 基础镜像
USER root

# 1. 替换二进制
COPY llm-gateway /tmp/llm-gateway-go.new
RUN cp /tmp/llm-gateway-go.new /usr/local/bin/llm-gateway-go && \
    chmod +x /usr/local/bin/llm-gateway-go && \
    rm /tmp/llm-gateway-go.new

# 2. VERSION 文件（给 /healthz 用）
RUN echo "2.4.0-<sha>-<date>-718" > /opt/llm-gateway-go/VERSION

# 3. .deploy_seq 文件（给 /api/system/version 用，前端网页读这个！）
RUN echo "718" > /opt/llm-gateway-go/.deploy_seq

# 4. version.json（前端静态文件，备用）
COPY version.json /opt/llm-gateway-go/web/dist/version.json
```

### systemd 配置
```ini
# /etc/systemd/system/llm-gateway-go.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/docker run --rm --name llm-gateway-go --network host \
    --env-file /etc/llm-gateway-go/env \
    -v /opt/llm-gateway-go/data:/opt/llm-gateway-go/data \
    kx-llm-gateway-go:<新镜像标签>
```

---

## 五、部署流程（标准操作步骤）

```bash
# ── 1. 本地编译 ──
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -ldflags "-X 'main.Version=2.4.0-xxx-718' -X 'main.BuildNumber=718' ..." \
    -o bin/llm-gateway ./cmd/gateway

# ── 2. 上传到71 ──
scp -P [SSH_PORT] bin/llm-gateway root@[PROD_SERVER_IP_71]:/opt/build-src/
scp -P [SSH_PORT] version.json root@[PROD_SERVER_IP_71]:/opt/build-src/

# ── 3. 在71上构建镜像 ──
ssh -p [SSH_PORT] root@[PROD_SERVER_IP_71]
cd /opt/build-src
docker build -f Dockerfile -t kx-llm-gateway-go:gitsha-<sha>-r718 .

# ── 4. 更新 systemd override ──
# 修改 /etc/systemd/system/llm-gateway-go.service.d/override.conf

# ── 5. 重启服务 ──
systemctl daemon-reload
systemctl restart llm-gateway-go.service

# ── 6. 验证（4个地方都要查）──
docker logs llm-gateway-go | grep "gateway starting"        # build_number
docker exec llm-gateway-go cat /opt/llm-gateway-go/VERSION   # healthz
docker exec llm-gateway-go cat /opt/llm-gateway-go/.deploy_seq  # 网页！
curl -s https://llm.kxpms.cn/version.json | grep build_seq
```

---

## 六、犯过的错误记录

| 错误 | 原因 | 后果 |
|------|------|------|
| 在56服务器部署 | 56只是nginx，没有实例 | 完全无效 |
| 用macOS编译的二进制 | 没有交叉编译 | 二进制无法运行 |
| ldflags 用小写变量名 | Go区分大小写 | build_number 为空 |
| 只更新 VERSION 文件 | 不知道有 .deploy_seq | 网页一直显示716 |
| 在56启动临时进程 | 误以为是后端 | 干扰判断 |
| 没读前端JS代码 | 假设前端读 version.json | 没找到真正的API |

---

## 七、验证检查清单

部署后必须逐项确认：

- [ ] `docker logs llm-gateway-go` → build_number 正确
- [ ] `/healthz` → version 正确
- [ ] `/version.json` → build_seq 正确
- [ ] **`/api/system/version`** → build_seq 正确（前端网页实际调用的）
- [ ] 浏览器无痕模式打开网页 → 版本号正确
- [ ] API 功能测试 → 请求成功

---

## 八、核心教训

1. **先理解架构再动手**：搞清楚哪个机器、哪个进程、哪个容器才是真正的服务
2. **读代码定位数据来源**：前端显示的数字从哪个API来、后端从哪个文件读
3. **不要假设，要验证**：curl 每一个可能的端点，确认数据链路
4. **全面更新所有版本文件**：VERSION、.deploy_seq、version.json 一个都不能少
5. **看前端JS怎么调用**：不是看后端有什么，而是看前端实际用了什么
