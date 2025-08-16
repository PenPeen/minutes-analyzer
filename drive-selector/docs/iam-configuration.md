# IAMロールと環境変数設定ガイド

## 概要

Drive Selector Slack BotのセキュアなIAM設定と環境変数管理手順です。最小権限原則に基づいたセキュリティ設定を実現します。

## IAMロール構成

### Lambda実行ロール

Lambda関数に必要最小限の権限を付与。

#### 基本権限
- `AWSLambdaBasicExecutionRole`: CloudWatch Logs書き込み

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
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:*:table/drive-selector-oauth-tokens-production"
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
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:ap-northeast-1:*:secret:drive-selector-secrets-production-*"
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
      "Action": "lambda:InvokeFunction",
      "Resource": "arn:aws:lambda:ap-northeast-1:*:function:minutes-analyzer-production"
    }
  ]
}
```

### API Gateway CloudWatchロール

API GatewayのCloudWatch Logs書き込み権限。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:ap-northeast-1:*:log-group:/aws/api-gateway/drive-selector-*"
    }
  ]
}
```

## 環境変数管理

### Secrets Manager管理情報

| キー | 説明 | 取得元 |
|-----|------|--------|
| `SLACK_SIGNING_SECRET` | Slack署名検証 | Slack App管理画面 |
| `SLACK_BOT_TOKEN` | Slack Bot OAuth Token | Slack App管理画面 |
| `GOOGLE_CLIENT_ID` | Google OAuth Client ID | Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | Google OAuth Client Secret | Google Cloud Console |
| `PROCESS_LAMBDA_ARN` | 議事録分析Lambda ARN | AWS Lambda |

### Lambda環境変数

| 変数名 | 説明 | 例 |
|--------|------|-----|
| `ENVIRONMENT` | 実行環境 | `production` |
| `OAUTH_TOKENS_TABLE` | DynamoDBテーブル名 | `drive-selector-oauth-tokens-production` |
| `SECRETS_MANAGER_SECRET_ID` | Secrets Manager ID | `drive-selector-secrets-production` |

## セットアップ手順

### 1. Secrets Manager設定

#### AWS CLIでの作成

```bash
aws secretsmanager create-secret \
  --name drive-selector-secrets-production \
  --secret-string '{
    "SLACK_SIGNING_SECRET": "your-slack-signing-secret",
    "SLACK_BOT_TOKEN": "xoxb-your-bot-token",
    "GOOGLE_CLIENT_ID": "your-google-client-id",
    "GOOGLE_CLIENT_SECRET": "your-google-client-secret",
    "PROCESS_LAMBDA_ARN": "arn:aws:lambda:ap-northeast-1:account:function:minutes-analyzer-production"
  }'
```

#### AWSコンソールでの作成

1. Secrets Managerコンソールへアクセス
2. 「Store a new secret」をクリック
3. 「Other type of secret」を選択
4. 必要なキー/値ペアを入力
5. シークレット名: `drive-selector-secrets-production`

### 2. Terraformデプロイ

```bash
cd drive-selector

# 設定ファイル準備
cd infrastructure
cp terraform.tfvars.sample terraform.tfvars

# デプロイ
make deploy
```

### 3. 設定更新

#### Secrets Manager更新

```bash
aws secretsmanager update-secret \
  --secret-id drive-selector-secrets-production \
  --secret-string '{
    "SLACK_SIGNING_SECRET": "new-secret"
  }'
```

#### Lambda環境変数更新

Terraformで管理されるため、手動更新は非推奨。

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

### 本番環境設定

- シークレットの削除保護（30日間）
- エラーレベルのログ出力
- CloudWatchアラーム設定
- 最小権限の徹底

## 監視とアラート

### CloudWatchアラーム

以下のアラームが自動設定されます：
- Secrets Managerアクセスエラー
- Lambda関数エラー率
- DynamoDBアクセスエラー
- API Gateway 5XXエラー

## セキュリティベストプラクティス

### データ保護
- Secrets Managerの暗号化使用
- 転送中のTLS暗号化
- 機密情報の平文保存禁止

### アクセス制御
- 最小権限原則の徹底
- リソースベースの権限設定
- 定期的な権限レビュー

### 監査ログ
- CloudTrailで全API呼び出し記録
- CloudWatch Logsでアプリケーションログ監視
- 不正アクセスの検知とアラート

## 次のステップ

1. Terraformデプロイ実行
2. Secrets Managerの値設定
3. IAMロールの動作確認
4. アラート設定の検証