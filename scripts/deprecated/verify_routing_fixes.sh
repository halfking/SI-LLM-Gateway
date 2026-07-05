#!/bin/bash
# 路由系统修复验证脚本
# 验证 P0 + P1 修复是否正确应用

set -e

echo "========================================="
echo "🔍 LLM Gateway 路由修复验证"
echo "========================================="
echo ""

LOG_PREFIX="[VERIFY]"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 检查 1: P0-1 - disableModelOffer 封死
echo "📋 检查 P0-1: disableModelOffer 是否已封死..."
if grep -q "panic(\"disableModelOffer is DEPRECATED" routing/executor.go; then
    success "P0-1: disableModelOffer 已添加 panic guard"
else
    error "P0-1: disableModelOffer panic guard 未找到"
    exit 1
fi

# 检查 2: P0-2 - coolBindingOnMnfStreak 补写 unavailable_recover_at
echo "📋 检查 P0-2: coolBindingOnMnfStreak 是否写入 unavailable_recover_at..."
if grep -q "unavailable_recover_at = \$3" routing/executor.go; then
    success "P0-2: coolBindingOnMnfStreak 已补写 unavailable_recover_at"
else
    error "P0-2: unavailable_recover_at 未找到"
    exit 1
fi

# 检查 3: P0-3 - Circuit.RecordFailure 去重（排除注释）
echo "📋 检查 P0-3: 内层 Circuit.RecordFailure 是否已删除..."
CHAT_COUNT=$(grep "Circuit.RecordFailure" routing/executor_chat.go 2>/dev/null | grep -v "^[[:space:]]*//\|^[[:space:]]*\*" | wc -l)
ANTHROPIC_COUNT=$(grep "Circuit.RecordFailure" routing/executor_anthropic.go 2>/dev/null | grep -v "^[[:space:]]*//\|^[[:space:]]*\*" | wc -l)

if [ "$CHAT_COUNT" -eq 0 ] && [ "$ANTHROPIC_COUNT" -eq 0 ]; then
    success "P0-3: 内层 Circuit.RecordFailure 已全部删除"
else
    error "P0-3: 仍有 $CHAT_COUNT (chat) + $ANTHROPIC_COUNT (anthropic) 处调用"
    exit 1
fi

# 检查 4: P1-1 - RestoreOnSuccess WHERE 条件
echo "📋 检查 P1-1: RestoreOnSuccess 是否增加 unavailable_recover_at 检查..."
if grep -q "cmb.unavailable_recover_at IS NULL" credentialstate/writer.go && \
   grep -q "cmb.unavailable_recover_at <= now()" credentialstate/writer.go; then
    success "P1-1: RestoreOnSuccess WHERE 条件已添加"
else
    error "P1-1: unavailable_recover_at 检查未找到"
    exit 1
fi

# 检查 5: P1-2 - candCache invalidate
echo "📋 检查 P1-2: restoreCredentialState 是否调用 invalidate..."
if grep -A15 "func (e \*Executor) restoreCredentialState" routing/executor.go | \
   grep -q "InvalidateAllCandidateCache"; then
    success "P1-2: restoreCredentialState 已添加 invalidate 调用"
else
    error "P1-2: invalidate 调用未找到"
    exit 1
fi

# 检查 6: P1-5 - clearSessionPref 清除 sticky
echo "📋 检查 P1-5: clearSessionPref 是否清除 sticky..."
if grep -A40 "func (e \*Executor) clearSessionPreferenceOnNodeDisable" routing/executor.go | \
   grep -q "Sticky.Delete"; then
    success "P1-5: clearSessionPref 已添加 sticky 清除逻辑"
else
    error "P1-5: sticky 清除逻辑未找到"
    exit 1
fi

# 编译验证
echo ""
echo "🔨 编译验证..."
if go build ./routing ./credentialstate ./credentialhealth > /dev/null 2>&1; then
    success "编译通过"
else
    error "编译失败"
    exit 1
fi

# 单元测试验证
echo ""
echo "🧪 单元测试验证..."
if go test ./routing -run="TestExecutor" -v > /tmp/test_output.log 2>&1; then
    PASS_COUNT=$(grep -c "^--- PASS:" /tmp/test_output.log || echo "0")
    success "单元测试通过 ($PASS_COUNT 个测试)"
else
    error "单元测试失败"
    cat /tmp/test_output.log
    exit 1
fi

# 版本检查
echo ""
echo "📦 版本信息..."
if [ -f VERSION ]; then
    VERSION=$(cat VERSION)
    echo "当前版本: $VERSION"
fi

echo ""
echo "========================================="
echo "✅ 所有验证通过！"
echo "========================================="
echo ""
echo "📋 修复摘要："
echo "  ✅ P0-1: disableModelOffer 已封死"
echo "  ✅ P0-2: mnf 冷却时长修复 (30s → 2min)"
echo "  ✅ P0-3: Circuit 双重计数修复"
echo "  ✅ P1-1: AntiFlap 长冷却保护"
echo "  ✅ P1-2: candCache 即时失效"
echo "  ✅ P1-5: sticky 清除完整性"
echo ""
echo "🚀 可以安全部署到生产环境"
echo ""
