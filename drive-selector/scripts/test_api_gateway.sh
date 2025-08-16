#!/bin/bash

# API Gateway エンドポイントテストスクリプト

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 環境変数の確認
if [ -z "$API_GATEWAY_URL" ]; then
    echo -e "${RED}Error: API_GATEWAY_URL is not set${NC}"
    echo "Please set the API Gateway URL from Terraform output:"
    echo "export API_GATEWAY_URL=https://xxx.execute-api.ap-northeast-1.amazonaws.com/development"
    exit 1
fi

echo -e "${GREEN}Testing API Gateway endpoints...${NC}"
echo "API Gateway URL: $API_GATEWAY_URL"
echo ""

# 1. ヘルスチェック
echo -e "${YELLOW}1. Testing health check endpoint...${NC}"
curl -s -X GET "$API_GATEWAY_URL/health" | jq .
echo ""

# 2. Slack コマンドエンドポイント（署名なしでテスト - 401が期待される）
echo -e "${YELLOW}2. Testing Slack command endpoint (expecting 401)...${NC}"
curl -s -X POST "$API_GATEWAY_URL/slack/commands" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "command=/meeting-analyzer&user_id=U123456&team_id=T123456" | jq .
echo ""

# 3. Slack インタラクションエンドポイント（署名なしでテスト - 401が期待される）
echo -e "${YELLOW}3. Testing Slack interactions endpoint (expecting 401)...${NC}"
curl -s -X POST "$API_GATEWAY_URL/slack/interactions" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "payload={\"type\":\"block_actions\"}" | jq .
echo ""

# 4. 存在しないパス（404が期待される）
echo -e "${YELLOW}4. Testing non-existent path (expecting 404)...${NC}"
curl -s -X GET "$API_GATEWAY_URL/nonexistent" | jq .
echo ""

echo -e "${GREEN}API Gateway endpoint tests completed!${NC}"
echo ""
echo "Note: The 401 responses for Slack endpoints are expected since we're not providing valid Slack signatures."
echo "In production, Slack will provide the proper signatures automatically."
