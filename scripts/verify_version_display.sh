#!/bin/bash
# 验证71服务器版本显示修复
# 日期: 2026-07-01

set -e

SERVER="14.103.174.71"
PORT="25022"
API_KEY="sk-k40DVd9aqFGumYcEkfkQvSgdv06uepSNDK0BqHwtwS3RzTgY"

echo "=========================================="
echo "71服务器版本显示验证脚本"
echo "=========================================="
echo ""

echo "1️⃣  检查VERSION文件内容..."
ssh -p $PORT root@$SERVER "cat /opt/llm-gateway-go/VERSION"
echo ""

echo "2️⃣  检查.deploy_seq文件内容..."
ssh -p $PORT root@$SERVER "cat /opt/llm-gateway-go/.deploy_seq"
echo ""

echo "3️⃣  检查容器内VERSION文件..."
ssh -p $PORT root@$SERVER "docker exec llm-gateway-go cat /opt/llm-gateway-go/VERSION"
echo ""

echo "4️⃣  检查容器内.deploy_seq文件..."
ssh -p $PORT root@$SERVER "docker exec llm-gateway-go cat /opt/llm-gateway-go/.deploy_seq"
echo ""

echo "5️⃣  测试/api/system/version API..."
ssh -p $PORT root@$SERVER "curl -s -H 'Authorization: Bearer $API_KEY' http://localhost:8781/api/system/version" | jq .
echo ""

echo "=========================================="
echo "✅ 后端验证完成"
echo "=========================================="
echo ""

echo "📋 API返回数据检查:"
VERSION_JSON=$(ssh -p $PORT root@$SERVER "curl -s -H 'Authorization: Bearer $API_KEY' http://localhost:8781/api/system/version")

VERSION=$(echo "$VERSION_JSON" | jq -r .version)
BUILD_SEQ=$(echo "$VERSION_JSON" | jq -r .build_seq)
GIT_SHA=$(echo "$VERSION_JSON" | jq -r .git_sha)

echo "  version: $VERSION"
echo "  build_seq: $BUILD_SEQ"
echo "  git_sha: $GIT_SHA"
echo ""

# 验证结果
EXPECTED_VERSION="2.3.2-edb6fa85-20260701-717"
EXPECTED_BUILD_SEQ="717"
EXPECTED_GIT_SHA="edb6fa85"

if [ "$VERSION" = "$EXPECTED_VERSION" ]; then
    echo "✅ version字段正确: $VERSION"
else
    echo "❌ version字段错误: 期望 $EXPECTED_VERSION, 实际 $VERSION"
    exit 1
fi

if [ "$BUILD_SEQ" = "$EXPECTED_BUILD_SEQ" ]; then
    echo "✅ build_seq字段正确: $BUILD_SEQ"
else
    echo "❌ build_seq字段错误: 期望 $EXPECTED_BUILD_SEQ, 实际 $BUILD_SEQ"
    exit 1
fi

if [ "$GIT_SHA" = "$EXPECTED_GIT_SHA" ]; then
    echo "✅ git_sha字段正确: $GIT_SHA"
else
    echo "❌ git_sha字段错误: 期望 $EXPECTED_GIT_SHA, 实际 $GIT_SHA"
    exit 1
fi

echo ""
echo "=========================================="
echo "🎉 后端API验证全部通过！"
echo "=========================================="
echo ""
echo "📱 前端验证步骤："
echo ""
echo "1. 打开浏览器访问: http://14.103.174.71:8781"
echo "2. 点击右上角「登录」按钮"
echo "3. 输入管理员账号密码登录"
echo "4. 检查右上角是否显示:"
echo ""
echo "   ┌─────────────────────────────────────────────────────┐"
echo "   │ [用户名] · [角色] · v2.3.2-edb6fa85-20260701-717 · #717 │"
echo "   └─────────────────────────────────────────────────────┘"
echo ""
echo "5. 版本号应为紫色高亮、等宽字体"
echo "6. 编译次数(#717)应为灰色、等宽字体"
echo ""
echo "如果显示正确，说明问题已完全解决！🎊"
echo ""
