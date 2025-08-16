# Slack App設定手順（T-01）

## 概要
既存のSlack Appに対して、Google Driveファイル選択機能のための権限とコマンドを追加設定します。

## 前提条件
- 既存のSlack Appが作成済みであること
- Slack App管理画面へのアクセス権限があること
- SLACK_BOT_TOKEN が取得済みであること

## 設定手順

### 1. OAuth & Permissions設定

1. [Slack App管理画面](https://api.slack.com/apps) にアクセス
2. 対象のアプリを選択
3. 左メニューから「OAuth & Permissions」を選択
4. 「Scopes」セクションまでスクロール
5. 「Bot Token Scopes」に以下を追加：
   - `commands` - Add slash commands and respond to users
   - `users:read.email` - View email addresses of people in a workspace

### 2. Slash Commands設定

1. 左メニューから「Slash Commands」を選択
2. 「Create New Command」をクリック（既存の場合は編集）
3. 以下の情報を入力：
   ```
   Command: /meet-transcript
   Request URL: https://[API_GATEWAY_ID].execute-api.ap-northeast-1.amazonaws.com/production/slack/commands
   Short Description: Google Driveから議事録を選択して分析
   Usage Hint: /meet-transcript
   ```
4. 「Save」をクリック

**注意**: API_GATEWAY_IDはデプロイ後に`terraform output`で確認し、更新してください。

### 3. Interactivity設定

1. 左メニューから「Interactivity & Shortcuts」を選択
2. 「Interactivity」をONに切り替え
3. Request URLを入力：
   ```
   https://[API_GATEWAY_ID].execute-api.ap-northeast-1.amazonaws.com/production/slack/interactions
   ```
4. **Options Load URL**に**同じURL**を入力（重要！）：
   ```
   https://[API_GATEWAY_ID].execute-api.ap-northeast-1.amazonaws.com/production/slack/interactions
   ```
   ⚠️ **注意**: Options Load URLはexternal_selectの検索機能に必須です。必ず設定してください。
5. 「Save Changes」をクリック

**注意**: API_GATEWAY_IDはデプロイ後に`terraform output`で確認し、更新してください。

### 4. アプリの再インストール

1. 「OAuth & Permissions」ページに戻る
2. 「Reinstall to Workspace」をクリック
3. 権限を確認して「Allow」をクリック

## 環境変数の取得

以下の値を取得して保存してください：

### SLACK_SIGNING_SECRET
1. 「Basic Information」を選択
2. 「App Credentials」セクションを確認
3. 「Signing Secret」の値をコピー

### SLACK_BOT_TOKEN
1. 「OAuth & Permissions」を選択
2. 「OAuth Tokens for Your Workspace」セクションを確認
3. 「Bot User OAuth Token」（xoxb-で始まる）をコピー

## 設定確認チェックリスト

- [ ] Bot Token Scopesに `commands` が追加されている
- [ ] Bot Token Scopesに `users:read.email` が追加されている
- [ ] `/meeting-analyzer` コマンドが登録されている
- [ ] Interactivityが有効になっている
- [ ] Request URLとOptions Load URLが正しく設定されている
- [ ] アプリがワークスペースに再インストールされている
- [ ] SLACK_SIGNING_SECRET を取得済み
- [ ] SLACK_BOT_TOKEN を取得済み

## トラブルシューティング

### コマンドが認識されない場合
- アプリの再インストールを確認
- コマンド名が正しく入力されているか確認（スペースや大文字小文字）

### 権限エラーが発生する場合
- Bot Token Scopesが正しく設定されているか確認
- トークンが最新のものか確認（再インストール後のトークン）

## デプロイ後の設定更新手順

1. **デプロイを実行**
   ```bash
   make deploy
   ```

2. **API Gateway URLを取得**
   ```bash
   cd infrastructure && terraform output
   ```

3. **Slack App設定を更新**
   - Slash CommandsのRequest URLを更新
   - InteractivityのRequest URLとOptions Load URLを更新

4. **Google OAuth設定を更新**
   - Google Cloud ConsoleでRedirect URIを追加

5. **動作確認**
   - Slackで `/meeting-analyzer` コマンドを実行
   - Google認証が成功するか確認
   - ファイル検索が動作するか確認