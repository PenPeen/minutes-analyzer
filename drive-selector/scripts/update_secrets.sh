#!/bin/bash

# Secrets Manager更新スクリプト

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 使用方法を表示
usage() {
    echo "Usage: $0 <environment> [options]"
    echo ""
    echo "Arguments:"
    echo "  environment    Environment name (development, staging, production)"
    echo ""
    echo "Options:"
    echo "  --slack-signing-secret <value>   Update Slack signing secret"
    echo "  --slack-bot-token <value>       Update Slack bot token"
    echo "  --google-client-id <value>      Update Google client ID"
    echo "  --google-client-secret <value>  Update Google client secret"
    echo "  --process-lambda-arn <value>    Update process Lambda ARN"
    echo "  --all                           Update all secrets interactively"
    echo "  --show                          Show current secret values (be careful!)"
    echo ""
    echo "Example:"
    echo "  $0 development --slack-bot-token xoxb-new-token"
    echo "  $0 production --all"
    exit 1
}

# 引数チェック
if [ $# -lt 1 ]; then
    usage
fi

ENVIRONMENT=$1
shift

SECRET_NAME="drive-selector-secrets-${ENVIRONMENT}"

# 環境の検証
if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
    echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'${NC}"
    echo "Valid environments: development, staging, production"
    exit 1
fi

# 現在のシークレットを取得
get_current_secrets() {
    aws secretsmanager get-secret-value \
        --secret-id "$SECRET_NAME" \
        --query 'SecretString' \
        --output text 2>/dev/null || echo "{}"
}

# シークレットを表示
show_secrets() {
    echo -e "${YELLOW}Current secrets for ${ENVIRONMENT}:${NC}"
    CURRENT=$(get_current_secrets)
    
    if [ "$CURRENT" = "{}" ]; then
        echo -e "${RED}No secrets found or access denied${NC}"
        exit 1
    fi
    
    echo "$CURRENT" | jq '.' | while IFS= read -r line; do
        if [[ $line == *"TOKEN"* ]] || [[ $line == *"SECRET"* ]]; then
            # センシティブな値をマスク
            key=$(echo "$line" | cut -d':' -f1 | tr -d ' "')
            if [[ ! -z "$key" && "$key" != "{" && "$key" != "}" ]]; then
                echo "  $key: ***MASKED***"
            else
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done
}

# 全シークレットを対話的に更新
update_all_secrets() {
    echo -e "${YELLOW}Updating all secrets for ${ENVIRONMENT}${NC}"
    CURRENT=$(get_current_secrets)
    
    echo "Enter new values (press Enter to keep current value):"
    
    read -p "Slack Signing Secret: " SLACK_SIGNING_SECRET
    read -p "Slack Bot Token: " SLACK_BOT_TOKEN
    read -p "Google Client ID: " GOOGLE_CLIENT_ID
    read -p "Google Client Secret: " GOOGLE_CLIENT_SECRET
    read -p "Process Lambda ARN: " PROCESS_LAMBDA_ARN
    
    # 現在の値を保持するか新しい値を使用
    NEW_JSON=$(echo "$CURRENT" | jq \
        --arg ss "${SLACK_SIGNING_SECRET:-$(echo "$CURRENT" | jq -r '.SLACK_SIGNING_SECRET // empty')}" \
        --arg st "${SLACK_BOT_TOKEN:-$(echo "$CURRENT" | jq -r '.SLACK_BOT_TOKEN // empty')}" \
        --arg gi "${GOOGLE_CLIENT_ID:-$(echo "$CURRENT" | jq -r '.GOOGLE_CLIENT_ID // empty')}" \
        --arg gs "${GOOGLE_CLIENT_SECRET:-$(echo "$CURRENT" | jq -r '.GOOGLE_CLIENT_SECRET // empty')}" \
        --arg pl "${PROCESS_LAMBDA_ARN:-$(echo "$CURRENT" | jq -r '.PROCESS_LAMBDA_ARN // empty')}" \
        '{
            SLACK_SIGNING_SECRET: ($ss // .SLACK_SIGNING_SECRET),
            SLACK_BOT_TOKEN: ($st // .SLACK_BOT_TOKEN),
            GOOGLE_CLIENT_ID: ($gi // .GOOGLE_CLIENT_ID),
            GOOGLE_CLIENT_SECRET: ($gs // .GOOGLE_CLIENT_SECRET),
            PROCESS_LAMBDA_ARN: ($pl // .PROCESS_LAMBDA_ARN)
        }')
    
    update_secret "$NEW_JSON"
}

# 個別のシークレットを更新
update_individual_secrets() {
    CURRENT=$(get_current_secrets)
    NEW_JSON="$CURRENT"
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --slack-signing-secret)
                NEW_JSON=$(echo "$NEW_JSON" | jq --arg v "$2" '.SLACK_SIGNING_SECRET = $v')
                shift 2
                ;;
            --slack-bot-token)
                NEW_JSON=$(echo "$NEW_JSON" | jq --arg v "$2" '.SLACK_BOT_TOKEN = $v')
                shift 2
                ;;
            --google-client-id)
                NEW_JSON=$(echo "$NEW_JSON" | jq --arg v "$2" '.GOOGLE_CLIENT_ID = $v')
                shift 2
                ;;
            --google-client-secret)
                NEW_JSON=$(echo "$NEW_JSON" | jq --arg v "$2" '.GOOGLE_CLIENT_SECRET = $v')
                shift 2
                ;;
            --process-lambda-arn)
                NEW_JSON=$(echo "$NEW_JSON" | jq --arg v "$2" '.PROCESS_LAMBDA_ARN = $v')
                shift 2
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                ;;
        esac
    done
    
    update_secret "$NEW_JSON"
}

# シークレットを更新
update_secret() {
    local SECRET_JSON="$1"
    
    echo -e "${YELLOW}Updating secret: $SECRET_NAME${NC}"
    
    # 本番環境の場合は確認
    if [ "$ENVIRONMENT" = "production" ]; then
        echo -e "${RED}WARNING: You are updating PRODUCTION secrets!${NC}"
        read -p "Are you sure? (yes/no): " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    # シークレットを更新
    if aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SECRET_JSON" \
        >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Secret updated successfully${NC}"
    else
        echo -e "${RED}✗ Failed to update secret${NC}"
        exit 1
    fi
    
    # Lambda関数を再起動（新しいシークレットを反映）
    echo -e "${YELLOW}Updating Lambda function to use new secrets...${NC}"
    FUNCTION_NAME="drive-selector-controller-${ENVIRONMENT}"
    
    if aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment "Variables={FORCE_UPDATE=$(date +%s)}" \
        >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Lambda function updated${NC}"
    else
        echo -e "${YELLOW}! Lambda function update skipped (function may not exist)${NC}"
    fi
}

# メイン処理
if [ $# -eq 0 ]; then
    usage
fi

case "$1" in
    --show)
        show_secrets
        ;;
    --all)
        update_all_secrets
        ;;
    --*)
        update_individual_secrets "$@"
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        usage
        ;;
esac

echo -e "${GREEN}Done!${NC}"