# 专用测试脚本

本目录包含特定场景的测试脚本，补充核心测试脚本（`../test.sh`）的功能。

## 📋 脚本说明

### 完整测试
- `test_71_complete.sh` - 71服务器完整测试套件
  - 涵盖服务健康检查、API验证、路由测试等
  - 适用于生产环境部署后验证

### 性能测试
- `test_local_concurrency.sh` - 本地并发性能测试
  - 测试网关在高并发下的性能表现
  - 包含压力测试和稳定性测试

### 路由测试
- `test_local_routing.sh` - 本地路由功能测试
  - 详细的路由逻辑测试
  - 包含各种边界情况和异常场景

## 🚀 使用方法

```bash
# 71服务器完整测试
./scripts/testing/test_71_complete.sh

# 本地并发测试
./scripts/testing/test_local_concurrency.sh

# 本地路由测试
./scripts/testing/test_local_routing.sh
```

## 🎯 与核心测试脚本的区别

| 脚本类型 | 用途 | 场景 |
|---------|------|------|
| `../test.sh` | 快速功能测试 | 开发、CI/CD |
| `test_71_complete.sh` | 完整集成测试 | 生产部署后 |
| `test_local_concurrency.sh` | 性能测试 | 性能调优 |
| `test_local_routing.sh` | 深度路由测试 | 路由问题排查 |

## 💡 推荐使用场景

1. **日常开发**: 使用 `../test.sh`
2. **生产部署后**: 使用 `test_71_complete.sh`
3. **性能调优**: 使用 `test_local_concurrency.sh`
4. **路由调试**: 使用 `test_local_routing.sh`

## ⚠️ 注意事项

1. 这些测试可能需要特定的环境配置
2. 并发测试会产生大量请求，注意资源使用
3. 生产环境测试请在低峰期执行

## 📖 相关文档

- 核心测试脚本：`../test.sh --help`
- 主脚本目录：`../README.md`
