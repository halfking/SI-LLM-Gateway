# LLM Gateway 部署标准规范

## 📋 版本更新检查清单

### 必须更新的文件（按顺序）

| # | 文件路径 | 说明 | 格式 |
|---|---------|------|------|
| 1 | `VERSION` | 后端版本文件 | `<major>.<minor>.<patch>-<git_sha>-<YYYYMMDD>-<seq>` |
| 2 | `version.json` | 后端版本JSON | 完整JSON格式（见模板） |
| 3 | `web/public/version.json` | 前端版本JSON | 与后端version.json一致 |
| 4 | `web/dist/version.json` | 前端构建产物中的版本JSON | 与 3 一致 |
| 5 | `.deploy_seq` | 单文件 build_seq（被 `/api/system/version` 直接读取） | 单个整数 |
| 6 | Go 二进制 ldflags | 注入 `main.Version` / `main.BuildNumber` / `main.GitCommit` / `main.BuildTime` | `-ldflags "-X 'main.X=Y' ..."` |

> **2026-07-02 注**: `/api/system/version` 的 `build_seq` 字段**不**从 VERSION 文件解析，而是从 `.deploy_seq` 单文件读取（`admin/misc.go loadDeploySeq`）。只更新 VERSION 而忘记 `.deploy_seq` 会导致前端 build_seq 卡在旧值。

### ⚡ 推荐方式：`scripts/bump-version.sh` 一键同步

```bash
# 跳号到指定值（如 721）+ 部署到 71
SSHPASS='Kaixuan2026&#*9527' ./scripts/bump-version.sh --seq 721 --ssh root@14.103.174.71

# 自动递增（默认 +1）
SSHPASS='Kaixuan2026&#*9527' ./scripts/bump-version.sh --ssh root@14.103.174.71

# 仅修改文件，不构建不上传
./scripts/bump-version.sh --seq 722 --no-build --no-upload

# 完整一行式部署（默认 +1 + 跳过前端构建）
SSHPASS='Kaixuan2026&#*9527' ./scripts/deploy-71.sh
```

`bump-version.sh` 自动：
1. 从 `version.json` 读取当前 `build_seq`（single source of truth）
2. 更新 5 个文件 + ldflags 注入 + cross-compile linux/amd64
3. Stop 服务（释放 binary mmap 锁）→ scp 4 个文件到 71 → Start 服务
4. 重新加载 systemd

### ❌ 常见错误

- ❌ **只更新后端版本，忘记前端**
- ❌ **只更新 `version.json`，忘记 `VERSION` 文件**
- ❌ **只更新 `VERSION`，忘记 `.deploy_seq`**（前端 build_seq 卡旧值）
- ❌ **编译时未使用 `-ldflags` 注入版本信息**
- ❌ **容器挂载的文件路径搞错**
- ❌ **没有重新构建前端**
- ❌ **跨主机架构 scp**：开发机是 darwin/arm64，必须 `GOOS=linux GOARCH=amd64` 交叉编译，否则 docker exec 报 `exec format error`

---

## 📝 版本号规范

### 格式

```
<major>.<minor>.<patch>-<git_sha>-<YYYYMMDD>-<build_seq>
```

### 示例

```
2.3.2-edb6fa85-20260701-717
```

### 字段说明

- `major.minor.patch`: 语义化版本
  - `major`: 破坏性变更
  - `minor`: 新功能（向后兼容）
  - `patch`: Bug修复
- `git_sha`: 8位git commit hash
- `YYYYMMDD`: 构建日期
- `build_seq`: 递增的构建序号（从上一个版本递增）

### 前端显示格式

**重要**: 前端只显示简化的语义化版本，不是完整版本字符串。

- **VERSION文件内容**: `2.3.2-edb6fa85-20260701-717` (完整格式)
- **前端显示**: `v2.3.2 · #717` (简化格式)

`/api/system/version` API 返回：
```json
{
  "version": "2.3.2",           // 只返回语义化版本部分
  "git_sha": "edb6fa85",        // Git哈希单独返回
  "build_date": "2026-07-01",   // 构建日期单独返回
  "build_seq": 717              // 构建序号单独返回
}
```

前端显示位置：右上角用户信息栏

### version.json 模板

```json
{
  "version": "2.3.2-edb6fa85-20260701-717",
  "git_tag": "2.3.2-edb6fa85-20260701-717",
  "git_sha": "edb6fa85",
  "build_seq": 717,
  "build_date": "2026-07-01",
  "module": "llm-gateway-go-2"
}
```

---

## 🔧 编译步骤

### 1. 更新版本文件

```bash
# 确定版本信息
VERSION="2.3.2-edb6fa85-20260701-717"
GIT_SHA="edb6fa85"
BUILD_SEQ="717"
BUILD_DATE="2026-07-01"

# 更新 VERSION
echo "$VERSION" > VERSION

# 更新 version.json
cat > version.json <<EOF
{
  "version": "$VERSION",
  "git_tag": "$VERSION",
  "git_sha": "$GIT_SHA",
  "build_seq": $BUILD_SEQ,
  "build_date": "$BUILD_DATE",
  "module": "llm-gateway-go-2"
}
EOF

# 更新前端 version.json（必须！）
cp version.json web/public/version.json
```

### 2. 编译后端

**必须使用 -ldflags 注入版本信息！**

```bash
VERSION="2.3.2-edb6fa85-20260701-717"
GIT_COMMIT="edb6fa85"
BUILD_NUMBER="717"
BUILD_TIME=$(date -u '+%Y-%m-%d %H:%M:%S')

GOOS=linux GOARCH=amd64 go build \
  -ldflags "-X 'main.Version=${VERSION}' \
            -X 'main.BuildNumber=${BUILD_NUMBER}' \
            -X 'main.GitCommit=${GIT_COMMIT}' \
            -X 'main.BuildTime=${BUILD_TIME}'" \
  -o llm-gateway-linux-amd64-v${BUILD_NUMBER} \
  ./cmd/gateway
```

### 3. 构建前端

```bash
cd web
npm run build
cd ..
```

### 4. 验证版本信息

```bash
# 检查前端构建产物中的version.json
cat web/dist/version.json

# 检查是否包含正确的版本号
grep "$VERSION" web/dist/version.json
```

### 5. 打包部署包

```bash
tar czf deploy-full-$(date +%Y%m%d)-v${BUILD_NUMBER}.tar.gz \
  llm-gateway-linux-amd64-v${BUILD_NUMBER} \
  web/dist \
  VERSION \
  version.json \
  scripts/deploy_*.sh \
  *.md
```

---

## 🖥️ 服务器资源清单

### 71 服务器 (14.103.174.71)

**连接信息**:
- 主机: `14.103.174.71`
- SSH端口: `25022`
- 用户: `root`

**服务架构**:
- 运行方式: Docker容器（Alpine 3.20）
- 容器名: `llm-gateway-go`
- 自动重启: 是（停止后自动重新创建）

**关键路径**:

| 路径 | 用途 | 挂载 |
|------|------|------|
| `/opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64` | 后端二进制 | ✅ 挂载到容器 |
| `/opt/llm-gateway-go/VERSION` | 版本文件（API读取） | ✅ 需要部署 |
| `/opt/llm-gateway-go/web/dist/` | 前端静态文件 | ✅ 挂载到容器 |
| `/opt/llm-gateway-go/data/` | 数据目录 | ✅ 挂载到容器 |
| `/opt/llm-gateway-go/data/attachments/` | 附件存储 | ✅ 挂载到容器 |

**容器配置**:
- Entrypoint: `/opt/llm-gateway-go/llm-gateway-go`
- 监听端口: `8781`
- 数据库: `127.0.0.1:5432` (宿主机PostgreSQL)

**数据库**:
- 主机: `127.0.0.1:5432`
- 数据库: `llm_gateway`
- 用户: `llm_gateway`
- 密码: `4Q92cFTaYY8Z3AO07XTBBH-1g7kceaxg`

---

## 🚀 部署步骤

### ⚠️ 前置检查

```bash
# 1. 确认所有版本文件已更新
ls -l VERSION version.json web/public/version.json

# 2. 确认二进制已编译（带版本信息）
ls -lh llm-gateway-linux-amd64-v*

# 3. 确认前端已构建
ls -l web/dist/version.json

# 4. 确认版本号一致
VERSION=$(cat VERSION)
grep "$VERSION" version.json
grep "$VERSION" web/public/version.json
grep "$VERSION" web/dist/version.json
```

### 📦 上传部署包

```bash
sshpass -p '<PASSWORD>' scp -P 25022 \
  deploy-full-*.tar.gz \
  root@14.103.174.71:/tmp/
```

### 🔄 执行部署

**步骤1: 解压部署包**

```bash
ssh root@14.103.174.71 -p 25022
cd /tmp
tar xzf deploy-full-*.tar.gz
```

**步骤2: 停止容器**

```bash
docker stop llm-gateway-go
sleep 2
```

**步骤3: 备份当前版本**

```bash
cd /opt/llm-gateway-go
cp llm-gateway-go.v321.linux.amd64 \
   llm-gateway-go.v321.linux.amd64.backup.$(date +%Y%m%d_%H%M%S)
```

**步骤4: 部署后端**

```bash
# 部署二进制（注意：必须是 v321 文件！）
cp /tmp/llm-gateway-linux-amd64-v* \
   /opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64
chmod +x /opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64

# 部署VERSION文件（API会读取）
cp /tmp/VERSION /opt/llm-gateway-go/VERSION
```

**步骤5: 部署前端**

```bash
# 备份旧前端
rm -rf /opt/llm-gateway-go/web/dist.old
mv /opt/llm-gateway-go/web/dist \
   /opt/llm-gateway-go/web/dist.old

# 部署新前端
cp -r /tmp/web/dist /opt/llm-gateway-go/web/

# 确保version.json在dist目录
cp /tmp/web/public/version.json \
   /opt/llm-gateway-go/web/dist/version.json
```

**步骤6: 等待容器自动启动**

```bash
sleep 5
docker ps | grep llm-gateway-go
```

### ✅ 部署验证

**1. 检查容器状态**

```bash
docker ps | grep llm-gateway-go
# 应该显示 Up X seconds
```

**2. 检查后端版本（启动日志）**

```bash
docker logs llm-gateway-go 2>&1 | grep "gateway starting" | tail -1
```

应该显示：
```json
{
  "version": "2.3.2-edb6fa85-20260701-717",
  "build_number": "717",
  "git_commit": "edb6fa85",
  "build_time": "2026-07-01 14:15:06"
}
```

**3. 检查VERSION文件**

```bash
cat /opt/llm-gateway-go/VERSION
# 应该显示: 2.3.2-edb6fa85-20260701-717
```

**4. 检查前端version.json**

```bash
cat /opt/llm-gateway-go/web/dist/version.json
# 应该包含正确的版本信息
```

**5. 检查服务健康**

```bash
curl -s http://localhost:8781/healthz | jq
```

**6. 检查前端访问**

```bash
curl -s http://localhost:8781/ | grep "LLM Gateway"
```

**7. 检查前端版本显示（需要登录后验证）**

登录前端后，查看右上角版本号显示：

**期望显示格式**: `v2.3.2 · #717`

- ✅ 版本号为简化格式（`v2.3.2`），不是完整版本字符串
- ✅ 构建序号显示为 `#717`
- ✅ 样式正确（版本号紫色、构建序号灰色）

**错误示例**:
- ❌ `v2.3.2-edb6fa85-20260701-717` (完整版本字符串 - 错误)
- ❌ `v0.1.0` (默认值 - 说明VERSION文件未读取)
- ❌ `v2.3.2 · #0` (构建序号为0 - 说明.deploy_seq文件未读取)

**验证方式**:
```
1. 打开 http://14.103.174.71:8781
2. 使用管理员账号登录
3. 查看右上角：[用户名] · [角色] · vX.X.X · #NNN
4. 确认格式正确
```

---

## ❌ 禁止操作

### 部署时禁止

1. ❌ **禁止直接修改 `llm-gateway-go` 文件**
   - 容器实际挂载的是 `llm-gateway-go.v321.linux.amd64`
   
2. ❌ **禁止使用 `docker restart` 替换二进制**
   - 文件被占用无法替换，必须先 `docker stop`

3. ❌ **禁止跳过前端构建**
   - 前端version.json必须重新打包到dist/

4. ❌ **禁止只更新二进制不更新VERSION文件**
   - API从VERSION文件读取版本，不是从二进制

5. ❌ **禁止跳过版本验证步骤**
   - 部署后必须验证前后端版本一致

### 编译时禁止

1. ❌ **禁止不带 -ldflags 编译**
   - Version等变量必须在编译时注入

2. ❌ **禁止版本号不一致**
   - VERSION、version.json、web/public/version.json 必须一致

3. ❌ **禁止跳过前端构建**
   - web/dist/ 必须包含最新的version.json

---

## 🔄 回滚流程

### 快速回滚

```bash
# 1. 停止容器
docker stop llm-gateway-go

# 2. 恢复二进制
cd /opt/llm-gateway-go
cp llm-gateway-go.v321.linux.amd64.backup.YYYYMMDD_HHMMSS \
   llm-gateway-go.v321.linux.amd64

# 3. 恢复VERSION文件（如果有备份）
cp VERSION.backup.YYYYMMDD_HHMMSS VERSION

# 4. 恢复前端（如果有备份）
rm -rf web/dist
mv web/dist.old web/dist

# 5. 等待容器自动启动
sleep 5
docker ps | grep llm-gateway-go
```

### 回滚验证

```bash
# 检查版本是否回滚成功
docker logs llm-gateway-go 2>&1 | grep "gateway starting" | tail -1
cat /opt/llm-gateway-go/VERSION
```

---

## 📊 版本历史记录

### 版本更新日志格式

```markdown
## v2.3.2-edb6fa85-20260701-717

**发布日期**: 2026-07-01  
**Git Commit**: edb6fa85  
**构建序号**: 717  

**新增功能**:
- 附件归档功能（支持图片自动归档）
- Admin API 附件下载接口

**Bug修复**:
- 修复Anthropic→OpenAI图片转换丢失问题
- 修复OpenAI→Anthropic data URL被拒问题
- 修复attachmentCount永远是0的问题

**部署影响**:
- 需要更新前后端
- 需要部署VERSION文件
- 数据库已就绪，无需migration
```

---

## 🛠️ 故障排查

### 问题1: 前端显示的版本号不正确

**检查清单**:
1. ✅ VERSION文件是否部署？ `cat /opt/llm-gateway-go/VERSION`
2. ✅ 前端version.json是否部署？ `cat /opt/llm-gateway-go/web/dist/version.json`
3. ✅ 容器是否重启？ `docker ps | grep llm-gateway-go`
4. ✅ 用户是否已登录？（未登录不会调用version API）

**解决方案**:
```bash
# 补充部署VERSION文件
echo "2.3.2-edb6fa85-20260701-717" > /opt/llm-gateway-go/VERSION
docker restart llm-gateway-go
```

### 问题2: 后端启动日志显示版本为空

**原因**: 编译时未使用 -ldflags

**解决方案**: 重新编译，必须带 -ldflags 参数

### 问题3: 容器停止后无法启动

**原因**: 有自动重启机制，会自动创建新容器

**解决方案**: 等待5-10秒，检查新容器ID

### 问题4: 二进制文件无法替换（Text file busy）

**原因**: 容器正在使用该文件

**解决方案**: 必须先 `docker stop llm-gateway-go`

---

## 📚 参考命令速查

### 版本检查

```bash
# 后端版本（启动日志）
docker logs llm-gateway-go | grep "gateway starting" | tail -1

# VERSION文件
cat /opt/llm-gateway-go/VERSION

# 前端version.json
curl -s http://localhost:8781/version.json | jq

# 数据库连接测试
PGPASSWORD='4Q92cFTaYY8Z3AO07XTBBH-1g7kceaxg' \
  psql -h 127.0.0.1 -p 5432 -U llm_gateway -d llm_gateway -c '\dt'
```

### 容器管理

```bash
# 查看容器
docker ps | grep llm-gateway-go

# 查看日志
docker logs llm-gateway-go -f

# 停止容器
docker stop llm-gateway-go

# 容器会自动重启，无需手动start
```

### 服务测试

```bash
# 健康检查
curl -s http://localhost:8781/healthz | jq

# 前端首页
curl -s http://localhost:8781/ | head -20

# 附件功能测试
docker logs llm-gateway-go | grep attachment
```

---

## 📝 部署检查清单（打印版）

```
部署前检查:
□ VERSION文件已更新
□ version.json已更新
□ web/public/version.json已更新
□ 后端已编译（带-ldflags）
□ 前端已构建（npm run build）
□ 部署包已打包
□ 版本号在所有文件中一致

部署步骤:
□ 上传部署包到/tmp
□ 停止容器（docker stop）
□ 备份旧二进制
□ 部署新二进制到v321文件
□ 部署VERSION文件
□ 备份旧前端
□ 部署新前端dist/
□ 等待容器自动启动

部署后验证:
□ 容器状态正常（Up）
□ 后端版本日志正确
□ VERSION文件正确
□ 前端version.json正确
□ /healthz返回200
□ 前端页面可访问
□ （登录后）版本号显示正确
```

---

**最后更新**: 2026-07-02  
**维护者**: Kiro AI  
**版本**: 1.1 (2026-07-02: 增加 `bump-version.sh` 一键脚本说明 + `.deploy_seq` 同步要求)
