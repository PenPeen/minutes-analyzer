# Slack Bot設計書

## 概要

SlackでGoogle Driveファイルを検索・選択し、議事録分析Lambdaを起動するSlack Botの設計書です。

## 基本機能

- `/meeting-analyzer`コマンドでモーダル表示
- Google Driveファイルの動的検索（external_select）
- 既存analyzer Lambdaとの連携
- ドメイン全体委任による権限管理



## アーキテクチャ

### コンポーネント
- **Slack App**: スラッシュコマンド、モーダルUI
- **API Gateway**: Slackからのリクエスト受付
- **Controller Lambda**: Slack連携、Google Drive検索
- **Analyzer Lambda**: 議事録分析処理（既存）

### 処理フロー
1. ユーザー: `/meeting-analyzer`実行
2. Controller: モーダル表示
3. ユーザー: ファイル検索・選択
4. Controller: analyzer Lambda起動
5. Slack: 処理開始通知


## 主要仕様

### Slack App設定
- スラッシュコマンド: `/meeting-analyzer`
- 必要スコープ: `commands`, `chat:write`, `users:read.email`
- モーダルでファイル検索・選択UI提供

### Google Drive連携
- ドメイン全体委任によるファイル検索
- 検索条件: Google Documentsのみ、削除済み除外
- 検索結果: 最大20件、更新日時降順


## 環境変数

- `SLACK_SIGNING_SECRET`: Slack署名検証用
- `SLACK_BOT_TOKEN`: Bot認証トークン
- `PROCESS_LAMBDA_ARN`: analyzer Lambda関数のARN
- `GOOGLE_SERVICE_ACCOUNT_JSON`: サービスアカウント認証情報
- `USE_DWD`: ドメイン全体委任の使用（推奨: true）

## セキュリティ要件

- Slack署名検証（リプレイ攻撃対策）
- AWS Secrets Managerでの機密情報管理
- 最小権限アクセス制御
- ドメイン制限（オプション）

## デプロイ手順

1. **Google設定**: サービスアカウント作成、ドメイン全体委任設定
2. **Slack App**: アプリ作成、スコープ設定、Bot トークン取得
3. **AWS**: API Gateway、Lambda、IAMロールのデプロイ
4. **動作確認**: `/meeting-analyzer`コマンドテスト

詳細な実装・設定手順については、関連ドキュメントを参照してください。
