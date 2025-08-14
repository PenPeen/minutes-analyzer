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
=======
# Drive Selector - Slack Bot Drive連携機能

Slack上でGoogle Driveファイル（Meet文字起こし）を検索・選択し、既存の議事録分析Lambdaへ起動リクエストを送るマイクロサービスです。

## 機能概要

- `/meet-transcript` コマンドでGoogle Driveファイルを検索・選択
- OAuth 2.0認証によるセキュアなGoogle Drive連携
- 選択したファイルを既存の議事録分析Lambdaに送信
- 非同期処理による快適なユーザー体験

## アーキテクチャ

```
Slack ←→ API Gateway ←→ Lambda (Controller) ←→ Google Drive API
                              ↓
                      既存議事録分析Lambda
```

## セットアップ

### 前提条件

- AWS アカウント
- Slack ワークスペース管理者権限
- Google Cloud Console アクセス権限
- Terraform v1.0以上
- Ruby 3.2

### 1. Slack App設定

1. [Slack API](https://api.slack.com/apps)で新規アプリを作成
2. OAuth & Permissions で以下のスコープを追加：
   - `commands` - Slashコマンドの使用
   - `users:read.email` - ユーザーメールアドレスの取得
   - `chat:write` - メッセージの送信
3. Slash Commands で `/meet-transcript` コマンドを追加
4. Interactivity & Shortcuts を有効化
5. Bot User OAuth Token を取得

### 2. Google OAuth設定

1. [Google Cloud Console](https://console.cloud.google.com/)でプロジェクトを作成
2. OAuth 2.0 クライアントIDを作成
3. 承認済みリダイレクトURIを設定
4. クライアントID・シークレットを取得

### 3. 環境変数設定

```bash
# 開発環境
cp .env.local.sample .env.local
# 実際の値を設定
vi .env.local

# 本番環境
cp .env.production.sample .env.production
# 実際の値を設定
vi .env.production
```

### 4. インフラストラクチャのデプロイ

```bash
cd infrastructure

# 初期化
terraform init

# 設定ファイルをコピー
cp terraform.tfvars.sample terraform.tfvars
# 実際の値を設定
vi terraform.tfvars

# デプロイ
terraform plan
terraform apply
```

## Lambda関数の詳細

### ハンドラー構成

- `handler.rb` - メインハンドラー
- `lib/slack_verifier.rb` - Slack署名検証
- `lib/slack_command_handler.rb` - Slashコマンド処理
- `lib/slack_interaction_handler.rb` - インタラクション処理
- `lib/slack_modal_builder.rb` - モーダルUI構築
- `lib/google_oauth_client.rb` - OAuth認証管理
- `lib/google_drive_client.rb` - Drive API連携
- `lib/lambda_invoker.rb` - 既存Lambda呼び出し

### Lambda Invoke連携

`LambdaInvoker`クラスが既存の議事録分析Lambdaを非同期で呼び出します：

```ruby
# ペイロード形式
{
  "body": "{\"file_id\": \"...\", \"file_name\": \"...\"}",
  "headers": {"Content-Type": "application/json"}
}
```

### 環境変数

- `PROCESS_LAMBDA_ARN` - 既存議事録分析LambdaのARN
- `SLACK_SIGNING_SECRET` - Slack署名検証用シークレット
- `SLACK_BOT_TOKEN` - Slack Bot OAuth Token
- `GOOGLE_CLIENT_ID` - Google OAuth クライアントID
- `GOOGLE_CLIENT_SECRET` - Google OAuth クライアントシークレット
- `SECRETS_MANAGER_SECRET_ID` - AWS Secrets ManagerのシークレットID

## テスト

```bash
cd lambda

# 依存関係インストール
bundle install

# テスト実行
bundle exec rspec

# カバレッジレポート
open coverage/index.html
```

## デバッグ

CloudWatch Logsでログを確認：

```bash
# 開発環境
aws logs tail /aws/lambda/drive-selector-controller-development --follow

# 本番環境
aws logs tail /aws/lambda/drive-selector-controller-production --follow
```

## トラブルシューティング

### Slack署名検証エラー

- `SLACK_SIGNING_SECRET`が正しく設定されているか確認
- リクエストのタイムスタンプが5分以内か確認

### Google認証エラー

- OAuth クライアントIDとシークレットが正しいか確認
- リダイレクトURIが承認済みリストに含まれているか確認
- DynamoDBのトークンテーブルにアクセス権限があるか確認

### Lambda Invoke失敗

- `PROCESS_LAMBDA_ARN`が正しく設定されているか確認
- IAMロールにLambda InvokeFunction権限があるか確認
- ターゲットLambdaが存在し、アクティブか確認

## セキュリティ考慮事項

- Slack署名検証により、なりすましリクエストを防止
- OAuth 2.0によるセキュアなGoogle Drive連携
- DynamoDBのデフォルト暗号化によるトークン保護
- Secrets Managerによる機密情報の安全な管理
- 最小権限の原則に基づくIAMロール設定

## ライセンス

[プロジェクトのライセンスに準拠]
