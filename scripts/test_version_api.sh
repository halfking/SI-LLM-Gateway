#!/bin/bash
# Test /api/system/version API with admin credentials

echo "=== Testing /api/system/version API ==="
echo ""

# Try with a test admin key (you'll need to replace with actual key)
API_KEY="sk-admin-test-key"

echo "1. Testing with Authorization header:"
curl -s -H "Authorization: Bearer $API_KEY" \
  http://localhost:8781/api/system/version | jq '.'

echo ""
echo "2. Expected result:"
echo "   version: \"2.3.2\" (simplified semantic version)"
echo "   build_seq: 717"
echo "   git_sha: \"edb6fa85\""
echo "   build_date: \"2026-07-01\""
