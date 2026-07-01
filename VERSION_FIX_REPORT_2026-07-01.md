# ✅ 版本信息修正报告

**修正日期**：2026-07-01 22:17  
**问题**：部署后版本信息不正确  
**状态**：✅ 已修正  

---

## 🐛 问题描述

初次部署后，服务启动日志显示：

```json
{
  "version": "v2.3.1-routing-fix",
  "build_number": "",        // ❌ 空
  "git_commit": "",          // ❌ 空
  "build_time": "2026-07-01 14:06:05"
}
```

**问题根因**：
1. 编译时未使用 `-ldflags` 注入版本信息
2. VERSION 和 version.json 未更新到最新版本

---

## 🔧 修正措施

### 1. 更新版本文件

**VERSION**：
```
2.3.2-edb6fa85-20260701-717
```

**version.json**：
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

**版本号说明**：
- `2.3.2`：从 2.3.0 升级（新增附件归档功能，minor版本升级）
- `edb6fa85`：附件功能的 git commit hash
- `20260701`：构建日期
- `717`：构建序号（从716递增）

### 2. 使用正确的 ldflags 重新编译

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
  -o llm-gateway-linux-amd64-v717 \
  ./cmd/gateway
```

### 3. 部署到71服务器

**关键发现**：容器实际挂载的是 `/opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64` 而不是 `llm-gateway-go`。

**部署步骤**：
```bash
# 1. 停止容器
docker stop llm-gateway-go

# 2. 备份旧版本
cp llm-gateway-go.v321.linux.amd64 llm-gateway-go.v321.linux.amd64.backup.20260701_221729

# 3. 部署新版本
cp /tmp/llm-gateway-linux-amd64-v717 llm-gateway-go.v321.linux.amd64
chmod +x llm-gateway-go.v321.linux.amd64

# 4. 容器自动重启
```

---

## ✅ 验证结果

### 启动日志

```json
{
  "time": "2026-07-01T14:17:29.022Z",
  "level": "INFO",
  "msg": "gateway starting",
  "listen": ":8781",
  "log_level": "debug",
  "version": "2.3.2-edb6fa85-20260701-717",    // ✅ 正确
  "build_number": "717",                         // ✅ 正确
  "git_commit": "edb6fa85",                      // ✅ 正确
  "build_time": "2026-07-01 14:15:06"           // ✅ 正确
}
```

### 功能模块

```json
{"level":"INFO","msg":"attachment manager enabled","storage_path":"./data/attachments","max_size_mb":10}
{"level":"INFO","msg":"attachment download API enabled (/api/admin/attachments/)"}
```

✅ 所有模块正常初始化

---

## 📊 对比

| 字段 | 修正前 | 修正后 |
|------|--------|--------|
| version | v2.3.1-routing-fix | 2.3.2-edb6fa85-20260701-717 ✅ |
| build_number | (空) | 717 ✅ |
| git_commit | (空) | edb6fa85 ✅ |
| build_time | 编译时间 | 2026-07-01 14:15:06 ✅ |

---

## 🎯 规范要求

根据项目规范，版本号格式为：

```
<major>.<minor>.<patch>-<git_sha>-<date>-<build_seq>
```

示例：`2.3.2-edb6fa85-20260701-717`

**字段说明**：
- `major.minor.patch`：语义化版本
- `git_sha`：8位 git commit hash
- `date`：YYYYMMDD 格式
- `build_seq`：递增的构建序号

---

## 🔄 回滚准备

**备份位置**：
```
/opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64.backup.20260701_221729
```

**回滚命令**：
```bash
docker stop llm-gateway-go
cp /opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64.backup.20260701_221729 \
   /opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64
# 等待容器自动重启
```

---

## 📝 经验教训

1. **编译时必须使用 ldflags**：不能依赖代码中的默认值
2. **容器挂载路径要确认**：不要假设挂载的是哪个文件
3. **版本文件要同步更新**：VERSION 和 version.json 必须一致
4. **版本号要遵守规范**：格式必须符合项目约定

---

## ✅ 结论

**问题状态**：✅ 已完全修正

**当前版本**：2.3.2-edb6fa85-20260701-717

**下一步**：开始开发 Admin 前端 UI，显示附件徽标和图片预览

---

**报告生成时间**：2026-07-01 22:18
