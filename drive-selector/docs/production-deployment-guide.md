# 本番環境デプロイガイド

## 📋 概要

Drive Selector Slack Botを本番環境にデプロイするための完全ガイドです。

## 🔍 前提条件

### 必要なアクセス権限

- [ ] AWS本番アカウントへのアクセス
- [ ] Terraform state保存用S3バケットへのアクセス
- [ ] Slack Workspace管理者権限
- [ ] Google Cloud Console プロジェクト管理者権限

### 必要なツール

```bash
# バージョン確認
terraform version  # >= 1.0
aws --version      # >= 2.0
ruby --version     # >= 3.2
bundle --version   # >= 2.0
```

## 📝 事前準備チェックリスト

### 1. Slackアプリ設定

- [ ] 本番用Slack Appを作成
- [ ] OAuth & Permissionsでスコープ設定
  - `commands`
  - `users:read.email`
  - `chat:write`
- [ ] Slash Commands設定（URLは後で更新）
- [ ] Interactivity有効化（URLは後で更新）
- [ ] Bot User OAuth Tokenを取得
- [ ] Signing Secretを取得

### 2. Google OAuth設定

- [ ] 本番用プロジェクトを作成
- [ ] OAuth 2.0 Client IDを作成
- [ ] 承認済みリダイレクトURIを設定（後で更新）
- [ ] Client IDとClient Secretを取得

### 3. AWS環境準備

- [ ] 本番AWSアカウントにログイン
- [ ] Terraform用IAMユーザー作成
- [ ] S3バケット作成（Terraform state用）
- [ ] Route53ドメイン設定（オプション）

## 🚀 デプロイ手順

### Step 1: 環境変数の設定

```bash
# .env.production ファイルを作成
cp drive-selector/.env.production.sample drive-selector/.env.production

# 実際の値を設定
vi drive-selector/.env.production
```

必須環境変数:
```bash
SLACK_SIGNING_SECRET=prod-slack-signing-secret
SLACK_BOT_TOKEN=xoxb-production-bot-token
GOOGLE_CLIENT_ID=production-google-client-id
GOOGLE_CLIENT_SECRET=production-google-client-secret
PROCESS_LAMBDA_ARN=arn:aws:lambda:ap-northeast-1:ACCOUNT:function:minutes-analyzer-production
```

### Step 2: Terraform設定

```bash
cd drive-selector/infrastructure

# backend設定を更新
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "drive-selector/production/terraform.tfstate"
    region = "ap-northeast-1"
    encrypt = true
    dynamodb_table = "terraform-state-lock"
  }
}
EOF

# 初期化
terraform init

# Workspaceを作成/選択
terraform workspace new production || terraform workspace select production
```

### Step 3: 変数ファイルの準備

```bash
# terraform.tfvars.production を作成
cat > terraform.tfvars.production <<EOF
environment = "production"
aws_region = "ap-northeast-1"
api_gateway_domain = "api.your-domain.com"  # オプション
process_lambda_arn = "arn:aws:lambda:ap-northeast-1:ACCOUNT:function:minutes-analyzer-production"
EOF
```

### Step 4: デプロイ実行

```bash
# ドライラン（変更内容確認）
terraform plan -var-file=terraform.tfvars.production

# 確認後、デプロイ実行
terraform apply -var-file=terraform.tfvars.production

# 出力を保存
terraform output -json > outputs.json
```

### Step 5: Secrets Manager設定

```bash
# シークレットを登録
aws secretsmanager create-secret \
  --name drive-selector-secrets-production \
  --secret-string '{
    "SLACK_SIGNING_SECRET": "your-prod-secret",
    "SLACK_BOT_TOKEN": "xoxb-your-prod-token",
    "GOOGLE_CLIENT_ID": "your-prod-client-id",
    "GOOGLE_CLIENT_SECRET": "your-prod-client-secret",
    "PROCESS_LAMBDA_ARN": "arn:aws:lambda:..."
  }'
```

### Step 6: API Gateway URLの取得と設定

```bash
# API Gateway URLを取得
API_URL=$(terraform output -raw api_gateway_url)
echo "API Gateway URL: $API_URL"

# Slack App設定を更新
echo "1. Slash Commands URL: $API_URL/slack/commands"
echo "2. Interactivity URL: $API_URL/slack/interactions"

# Google OAuth設定を更新
echo "3. Redirect URI: $API_URL/oauth/callback"
```

### Step 7: 動作確認

```bash
# ヘルスチェック
curl "$API_URL/health"

# E2Eテスト実行
export API_GATEWAY_URL=$API_URL
export SLACK_SIGNING_SECRET=your-prod-secret
export FUNCTION_NAME=drive-selector-controller-production
./test/e2e_test.sh
```

## 📊 監視設定

### CloudWatch アラーム

```bash
# エラー率アラーム
aws cloudwatch put-metric-alarm \
  --alarm-name "drive-selector-prod-errors" \
  --alarm-description "High error rate in production" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

### ダッシュボード作成

```json
{
  "name": "DriveSelector-Production",
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", {"stat": "Sum"}],
          [".", "Errors", {"stat": "Sum"}],
          [".", "Duration", {"stat": "Average"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "ap-northeast-1",
        "title": "Lambda Metrics"
      }
    }
  ]
}
```

## 🔄 ロールバック手順

問題が発生した場合のロールバック手順：

### 1. 即時ロールバック

```bash
# 前のバージョンにロールバック
cd drive-selector/infrastructure
terraform workspace select production
terraform apply -var-file=terraform.tfvars.production -refresh=false \
  -target=aws_lambda_function.slack_bot_controller \
  -replace="aws_lambda_function.slack_bot_controller"
```

### 2. Lambda関数のみロールバック

```bash
# 前のバージョンを指定してロールバック
aws lambda update-function-code \
  --function-name drive-selector-controller-production \
  --s3-bucket your-deployment-bucket \
  --s3-key lambda-previous-version.zip
```

### 3. API Gatewayのロールバック

```bash
# 前のデプロイメントにロールバック
aws apigateway update-stage \
  --rest-api-id YOUR_API_ID \
  --stage-name production \
  --deployment-id PREVIOUS_DEPLOYMENT_ID
```

## 🔐 セキュリティチェックリスト

### デプロイ前

- [ ] Secrets Managerの暗号化設定確認
- [ ] IAMロールの最小権限確認
- [ ] API Gatewayのスロットリング設定
- [ ] CloudWatch Logsの暗号化
- [ ] DynamoDBの暗号化設定

### デプロイ後

- [ ] 不要なデバッグログの無効化
- [ ] APIキーのローテーションスケジュール設定
- [ ] セキュリティグループの確認
- [ ] CloudTrailログの有効化確認

## 📈 パフォーマンスチューニング

### Lambda設定最適化

```bash
# メモリサイズ調整（必要に応じて）
aws lambda update-function-configuration \
  --function-name drive-selector-controller-production \
  --memory-size 512

# 予約済み同時実行数の設定
aws lambda put-function-concurrency \
  --function-name drive-selector-controller-production \
  --reserved-concurrent-executions 100
```

### API Gatewayキャッシュ

```bash
# キャッシュ有効化（GETリクエストのみ）
aws apigateway update-stage \
  --rest-api-id YOUR_API_ID \
  --stage-name production \
  --patch-operations \
    op=replace,path=/cacheClusterEnabled,value=true \
    op=replace,path=/cacheClusterSize,value=0.5
```

## 🔍 トラブルシューティング

### よくある問題と解決方法

#### 1. Lambda関数がタイムアウトする

```bash
# タイムアウト値を増やす
aws lambda update-function-configuration \
  --function-name drive-selector-controller-production \
  --timeout 60
```

#### 2. API Gateway 502エラー

```bash
# Lambda関数のログを確認
aws logs tail /aws/lambda/drive-selector-controller-production --follow

# レスポンス形式を確認
# statusCode, headers, bodyが必須
```

#### 3. Slack署名検証失敗

```bash
# Secrets Managerの値を確認
aws secretsmanager get-secret-value \
  --secret-id drive-selector-secrets-production \
  --query SecretString --output text | jq .

# 環境変数を確認
aws lambda get-function-configuration \
  --function-name drive-selector-controller-production \
  --query Environment.Variables
```

## 📋 運用チェックリスト

### 日次チェック

- [ ] CloudWatchエラーログ確認
- [ ] API利用状況確認
- [ ] DynamoDB容量確認

### 週次チェック

- [ ] パフォーマンスメトリクス分析
- [ ] コスト分析
- [ ] セキュリティアラート確認

### 月次チェック

- [ ] 依存パッケージの更新
- [ ] IAMポリシーレビュー
- [ ] バックアップ確認
- [ ] ディザスタリカバリテスト

## 📞 緊急連絡先

| 役割 | 名前 | 連絡先 |
|-----|------|--------|
| インシデント管理者 | - | - |
| AWS管理者 | - | - |
| Slack管理者 | - | - |
| 開発リード | - | - |

## 📚 関連ドキュメント

- [AWS Lambda ベストプラクティス](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [Slack API セキュリティベストプラクティス](https://api.slack.com/security-best-practices)
- [Google OAuth 2.0 セキュリティ](https://developers.google.com/identity/protocols/oauth2/security)

## まとめ

本番環境へのデプロイは慎重に行い、各ステップで動作確認を実施してください。問題が発生した場合は、速やかにロールバック手順を実行し、影響を最小限に抑えてください。