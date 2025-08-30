# Google Drive選択用SlackBot

Google Driveの議事録ファイルを選択し、AI分析システムに送信するSlackBotです。

## 主要機能

- `/meeting-analyzer`コマンドによるファイル検索・選択
- Google OAuth 2.0によるセキュアな認証
- 選択ファイルの議事録分析システムへの自動送信
- 分析開始通知（Slackメンション付き）

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

## OAuth トークン管理

OAuthトークンはDynamoDBで永続化・暗号化されています：

### テーブル仕様
- **テーブル名**: `{project_name}-oauth-tokens-{environment}`
- **主キー**: `user_id` (SlackユーザーID)
- **暗号化**: KMS暗号化による at-rest セキュリティ
- **TTL**: 期限切れトークンの自動削除
- **自動更新**: 有効期限5分前にリフレッシュ実行

## 環境変数

### 必須設定
- `SLACK_BOT_TOKEN`: Slack Bot OAuth Token
- `SLACK_SIGNING_SECRET`: Slackアプリ署名シークレット
- `GOOGLE_CLIENT_ID`: Google OAuth クライアントID
- `GOOGLE_CLIENT_SECRET`: Google OAuth クライアントシークレット
- `PROCESS_LAMBDA_ARN`: 議事録分析Lambda ARN
- `OAUTH_TOKENS_TABLE_NAME`: DynamoDBテーブル名
- `SLACK_CHANNEL_ID`: 通知送信先チャンネルID

## デプロイ

```bash
make deploy-production
```

### 手動デプロイ
```bash
cd infrastructure/environments/production
terraform init
terraform apply -var-file=terraform.tfvars
```

## システム構成

### 主要コンポーネント
- `handler.rb` - メインハンドラー
- `google_oauth_client.rb` - OAuth認証・DynamoDB連携
- `google_drive_client.rb` - Google Drive API連携
- `slack_command_handler.rb` - Slackコマンド処理
- `slack_interaction_handler.rb` - インタラクション処理

### 認証フロー
1. `/meeting-analyzer`コマンド実行
2. 初回認証時はGoogle OAuth URLにリダイレクト
3. 認証完了後、トークンをDynamoDBに暗号化保存
4. 以降のリクエストではDynamoDBからトークン取得
5. 期限切れ前にトークンを自動リフレッシュ

## テスト実行

```bash
cd lambda
bundle install
bundle exec rspec
```

## トラブルシューティング

### OAuth認証エラー
- DynamoDBテーブルのアクセス権限を確認
- `OAUTH_TOKENS_TABLE_NAME`の設定値を確認
- CloudWatchログでトークンリフレッシュ状況を確認

### Lambda呼び出しエラー
- `PROCESS_LAMBDA_ARN`の設定値を確認
- IAMロールに`lambda:InvokeFunction`権限があるか確認
- CloudWatchログで詳細エラーを確認

### DynamoDBアクセスエラー
- Lambda実行ロールに以下の権限があるか確認：
  - `dynamodb:GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`
- テーブルの存在と正しいキー設定を確認
