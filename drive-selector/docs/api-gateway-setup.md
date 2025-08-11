# API Gateway設定ガイド

## 概要

このドキュメントでは、Slack Bot Drive Selectorサービス用のAPI Gateway設定について説明します。

## アーキテクチャ

```
Slack → API Gateway → Lambda → Google Drive API
             ↓
        既存議事録分析Lambda
```

## エンドポイント構成

### 基本URL
```
https://{api-id}.execute-api.{region}.amazonaws.com/{stage}
```

### エンドポイント一覧

| パス | メソッド | 用途 | 認証 |
|-----|---------|------|-----|
| `/health` | GET | ヘルスチェック | なし |
| `/slack/commands` | POST | Slashコマンド処理 | Slack署名 |
| `/slack/interactions` | POST | インタラクション処理 | Slack署名 |
| `/oauth/callback` | GET | OAuth認証コールバック | なし |

## デプロイ手順

### 1. Terraform初期化

```bash
cd infrastructure
terraform init
```

### 2. 設定ファイル準備

```bash
cp terraform.tfvars.sample terraform.tfvars
# 必要な値を設定
vi terraform.tfvars
```

### 3. デプロイ実行

```bash
# プランを確認
terraform plan

# デプロイ
terraform apply
```

### 4. エンドポイントURL取得

```bash
# Terraform出力から取得
terraform output slack_command_endpoint
terraform output slack_interactions_endpoint
```

## Slack App設定

### 1. Slash Commands設定

1. Slack App管理画面の「Slash Commands」セクションへ移動
2. 「Create New Command」をクリック
3. 以下を設定：
   - Command: `/meet-transcript`
   - Request URL: `{api-gateway-url}/slack/commands`
   - Short Description: Google Driveから議事録を選択
   - Usage Hint: [optional] ファイル名で検索

### 2. Interactivity設定

1. 「Interactivity & Shortcuts」セクションへ移動
2. 「Interactivity」をONに切り替え
3. Request URLに設定：
   ```
   {api-gateway-url}/slack/interactions
   ```

## API Gatewayの特徴

### タイムアウト設定
- Lambda統合タイムアウト: 29秒
- Slackの要求: 3秒以内にACKレスポンス
- 対応: Lambda内で即座にACKを返し、処理は非同期実行

### ロギング
- CloudWatch Logsに全リクエストを記録
- X-Rayトレーシング有効
- エラー時の詳細ログ出力

### セキュリティ
- Slack署名検証による認証
- X-Content-Type-Options: nosniff
- X-Frame-Options: DENY

### スロットリング
- Rate limit: 10,000 req/sec
- Burst limit: 5,000 requests

## テスト方法

### 1. ヘルスチェック

```bash
curl https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/health
```

期待されるレスポンス：
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:00:00Z"
}
```

### 2. テストスクリプト実行

```bash
export API_GATEWAY_URL=https://{api-id}.execute-api.{region}.amazonaws.com/{stage}
./scripts/test_api_gateway.sh
```

## トラブルシューティング

### 403 Forbidden エラー

**原因**: Lambda権限が不足
**解決策**: 
```bash
terraform apply -target=aws_lambda_permission.api_gateway_invoke
```

### 502 Bad Gateway エラー

**原因**: Lambda関数のレスポンス形式が不正
**確認事項**:
- statusCode、headers、bodyを含むオブジェクトを返しているか
- bodyはJSON文字列化されているか

### タイムアウトエラー

**原因**: Lambda処理が29秒を超過
**解決策**: 
- 処理を非同期化
- Lambda関数のタイムアウト値を確認

### CloudWatchログの確認

```bash
# API Gatewayログ
aws logs tail /aws/api-gateway/drive-selector-{environment} --follow

# Lambdaログ
aws logs tail /aws/lambda/drive-selector-controller-{environment} --follow
```

## ステージ管理

### 開発環境
- ステージ名: `development`
- ログレベル: INFO
- データトレース: 有効

### 本番環境
- ステージ名: `production`
- ログレベル: ERROR
- データトレース: 無効

## API仕様

### Slackコマンドリクエスト

```
POST /slack/commands
Content-Type: application/x-www-form-urlencoded

command=/meet-transcript&
text=search+term&
user_id=U123456&
team_id=T123456&
trigger_id=123456789.123456789
```

### Slackインタラクションリクエスト

```
POST /slack/interactions
Content-Type: application/x-www-form-urlencoded

payload={"type":"block_actions","user":{"id":"U123456"},...}
```

## カスタムドメイン設定（オプション）

### 1. ACM証明書の作成

```bash
aws acm request-certificate \
  --domain-name api.your-domain.com \
  --validation-method DNS
```

### 2. Route53設定

```hcl
resource "aws_api_gateway_domain_name" "slack_bot" {
  domain_name     = "api.your-domain.com"
  certificate_arn = aws_acm_certificate.api.arn
}
```

### 3. ベースパスマッピング

```hcl
resource "aws_api_gateway_base_path_mapping" "slack_bot" {
  api_id      = aws_api_gateway_rest_api.slack_bot.id
  stage_name  = aws_api_gateway_stage.slack_bot.stage_name
  domain_name = aws_api_gateway_domain_name.slack_bot.domain_name
}
```

## メトリクス監視

### 重要メトリクス

- **4XXError**: クライアントエラー率
- **5XXError**: サーバーエラー率
- **Count**: API呼び出し回数
- **Latency**: レスポンス時間
- **IntegrationLatency**: Lambda実行時間

### CloudWatchアラーム例

```hcl
resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  alarm_name          = "${var.project_name}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors 5xx errors"
}
```

## まとめ

API Gatewayは、Slack BotとLambda関数を接続する重要なコンポーネントです。適切な設定により、セキュアで高性能なAPIエンドポイントを提供します。