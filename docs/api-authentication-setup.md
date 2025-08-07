# API認証設定手順書

## 1. Google Calendar API

### サービスアカウントの作成
1. [Google Cloud Console](https://console.cloud.google.com/)にアクセス
2. プロジェクトを作成または選択
3. 「APIとサービス」→「認証情報」に移動
4. 「認証情報を作成」→「サービスアカウント」を選択
5. サービスアカウント名とIDを入力
6. 「作成して続行」をクリック

### 必要な権限
- Calendar API: `https://www.googleapis.com/auth/calendar.readonly`
- Drive API: `https://www.googleapis.com/auth/drive.readonly`

### JSONキーの生成
1. 作成したサービスアカウントをクリック
2. 「キー」タブに移動
3. 「鍵を追加」→「新しい鍵を作成」
4. 「JSON」を選択してダウンロード
5. ダウンロードしたJSONファイルを安全な場所に保存

### APIの有効化
1. 「APIとサービス」→「ライブラリ」に移動
2. 「Google Calendar API」を検索して有効化
3. 「Google Drive API」を検索して有効化

### カレンダーへのアクセス権限付与
1. Google Calendarにアクセス
2. 共有したいカレンダーの設定を開く
3. 「特定のユーザーと共有」にサービスアカウントのメールアドレスを追加
4. 権限レベルを「予定の表示（すべての予定の詳細）」に設定

## 2. Slack API

### Slackアプリの作成
1. [Slack API](https://api.slack.com/apps)にアクセス
2. 「Create New App」をクリック
3. 「From scratch」を選択
4. アプリ名とワークスペースを設定

### OAuth & Permissions設定
1. 左メニューから「OAuth & Permissions」を選択
2. 「Bot Token Scopes」に以下を追加：
   - `users:read`
   - `users:read.email`
   - `chat:write`（通知送信用）

### Bot Tokenの取得
1. 「OAuth & Permissions」ページで「Install to Workspace」をクリック
2. 権限を確認して「許可」
3. 「Bot User OAuth Token」をコピー（xoxb-で始まる文字列）

### Webhook URL設定（オプション）
1. 「Incoming Webhooks」を有効化
2. 「Add New Webhook to Workspace」をクリック
3. 投稿先チャンネルを選択
4. Webhook URLをコピー

## 3. Notion API

### インテグレーションの作成
1. [Notion Developers](https://www.notion.so/my-integrations)にアクセス
2. 「新しいインテグレーション」をクリック
3. 基本情報を入力：
   - 名前: Minutes Analyzer
   - ワークスペースを選択

### 権限設定
以下の権限を有効化：
- コンテンツ機能:
  - コンテンツを読み取る ✓
  - コンテンツを更新 ✓
  - コンテンツを挿入 ✓
- コメント機能:
  - コメントを読み取る ✓
  - コメントを作成 ✓
- ユーザー機能:
  - **User Information With Email Addresses** （最高権限レベル必須）

### APIキーの取得
1. 「内部インテグレーショントークン」をコピー（secret_で始まる文字列）

### データベースへの接続
1. Notionで議事録データベースを開く
2. 右上の「...」メニューから「接続」を選択
3. 作成したインテグレーションを選択して接続

### データベースIDの取得
1. データベースページのURLをコピー
2. URLの形式: `https://www.notion.so/workspace/[DATABASE_ID]?v=xxx`
3. DATABASE_ID部分を抽出（32文字の英数字）

## 4. 環境変数の設定

### ローカル環境（.env）
```bash
# Google
GOOGLE_SERVICE_ACCOUNT_JSON_PATH="/path/to/service-account.json"
GOOGLE_CALENDAR_ENABLED=true

# Slack
SLACK_BOT_TOKEN="xoxb-your-bot-token"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx"

# Notion
NOTION_API_KEY="secret_your_api_key"
NOTION_DATABASE_ID="your_database_id"
NOTION_TASK_DATABASE_ID="your_task_database_id"

# Features
USER_MAPPING_ENABLED=true
CACHE_TTL=600
```

### AWS Secrets Manager（本番環境）
```json
{
  "GEMINI_API_KEY": "your-gemini-api-key",
  "GOOGLE_SERVICE_ACCOUNT_JSON": "{...service account json content...}",
  "SLACK_BOT_TOKEN": "xoxb-your-bot-token",
  "SLACK_WEBHOOK_URL": "https://hooks.slack.com/services/xxx",
  "NOTION_API_KEY": "secret_your_api_key",
  "NOTION_DATABASE_ID": "your_database_id",
  "NOTION_TASK_DATABASE_ID": "your_task_database_id"
}
```

## 5. トラブルシューティング

### Google Calendar API
- **エラー: "Calendar not found"**
  - サービスアカウントにカレンダーへのアクセス権限が付与されているか確認
  - カレンダーIDが正しいか確認（primary or specific calendar ID）

- **エラー: "Insufficient Permission"**
  - APIが有効化されているか確認
  - サービスアカウントの権限スコープを確認

### Slack API
- **エラー: "invalid_auth"**
  - Bot Tokenが正しくコピーされているか確認
  - アプリがワークスペースにインストールされているか確認

- **エラー: "users_not_found"**
  - ユーザーのメールアドレスがSlackアカウントと一致しているか確認
  - Bot に users:read.email 権限があるか確認

### Notion API
- **エラー: "unauthorized"**
  - APIキーが正しいか確認
  - データベースにインテグレーションが接続されているか確認

- **エラー: "restricted_resource"**
  - インテグレーションの権限レベルを確認
  - User Information With Email Addresses権限が必要

## 6. セキュリティベストプラクティス

1. **APIキーの管理**
   - 本番環境ではAWS Secrets Managerを使用
   - ローカルでは.envファイルを使用し、.gitignoreに追加
   - APIキーをコードにハードコーディングしない

2. **最小権限の原則**
   - 必要最小限の権限のみを付与
   - 定期的に権限を見直し

3. **監査ログ**
   - API呼び出しをCloudWatchで監視
   - 異常なアクセスパターンを検知

4. **ローテーション**
   - 定期的にAPIキーをローテーション
   - 古いキーは速やかに無効化