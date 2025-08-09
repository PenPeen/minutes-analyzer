# Slack Integration ガイド

## 概要

本ドキュメントは、議事録分析システムのSlack連携機能の設定方法と必要なOAuth Scopeについて説明します。

## Slack App の設定手順

### 1. Slack App の作成

1. [Slack API](https://api.slack.com/apps) にアクセス
2. 「Create New App」をクリック
3. 「From scratch」を選択
4. App名に「Minutes Analyzer」（または任意の名前）を入力
5. ワークスペースを選択して「Create App」をクリック

### 2. Bot Token の設定

1. 左メニューから「OAuth & Permissions」を選択
2. 「Scopes」セクションまでスクロール
3. 「Bot Token Scopes」で必要なスコープを追加（下記参照）
4. ページ上部の「Install to Workspace」をクリック
5. 権限を確認して「Allow」をクリック
6. 表示される「Bot User OAuth Token」（`xoxb-`で始まる）をコピー

### 3. 環境変数の設定

`.env.local` または `.env.production` に以下を設定：

```bash
SLACK_BOT_TOKEN=xoxb-xxxxxxxxxxxx-xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxx
SLACK_CHANNEL_ID=C1234567890  # 投稿先チャンネルのID
```

## 必要な OAuth Scopes

議事録分析システムが正常に動作するために必要なSlack OAuth Scopeの一覧です。

| OAuth Scope | 説明 | 使用目的 |
|------------|------|----------|
| `chat:write` | Send messages as @minutes-analyzer | 議事録分析結果をチャンネルにメインメッセージとして投稿 |
| `chat:write.public` | Send messages to channels @minutes-analyzer isn't a member of | Botがメンバーでないパブリックチャンネルへの投稿を可能にする |
| `users.profile:read` | View profile details about people in a workspace | ユーザープロフィール情報の取得（将来的な機能拡張用） |
| `users:read` | View people in a workspace | ワークスペースのユーザー一覧取得（将来的な機能拡張用） |
| `users:read.email` | View email addresses of people in a workspace | ユーザーのメールアドレス取得（将来的な機能拡張用） |

### 必須スコープ

現在のシステムで**必須**となるスコープ：
- `chat:write` - 基本的なメッセージ送信機能
- `chat:write.public` - パブリックチャンネルへの投稿（Botがメンバーでない場合）

**重要**: 両方のスコープを設定することで、どのチャンネルにも柔軟に投稿できるようになります。

### オプションスコープ

将来の機能拡張に備えて設定されているスコープ：
- `users.profile:read`
- `users:read` 
- `users:read.email`

これらは現在のバージョンでは使用されていませんが、今後の機能追加（例：参加者の自動マッピング、メンション機能など）で使用予定です。

## 投稿先チャンネルの設定

### チャンネルIDの取得方法

1. Slackでチャンネルを右クリック
2. 「チャンネル詳細を表示」を選択
3. 最下部の「チャンネルID」をコピー（`C`で始まる文字列）

### プライベートチャンネルへの投稿

プライベートチャンネルに投稿する場合は、以下の手順でBotを招待する必要があります：

1. 対象のプライベートチャンネルに移動
2. チャンネルで `/invite @minutes-analyzer` を実行
3. または、チャンネル設定 → インテグレーション → アプリを追加

## メッセージ形式

### メインメッセージ

議事録分析結果は以下の形式で投稿されます：

```
📝 [会議タイトル]
━━━━━━━━━━━━━━━━━━━━━━━━
📅 日付: YYYY-MM-DD
⏱️ 所要時間: XX分
👥 参加者: 参加者1, 参加者2, ...

🎯 決定事項: X件
📋 アクション: Y件

🎯 主な決定事項
1. 決定事項1
2. 決定事項2
...

📋 アクション一覧
1. 🔴 [高優先度] タスク1 - 担当者（期限）
2. 🟡 [中優先度] タスク2 - 担当者（期限）
...
```

### スレッド返信

メインメッセージに対するスレッド返信として、以下の詳細情報が投稿されます：

- 😊 会議の雰囲気
- 💡 改善提案

## トラブルシューティング

### `missing_scope` エラー

エラーメッセージ例：
```json
{
  "error": "missing_scope",
  "needed": "chat:write",
  "provided": "users:read,users:read.email"
}
```

**対処法：**
1. Slack App管理画面で必要なスコープが追加されているか確認
2. スコープ追加後、必ず「Reinstall to Workspace」を実行
3. 新しいBot Tokenを取得して環境変数を更新

### `channel_not_found` エラー

**対処法：**
1. チャンネルIDが正しいか確認（`#`を含めない）
2. プライベートチャンネルの場合、Botが招待されているか確認
3. チャンネルIDの形式を確認（`C`で始まる英数字）

### `not_in_channel` エラー

**対処法：**
1. パブリックチャンネルの場合：`chat:write.public` スコープを追加
2. プライベートチャンネルの場合：Botをチャンネルに招待

## セキュリティ上の注意事項

1. **Bot Token の管理**
   - Bot Tokenは環境変数として管理し、コードに直接記載しない
   - `.env.local` ファイルは `.gitignore` に含める
   - 本番環境ではAWS Secrets Managerなどのシークレット管理サービスを使用

2. **スコープの最小権限の原則**
   - 必要最小限のスコープのみを要求
   - 不要になったスコープは削除

3. **チャンネル設定**
   - 機密情報を含む議事録は適切なプライベートチャンネルに投稿
   - チャンネルIDは環境変数として管理

## 関連ドキュメント

- [統合テスト実施手順書](integration-test-guide.md)
- [アーキテクチャ設計](architecture.md)
- [README](../README.md)