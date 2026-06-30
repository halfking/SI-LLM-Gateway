# 🚀 部署包 - Minimax-m3 路由问题修复

## 📦 需要传输的文件

1. **二进制文件**: `bin/llm-gateway` (41MB)
2. **部署脚本**: `deploy_on_71.sh`
3. **测试脚本**: `scripts/test_71_complete.sh`

## 📋 部署步骤

### 步骤1: 传输文件到71服务器

```bash
# 方法1: 使用scp（如果有网络访问）
scp bin/llm-gateway root@192.168.1.71:/tmp/
scp deploy_on_71.sh root@192.168.1.71:/tmp/
scp scripts/test_71_complete.sh root@192.168.1.71:/tmp/

# 方法2: 使用其他传输方式
# - 通过跳板机
# - 使用U盘/共享文件夹
# - 其他可用方式
```

### 步骤2: 连接到71服务器

```bash
ssh root@192.168.1.71
# 或使用其他可用的连接方式
```

### 步骤3: 执行部署

```bash
cd /tmp
chmod +x deploy_on_71.sh
sudo bash deploy_on_71.sh
```

脚本会提示确认，输入 `yes` 继续。

### 步骤4: 验证部署

部署完成后，脚本会自动检查服务状态。额外验证：

```bash
# 检查服务状态
systemctl status llm-gateway

# 查看最近日志
journalctl -u llm-gateway -n 50

# 监控实时日志（Ctrl+C退出）
journalctl -u llm-gateway -f
```

### 步骤5: 运行测试（可选）

```bash
cd /tmp
chmod +x test_71_complete.sh
./test_71_complete.sh
```

## 🔍 关键监控指标

部署后持续监控这些指标：

### 1. 服务日志
```bash
# 查看错误日志
journalctl -u llm-gateway --since "10 min ago" | grep -E "ERROR|error|WARN"

# 查看路由相关日志
journalctl -u llm-gateway --since "10 min ago" | grep -E "no_candidate|empty_response|filtered.*health"
```

### 2. 数据库指标（需要数据库访问）
```bash
export LLM_GATEWAY_DATABASE_URL="postgresql://..."

# No Candidate 错误率
psql "$LLM_GATEWAY_DATABASE_URL" -c "
SELECT 
    COUNT(*) FILTER (WHERE error_kind = 'no_candidate') as no_candidate,
    COUNT(*) as total_requests,
    ROUND(COUNT(*) FILTER (WHERE error_kind = 'no_candidate')::numeric / NULLIF(COUNT(*), 0) * 100, 2) as error_rate
FROM request_logs
WHERE client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '1 hour';
"

# Empty Response 错误率
psql "$LLM_GATEWAY_DATABASE_URL" -c "
SELECT 
    COUNT(*) FILTER (WHERE error_kind = 'empty_response') as empty_response,
    COUNT(*) as total_requests,
    ROUND(COUNT(*) FILTER (WHERE error_kind = 'empty_response')::numeric / NULLIF(COUNT(*), 0) * 100, 2) as error_rate
FROM request_logs
WHERE client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '1 hour';
"
```

## 🛡️ 回滚方案

如果部署后出现问题：

```bash
# 停止服务
systemctl stop llm-gateway

# 恢复备份（使用部署时生成的备份文件名）
cp /opt/llm-gateway-go/llm-gateway.backup-TIMESTAMP /opt/llm-gateway-go/llm-gateway

# 启动服务
systemctl start llm-gateway

# 检查状态
systemctl status llm-gateway
```

## 📊 成功标准

部署成功的标志（24小时内观察）：

- ✅ 服务启动正常，无频繁重启
- ✅ No Candidate 错误率 < 1%（之前可能很高）
- ✅ Empty Response 错误率显著下降（目标 < 5%）
- ✅ 整体请求成功率保持或提升
- ✅ 没有新的错误类型出现

## 🔧 排查问题

如果遇到问题：

1. **服务无法启动**
   ```bash
   journalctl -u llm-gateway -n 100
   # 查看启动错误
   ```

2. **性能下降**
   ```bash
   # 检查CPU/内存使用
   top -b -n 1 | grep llm-gateway
   ```

3. **新的错误出现**
   ```bash
   # 查看所有错误
   journalctl -u llm-gateway --since "deployment_time" | grep -i error
   ```

## 📞 支持

- 完整分析文档: `PROBLEM_ANALYSIS_AND_FIX.md`
- 测试工具文档: `README_TESTING_TOOLS.md`
- 快速指南: `QUICK_START_TESTING.md`

## ✨ 修复内容

1. **路由健康检查阈值调整**
   - 失败阈值: 3 → 5 次
   - 冷却时间: 5分钟 → 3分钟

2. **Empty Response 检测改进**
   - 增加 chunk_count == 1 的short-circuit
   - 增加响应时间 < 2秒的short-circuit

3. **Fallback机制**
   - 当所有节点被过滤时启用宽容模式
   - 防止 "no candidate" 错误
