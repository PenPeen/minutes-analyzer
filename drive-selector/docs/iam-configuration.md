# IAMロールと環境変数設定ガイド

## 概要

このドキュメントでは、Drive Selector Slack BotのIAMロール設定と環境変数管理について説明します。

## IAMロール構成

### Lambda実行ロール

Lambda関数に必要な最小権限を付与しています。

#### 基本権限
- `AWSLambdaBasicExecutionRole`: CloudWatch Logsへの書き込み

#### DynamoDB権限
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": [
        "arn:aws:dynamodb:*:*:table/drive-selector-oauth-tokens-*",
        "arn:aws:dynamodb:*:*:table/drive-selector-user-preferences-*"
      ]
    }
  ]
}
```

#### Secrets Manager権限
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:drive-selector-secrets-*"
    }
  ]
}
```

#### Lambda Invoke権限
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": "arn:aws:lambda:*:*:function:minutes-analyzer-*"
    }
  ]
}
```

### API Gateway CloudWatchロール

API GatewayがCloudWatch Logsに書き込むための権限。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

## 環境変数管理

### Secrets Managerで管理する機密情報

以下の機密情報はSecrets Managerで管理されます：

| キー | 説明 | 取得元 |
|-----|------|--------|
| `SLACK_SIGNING_SECRET` | Slack署名検証用シークレット | Slack App管理画面 |
| `SLACK_BOT_TOKEN` | Slack Bot OAuth Token | Slack App管理画面 |
| `GOOGLE_CLIENT_ID` | Google OAuth Client ID | Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | Google OAuth Client Secret | Google Cloud Console |
| `PROCESS_LAMBDA_ARN` | 議事録分析Lambda ARN | AWS Lambda |

### Lambda環境変数

Lambda関数に直接設定される環境変数：

| 変数名 | 説明 | 例 |
|--------|------|-----|
| `ENVIRONMENT` | 実行環境 | `development`, `production` |
| `OAUTH_TOKENS_TABLE` | DynamoDBテーブル名 | `drive-selector-oauth-tokens-dev` |
| `USER_PREFERENCES_TABLE` | DynamoDBテーブル名 | `drive-selector-user-preferences-dev` |
| `SECRETS_MANAGER_SECRET_ID` | Secrets Manager ID | `drive-selector-secrets-dev` |
| `GOOGLE_REDIRECT_URI` | OAuth認証後のリダイレクトURI | `https://api.example.com/oauth/callback` |

## セットアップ手順

### 1. Secrets Managerへの機密情報登録

#### AWS CLIを使用する場合

```bash
# シークレットを作成
aws secretsmanager create-secret \
  --name drive-selector-secrets-development \
  --secret-string '{
    "SLACK_SIGNING_SECRET": "your-slack-signing-secret",
    "SLACK_BOT_TOKEN": "xoxb-your-bot-token",
    "GOOGLE_CLIENT_ID": "your-google-client-id",
    "GOOGLE_CLIENT_SECRET": "your-google-client-secret",
    "PROCESS_LAMBDA_ARN": "arn:aws:lambda:region:account:function:name"
  }'
```

#### AWS コンソールを使用する場合

1. AWS Secrets Managerコンソールにアクセス
2. 「Store a new secret」をクリック
3. 「Other type of secret」を選択
4. キー/値ペアを入力
5. シークレット名を設定（例: `drive-selector-secrets-development`）

### 2. Terraformでのデプロイ

```bash
cd infrastructure

# 変数ファイルを準備
cp terraform.tfvars.sample terraform.tfvars

# 機密情報を環境変数として設定
export TF_VAR_slack_signing_secret="your-secret"
export TF_VAR_slack_bot_token="xoxb-your-token"
export TF_VAR_google_client_id="your-client-id"
export TF_VAR_google_client_secret="your-client-secret"
export TF_VAR_process_lambda_arn="arn:aws:lambda:..."

# デプロイ
terraform apply
```

### 3. 環境変数の更新

#### Secrets Managerの値を更新

```bash
aws secretsmanager update-secret \
  --secret-id drive-selector-secrets-development \
  --secret-string '{
    "SLACK_SIGNING_SECRET": "new-secret",
    ...
  }'
```

#### Lambda環境変数を更新

```bash
aws lambda update-function-configuration \
  --function-name drive-selector-controller-development \
  --environment Variables={ENVIRONMENT=development,...}
```

## セキュリティベストプラクティス

### 1. 最小権限の原則

- 各リソースに必要最小限の権限のみを付与
- ワイルドカード（*）の使用を最小限に
- 定期的な権限レビュー

### 2. シークレットローテーション

- 本番環境では90日ごとに自動ローテーション
- 手動ローテーション手順の文書化
- ローテーション後の動作確認

### 3. 監査ログ

- CloudTrailでSecrets Manager APIコールを監視
- 不正なアクセス試行の検知
- 定期的なログレビュー

### 4. 環境分離

- 開発・ステージング・本番環境で異なるシークレット
- 環境ごとに異なるIAMロール
- クロス環境アクセスの防止

## トラブルシューティング

### AccessDeniedException

**エラー**: `User is not authorized to perform: secretsmanager:GetSecretValue`

**解決方法**:
```bash
# IAMポリシーを確認
aws iam get-role-policy \
  --role-name drive-selector-lambda-role-development \
  --policy-name secrets-access
```

### ResourceNotFoundException

**エラー**: `Secrets Manager can't find the specified secret`

**解決方法**:
```bash
# シークレットの存在を確認
aws secretsmanager list-secrets \
  --filters Key=name,Values=drive-selector
```

### InvalidParameterException

**エラー**: `The parameter SecretString is not valid JSON`

**解決方法**:
```bash
# JSON形式を検証
echo '{"key": "value"}' | jq .
```

## 環境別設定

### 開発環境

- シークレットの即時削除（recovery_window_in_days = 0）
- 詳細なログ出力
- テスト用のダミー値許可

### ステージング環境

- 本番環境と同じ設定
- 実際のAPIキーを使用
- パフォーマンステスト実施

### 本番環境

- シークレットの削除保護（recovery_window_in_days = 30）
- 最小限のログ出力
- 自動ローテーション有効
- CloudWatchアラーム設定

## 監視とアラート

### CloudWatchメトリクス

```hcl
resource "aws_cloudwatch_metric_alarm" "secrets_access_error" {
  alarm_name          = "drive-selector-secrets-access-error"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Secrets Manager access errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.slack_bot_controller.function_name
  }
}
```

## コンプライアンス

### データ保護

- 機密情報は平文で保存しない
- Secrets Managerの暗号化を使用
- 転送中の暗号化（TLS）

### アクセス制御

- MFA必須化
- IPアドレス制限
- セッション時間制限

### 監査

- 全API呼び出しをCloudTrailで記録
- 定期的なアクセスレビュー
- コンプライアンスレポート生成

## まとめ

適切なIAMロール設定と環境変数管理により、セキュアで管理しやすいシステムを構築できます。定期的なレビューと更新を行い、セキュリティを維持してください。