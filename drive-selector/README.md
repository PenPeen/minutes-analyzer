# Drive Selector - Slack Bot for Meeting Analyzer

Google Drive ファイル選択機能を提供する Slack Bot です。Slack から Google Drive のファイルを検索・選択し、議事録分析 Lambda に送信します。

## 機能

- `/meeting-analyzer` コマンドで Google Drive ファイルを検索・選択
- Google OAuth 2.0 によるユーザー認証
- 選択したファイルを議事録分析 Lambda へ送信
- 分析開始時の Slack 通知（メンション付き）

## 環境変数

### 必須

- `SLACK_BOT_TOKEN`: Slack Bot User OAuth Token
- `SLACK_SIGNING_SECRET`: Slack アプリの署名シークレット
- `GOOGLE_CLIENT_ID`: Google OAuth 2.0 クライアント ID
- `GOOGLE_CLIENT_SECRET`: Google OAuth 2.0 クライアントシークレット
- `PROCESS_LAMBDA_ARN`: 議事録分析 Lambda の ARN

### オプション

- `SLACK_CHANNEL_ID`: 通知を送信する Slack チャンネル ID（例: C1234567890）
  - 設定されている場合、分析開始時にチャンネルに通知を送信
  - 未設定の場合、実行ユーザーにのみエフェメラルメッセージを送信

## デプロイ

### 開発環境

```bash
cd infrastructure
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### 本番環境

```bash
cd infrastructure
terraform init
terraform plan -var-file=terraform.production.tfvars
terraform apply -var-file=terraform.production.tfvars
```

## Lambda 関数名

- 開発環境: `drive-selector-controller-development`
- 本番環境: `drive-selector-production`

## CloudWatch ログ

- 開発環境: `/aws/lambda/drive-selector-controller-development`
- 本番環境: `/aws/lambda/drive-selector-production`

## アーキテクチャ

```
Slack App
    ↓
API Gateway
    ↓
Lambda (drive-selector)
    ├→ Google Drive API (ファイル検索)
    ├→ DynamoDB (OAuth トークン保存)
    └→ Lambda (minutes-analyzer-production) [非同期呼び出し]
```

## 通知フォーマット

分析開始時に以下の形式で Slack に通知されます：

```
🔄 議事録分析を開始しました
実行者: @username
対象ファイル: ファイル名
```

## トラブルシューティング

### Lambda 呼び出しが動作しない場合

1. CloudWatch ログを確認
2. `PROCESS_LAMBDA_ARN` が正しく設定されているか確認
3. IAM ロールに `lambda:InvokeFunction` 権限があるか確認

### Slack 通知が送信されない場合

1. `SLACK_CHANNEL_ID` が正しく設定されているか確認
2. Slack Bot がチャンネルに招待されているか確認
3. `chat:write` スコープが付与されているか確認