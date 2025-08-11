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
2. 「Create New Command」をクリック
3. 以下の情報を入力：
   ```
   Command: /meet-transcript
   Request URL: https://[後で設定]/slack/commands
   Short Description: Google Driveから議事録を選択して分析
   Usage Hint: /meet-transcript
   ```
4. 「Save」をクリック

**注意**: Request URLは後でAPI Gatewayのエンドポイントが確定してから更新します。

### 3. Interactivity設定

1. 左メニューから「Interactivity & Shortcuts」を選択
2. 「Interactivity」をONに切り替え
3. Request URLを入力：
   ```
   https://[後で設定]/slack/interactions
   ```
4. 「Save Changes」をクリック

**注意**: こちらのURLも後で更新が必要です。

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
- [ ] `/meet-transcript` コマンドが登録されている
- [ ] Interactivityが有効になっている
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

## 次のステップ
T-07（API Gateway設定）完了後に、Request URLを実際のエンドポイントに更新する必要があります。