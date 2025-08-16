# Slack App設定手順

## 概要

既存のSlack AppにGoogle Driveファイル選択機能を追加するための設定手順です。API Gatewayのデプロイ後に必要な設定更新を含みます。

## 前提条件

- 既存のSlack App（議事録分析用）
- Slack App管理者権限
- API Gateway URL（デプロイ後に取得）

## 設定手順

### 1. OAuth & Permissions設定

1. [Slack App管理画面](https://api.slack.com/apps) にアクセス
2. 対象アプリを選択
3. 「OAuth & Permissions」へ移動
4. 「Bot Token Scopes」に追加：
   - `commands` - Slashコマンドの追加と応答
   - `users:read.email` - ユーザーメールアドレスの参照

### 2. Slash Commands設定

1. 「Slash Commands」へ移動
2. 「Create New Command」または既存コマンドを編集
3. 設定内容：
   - Command: `/meeting-analyzer`
   - Request URL: `https://[API_GATEWAY_ID].execute-api.ap-northeast-1.amazonaws.com/production/slack/commands`
   - Short Description: `Google Driveから議事録を選択して分析`
   - Usage Hint: `/meeting-analyzer`

※ API_GATEWAY_IDはデプロイ後に `terraform output` で確認

### 3. Interactivity設定

1. 「Interactivity & Shortcuts」へ移動
2. 「Interactivity」をONに切り替え
3. Request URL設定：
   ```
   https://[API_GATEWAY_ID].execute-api.ap-northeast-1.amazonaws.com/production/slack/interactions
   ```
4. **Options Load URL設定（重要）**：
   ```
   https://[API_GATEWAY_ID].execute-api.ap-northeast-1.amazonaws.com/production/slack/interactions
   ```
   ※ external_selectの検索機能に必須

※ API_GATEWAY_IDはデプロイ後に `terraform output` で確認

### 4. アプリの再インストール

1. 「OAuth & Permissions」へ戻る
2. 「Reinstall to Workspace」をクリック
3. 新しい権限を確認して「Allow」

## 環境変数の取得

以下の値を取得してSecrets Managerに設定：

### SLACK_SIGNING_SECRET
1. 「Basic Information」→「App Credentials」
2. 「Signing Secret」をコピー

### SLACK_BOT_TOKEN
1. 「OAuth & Permissions」→「OAuth Tokens for Your Workspace」
2. 「Bot User OAuth Token」（xoxb-で始まる）をコピー

## 設定確認チェックリスト

- [ ] Bot Token Scopes: `commands`, `users:read.email` が追加済み
- [ ] `/meeting-analyzer` コマンドが登録済み
- [ ] Interactivityが有効
- [ ] Request URLとOptions Load URLが正しく設定済み
- [ ] アプリの再インストール完了
- [ ] SLACK_SIGNING_SECRET, SLACK_BOT_TOKENをSecrets Managerに設定済み

## トラブルシューティング

### コマンド未認識
- アプリの再インストール確認
- コマンド名の正確性確認
- Request URLの正確性確認

### 権限エラー
- Bot Token Scopesの設定確認
- トークンの更新確認（再インストール後）

## デプロイ後の設定更新手順

### 1. デプロイ実行
```bash
cd drive-selector
make deploy
```

### 2. API Gateway URL取得
```bash
cd infrastructure && terraform output
```

### 3. Slack App設定更新
- Slash CommandsのRequest URL
- InteractivityのRequest URLとOptions Load URL

### 4. Google OAuth設定更新
- Google Cloud ConsoleでRedirect URI追加

### 5. 動作テスト
- `/meeting-analyzer` コマンド実行
- Google認証フロー確認
- ファイル検索機能確認
