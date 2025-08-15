#!/bin/bash

# 本番環境のSecrets Managerにシークレットを設定するスクリプト

set -e

# .env.productionから値を読み込み
if [ ! -f .env.production ]; then
    echo "❌ .env.productionが見つかりません"
    exit 1
fi

echo "📝 .env.productionから値を読み込み中..."

# 一時的なJSONファイルを作成
python3 -c "
import json
import os

# .env.productionを読み込み
env_vars = {}
with open('.env.production', 'r') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#'):
            if '=' in line:
                key, value = line.split('=', 1)
                # Remove quotes from values
                if value.startswith("'") and value.endswith("'"):
                    value = value[1:-1]
                elif value.startswith('"') and value.endswith('"'):
                    value = value[1:-1]
                env_vars[key] = value

# JSONを作成
secrets = {
    'GEMINI_API_KEY': env_vars.get('GEMINI_API_KEY', ''),
    'SLACK_BOT_TOKEN': env_vars.get('SLACK_BOT_TOKEN', ''),
    'SLACK_CHANNEL_ID': env_vars.get('SLACK_CHANNEL_ID', ''),
    'NOTION_API_KEY': env_vars.get('NOTION_API_KEY', ''),
    'NOTION_DATABASE_ID': env_vars.get('NOTION_DATABASE_ID', ''),
    'NOTION_TASK_DATABASE_ID': env_vars.get('NOTION_TASK_DATABASE_ID', ''),
    'GOOGLE_SERVICE_ACCOUNT_JSON': env_vars.get('GOOGLE_SERVICE_ACCOUNT_JSON', '')
}

# JSONファイルに書き込み
with open('/tmp/production-secrets.json', 'w') as f:
    json.dump(secrets, f)

print('✅ JSONファイルを作成しました')
"

echo "🔐 Secrets Managerに値を設定中..."

# Secrets Managerに値を設定
aws secretsmanager put-secret-value \
    --secret-id minutes-analyzer-secrets-production \
    --secret-string file:///tmp/production-secrets.json \
    --region ap-northeast-1

# 一時ファイルを削除
rm -f /tmp/production-secrets.json

echo "✅ シークレットの設定が完了しました"