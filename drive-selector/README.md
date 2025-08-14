# Drive Selector - Slack Bot for Meeting Analyzer

Google Drive ファイル選択機能を提供する Slack Bot です。Slack から Google Drive のファイルを検索・選択し、議事録分析 Lambda に送信します。

## 機能

- `/meeting-analyzer` コマンドで Google Drive ファイルを検索・選択
- Google OAuth 2.0 によるユーザー認証
- 選択したファイルを議事録分析 Lambda へ送信
- 分析開始時の Slack 通知（メンション付き）

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

## DynamoDB トークン管理

OAuth トークンは DynamoDB テーブルで永続化されます：

### テーブル構造
- **テーブル名**: `{project_name}-oauth-tokens-{environment}`
- **パーティションキー**: `user_id` (SlackユーザーID)
- **属性**:
  - `access_token`: Google OAuth アクセストークン
  - `refresh_token`: Google OAuth リフレッシュトークン
  - `expires_at`: トークン有効期限 (UNIX timestamp)
  - `created_at`: 作成日時 (UNIX timestamp)
  - `updated_at`: 更新日時 (UNIX timestamp)

### 特徴
- KMS暗号化による at-rest セキュリティ
- TTL設定による期限切れトークンの自動削除
- 自動リフレッシュ機能（有効期限5分前に実行）

## 環境変数

### 必須

- `SLACK_BOT_TOKEN`: Slack Bot User OAuth Token
- `SLACK_SIGNING_SECRET`: Slack アプリの署名シークレット
- `GOOGLE_CLIENT_ID`: Google OAuth 2.0 クライアント ID
- `GOOGLE_CLIENT_SECRET`: Google OAuth 2.0 クライアントシークレット
- `PROCESS_LAMBDA_ARN`: 議事録分析 Lambda の ARN
- `OAUTH_TOKENS_TABLE_NAME`: DynamoDB トークンテーブル名
- `SLACK_CHANNEL_ID`: 通知を送信する Slack チャンネル ID（例: C1234567890）

## デプロイ

### 本番環境

```bash
cd infrastructure/environments/production
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

## Lambda関数の詳細

### 主要コンポーネント

- `handler.rb` - メインハンドラー
- `lib/google_oauth_client.rb` - OAuth認証管理（DynamoDB連携）
- `lib/dynamodb_token_store.rb` - DynamoDBトークン管理
- `lib/google_drive_client.rb` - Drive API連携
- `lib/slack_command_handler.rb` - Slashコマンド処理
- `lib/slack_interaction_handler.rb` - インタラクション処理

### OAuth トークンフロー

1. ユーザーが `/meeting-analyzer` コマンドを実行
2. 認証が必要な場合、Google OAuth URLにリダイレクト
3. 認証完了後、トークンをDynamoDBに保存
4. 以降のリクエストでは DynamoDB からトークンを取得
5. トークン有効期限が近い場合、自動的にリフレッシュ

## テスト

```bash
cd lambda
bundle install
bundle exec rspec
```

## トラブルシューティング

### OAuth トークンエラー

1. DynamoDB テーブルへのアクセス権限を確認
2. `OAUTH_TOKENS_TABLE_NAME` が正しく設定されているか確認
3. トークンの有効期限が切れていないか確認（自動リフレッシュされるはず）

### Lambda 呼び出しが動作しない場合

1. CloudWatch ログを確認
2. `PROCESS_LAMBDA_ARN` が正しく設定されているか確認
3. IAM ロールに `lambda:InvokeFunction` 権限があるか確認

### DynamoDB アクセスエラー

1. Lambda実行ロールにDynamoDB権限があるか確認:
   - `dynamodb:GetItem`
   - `dynamodb:PutItem`
   - `dynamodb:UpdateItem`
   - `dynamodb:DeleteItem`
2. `OAUTH_TOKENS_TABLE_NAME` 環境変数が設定されているか確認
3. DynamoDBテーブルが存在し、適切なキー設定になっているか確認
