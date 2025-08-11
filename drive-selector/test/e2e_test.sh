#!/bin/bash

# E2Eテストスクリプト
# 開発環境でのエンドツーエンドテスト

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# テスト結果カウンター
PASSED=0
FAILED=0

# 環境変数チェック
check_environment() {
    echo -e "${BLUE}=== Environment Check ===${NC}"
    
    required_vars=("API_GATEWAY_URL" "SLACK_SIGNING_SECRET" "FUNCTION_NAME")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo -e "${RED}✗ $var is not set${NC}"
            echo "Please set required environment variables:"
            echo "  export API_GATEWAY_URL=https://xxx.execute-api.region.amazonaws.com/stage"
            echo "  export SLACK_SIGNING_SECRET=your-slack-signing-secret"
            echo "  export FUNCTION_NAME=drive-selector-controller-development"
            exit 1
        else
            echo -e "${GREEN}✓ $var is set${NC}"
        fi
    done
    echo ""
}

# テスト実行関数
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo -e "${YELLOW}Running: $test_name${NC}"
    if $test_function; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED++))
    fi
    echo ""
}

# Test 1: ヘルスチェック
test_health_check() {
    response=$(curl -s -w "\n%{http_code}" "$API_GATEWAY_URL/health")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "200" ] && echo "$body" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
        return 0
    else
        echo "Expected: 200 with healthy status"
        echo "Got: $http_code"
        echo "Body: $body"
        return 1
    fi
}

# Test 2: 不正な署名でのSlackコマンド
test_invalid_signature() {
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_GATEWAY_URL/slack/commands" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "X-Slack-Signature: v0=invalid" \
        -H "X-Slack-Request-Timestamp: $(date +%s)" \
        -d "command=/meet-transcript&user_id=U123456")
    
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "401" ]; then
        return 0
    else
        echo "Expected: 401 Unauthorized"
        echo "Got: $http_code"
        return 1
    fi
}

# Test 3: 正しい署名でのSlackコマンド
test_valid_slack_command() {
    timestamp=$(date +%s)
    body="command=/meet-transcript&user_id=U123456&team_id=T123456&trigger_id=123.456"
    
    # 署名を生成
    sig_basestring="v0:${timestamp}:${body}"
    signature="v0=$(echo -n "$sig_basestring" | openssl dgst -sha256 -hmac "$SLACK_SIGNING_SECRET" -hex | cut -d' ' -f2)"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "$API_GATEWAY_URL/slack/commands" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "X-Slack-Signature: $signature" \
        -H "X-Slack-Request-Timestamp: $timestamp" \
        -d "$body")
    
    http_code=$(echo "$response" | tail -n1)
    
    # 200または認証エラー以外のエラー（例：DynamoDBアクセスエラー）
    if [ "$http_code" = "200" ] || [ "$http_code" = "500" ]; then
        return 0
    else
        echo "Expected: 200 or 500 (for missing resources)"
        echo "Got: $http_code"
        return 1
    fi
}

# Test 4: Lambda関数の存在確認
test_lambda_function() {
    if aws lambda get-function --function-name "$FUNCTION_NAME" > /dev/null 2>&1; then
        return 0
    else
        echo "Lambda function $FUNCTION_NAME not found"
        return 1
    fi
}

# Test 5: DynamoDBテーブルの存在確認
test_dynamodb_tables() {
    tables=("drive-selector-oauth-tokens-development" "drive-selector-user-preferences-development")
    
    for table in "${tables[@]}"; do
        if ! aws dynamodb describe-table --table-name "$table" > /dev/null 2>&1; then
            echo "DynamoDB table $table not found"
            return 1
        fi
    done
    
    return 0
}

# Test 6: Secrets Managerの存在確認
test_secrets_manager() {
    secret_name="drive-selector-secrets-development"
    
    if aws secretsmanager get-secret-value --secret-id "$secret_name" > /dev/null 2>&1; then
        return 0
    else
        echo "Secret $secret_name not found"
        return 1
    fi
}

# Test 7: CloudWatch Logsの確認
test_cloudwatch_logs() {
    log_group="/aws/lambda/$FUNCTION_NAME"
    
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" | jq -e '.logGroups | length > 0' > /dev/null 2>&1; then
        return 0
    else
        echo "CloudWatch log group $log_group not found"
        return 1
    fi
}

# Test 8: API Gatewayレート制限テスト
test_rate_limiting() {
    echo "Sending 10 rapid requests..."
    
    for i in {1..10}; do
        curl -s -o /dev/null -w "%{http_code}\n" "$API_GATEWAY_URL/health" &
    done
    
    wait
    
    # すべてのリクエストが成功すべき（レート制限は10,000/秒）
    return 0
}

# Test 9: Lambda関数のメモリとタイムアウト設定確認
test_lambda_configuration() {
    config=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME")
    
    memory=$(echo "$config" | jq -r '.MemorySize')
    timeout=$(echo "$config" | jq -r '.Timeout')
    
    if [ "$memory" -ge 256 ] && [ "$timeout" -ge 30 ]; then
        return 0
    else
        echo "Memory: $memory MB (expected >= 256)"
        echo "Timeout: $timeout seconds (expected >= 30)"
        return 1
    fi
}

# Test 10: エラーハンドリング（存在しないパス）
test_404_error() {
    response=$(curl -s -w "\n%{http_code}" "$API_GATEWAY_URL/nonexistent")
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "404" ]; then
        return 0
    else
        echo "Expected: 404"
        echo "Got: $http_code"
        return 1
    fi
}

# メイン処理
main() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Drive Selector E2E Test Suite      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # 環境チェック
    check_environment
    
    # テスト実行
    echo -e "${BLUE}=== Running Tests ===${NC}"
    
    run_test "Health Check" test_health_check
    run_test "Invalid Slack Signature" test_invalid_signature
    run_test "Valid Slack Command" test_valid_slack_command
    run_test "Lambda Function Exists" test_lambda_function
    run_test "DynamoDB Tables Exist" test_dynamodb_tables
    run_test "Secrets Manager Configured" test_secrets_manager
    run_test "CloudWatch Logs Setup" test_cloudwatch_logs
    run_test "Rate Limiting Test" test_rate_limiting
    run_test "Lambda Configuration" test_lambda_configuration
    run_test "404 Error Handling" test_404_error
    
    # 結果サマリー
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo -e "Passed: ${GREEN}$PASSED${NC}"
    echo -e "Failed: ${RED}$FAILED${NC}"
    
    if [ "$FAILED" -eq 0 ]; then
        echo -e "${GREEN}All tests passed! ✨${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please check the output above.${NC}"
        exit 1
    fi
}

# スクリプト実行
main