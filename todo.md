# ユーザー作業が必要なタスク

## 🔴 必須作業

### 1. Slack App設定（T-01）
Slack App管理画面（https://api.slack.com/apps）で以下の設定が必要です：

#### OAuth & Permissions
- 以下のBot Token Scopesを追加:
  - `commands` - Slashコマンドの実行権限
  - `users:read.email` - ユーザーメールアドレスの読み取り権限
- 設定後、アプリを再インストール

#### Slash Commands
- 新規コマンドを作成:
  - Command: `/meet-transcript`
  - Request URL: `https://[API_GATEWAY_URL]/slack/commands` （後で設定）
  - Short Description: Google Driveから議事録を選択して分析
  - Usage Hint: /meet-transcript

#### Interactivity & Shortcuts
- Interactivityを有効化
- Request URL: `https://[API_GATEWAY_URL]/slack/interactions` （後で設定）

### 2. Google OAuth 2.0設定（T-02）
Google Cloud Console（https://console.cloud.google.com）で以下の設定が必要です：

#### OAuth 2.0クライアントIDの作成
1. 「APIとサービス」→「認証情報」へ移動
2. 「認証情報を作成」→「OAuth クライアント ID」を選択
3. アプリケーションの種類: 「ウェブアプリケーション」
4. 承認済みのリダイレクトURI:
   - `https://[API_GATEWAY_URL]/oauth/callback`
5. 作成後、クライアントIDとクライアントシークレットを保存

#### 必要なAPIの有効化
- Google Drive API を有効化

## 📝 取得が必要な情報

以下の情報を取得して、環境変数またはSecrets Managerに設定してください：

1. **Slack関連**
   - SLACK_SIGNING_SECRET（Slack App Basic Information → App Credentials）
   - SLACK_BOT_TOKEN（既存のものを流用、スコープ追加後）

2. **Google OAuth関連**
   - GOOGLE_CLIENT_ID（OAuth 2.0クライアントIDから取得）
   - GOOGLE_CLIENT_SECRET（OAuth 2.0クライアントシークレットから取得）

## ⏰ タイミング

### API Gateway URLが決まった後に必要な作業
T-07（API Gateway設定）完了後に以下の更新が必要：
1. Slack App設定で Request URL を更新
2. Google OAuth設定で リダイレクトURI を更新

## 📌 注意事項
- Slack Appの設定変更後は、ワークスペースへの再インストールが必要です
- Google OAuthの本番環境では、OAuth同意画面の設定も必要になる場合があります