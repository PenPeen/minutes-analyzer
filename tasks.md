# Slack Bot Drive連携機能 実装タスク計画

## ドキュメントの関係性
- **本ファイル（tasks.md）**: プロジェクト管理・タスク計画書。タスクの進捗管理と割り当てに使用
- **architecture.md**: システム設計・技術仕様書。実装時の技術リファレンスとして参照
- 両ファイルは補完関係にあり、tasks.mdでタスクを管理しながら、architecture.mdを参照して実装を進める

## 概要
- 目的: Slack上でGoogle Driveファイル（Meet文字起こし）を検索・選択し、既存の議事録分析Lambdaへ起動リクエストを送る機能を実装する
- 成功基準: ユーザーが /meet-transcript コマンドでDriveファイルを検索・選択し、分析処理を開始できる
- スコープ: Slackアプリ設定/Controller Lambda実装/API Gateway設定/Google OAuth認証/既存Lambda連携
- 非スコープ: ユーザーOAuth認証対応, Meet Recordings配下の絞り込み, 完了通知機能
- 実装場所: drive-selectorディレクトリ内（analyzerとは独立したマイクロサービスとして実装）

## タスク一覧
- T-01: Slack App設定と権限拡張（完了）
  - 概要: 既存のSlack Appにcommands、users:read.emailスコープを追加し、Slash CommandとInteractivityを設定
  - 受け入れ条件:
    - 既存のSLACK_BOT_TOKENにcommands、users:read.emailスコープが追加されている（完了）
    - /meet-transcript コマンドが登録されている
    - Interactivity機能が有効化されている
    - 設定手順がドキュメント化されている
  - 依存関係: なし
  - ブランチ: chore/slack-app-permissions

- T-02: Google OAuth 2.0認証設定
  - 概要: Google OAuth 2.0認証を設定し、ユーザー権限でDrive検索を可能にする
  - 受け入れ条件:
    - OAuth 2.0クライアントIDが作成されている
    - drive.metadata.readonlyスコープでの認証フローが実装されている
    - アクセストークンの保存・リフレッシュ機能が実装されている
    - 設定手順がドキュメント化されている
  - 依存関係: なし
  - ブランチ: feature/google-oauth-setup

- T-03: Controller Lambda基本実装（Ruby）
  - 概要: Slackリクエストを受け付けるController Lambda関数の骨格と署名検証を実装
  - 受け入れ条件:
    - Lambda関数がSlack署名検証を実装している
    - 3秒以内にACK応答を返せる
    - エラーハンドリングが実装されている
    - CloudWatchログが適切に出力される
  - 依存関係: なし
  - ブランチ: feature/controller-lambda-base

- T-04: モーダルUI実装
  - 概要: /meet-transcript コマンドでモーダルを表示し、external_select検索UIを実装
  - 受け入れ条件:
    - views.openでモーダルが表示される
    - external_selectでDrive検索フィールドが表示される
    - ファイル名上書きオプションフィールドが表示される
    - モーダルのsubmit/cancelが正しく動作する
  - 依存関係: T-01, T-03
  - ブランチ: feature/slack-modal-ui

- T-05: Google Drive検索機能実装
  - 概要: OAuth認証を使用してGoogle Driveファイルを検索し、external_selectの候補として返す機能を実装
  - 受け入れ条件:
    - OAuth認証でDrive APIにアクセスできる
    - 検索クエリでGoogleドキュメントを検索できる
    - ユーザーが許可したドライブ内のファイルが検索対象になる
    - 最大20件の検索結果を返せる
    - 初回認証時の同意フローが実装されている
  - 依存関係: T-02, T-03
  - ブランチ: feature/drive-search-integration

- T-06: 既存Lambda Invoke連携
  - 概要: 選択されたファイル情報を既存の議事録分析Lambdaに正しい形式で送信する機能を実装
  - 受け入れ条件:
    - file_idとfile_nameを含むペイロードが生成される
    - 既存Lambda（PROCESS_LAMBDA_ARN）へ非同期Invokeが実行される
    - ペイロード形式が既存Lambdaの仕様と完全一致する
    - CloudWatchでInvokeログが確認できる
  - 依存関係: T-03
  - ブランチ: feature/process-lambda-invoke

- T-07: API Gateway設定
  - 概要: Controller Lambda用のAPI Gatewayを設定し、Slackから接続可能にする
  - 受け入れ条件:
    - REST API Gatewayが作成されている
    - /slack/commandsと/slack/interactionsエンドポイントが設定されている
    - Lambda統合が正しく設定されている
    - CORS設定が適切（Slackからのアクセスのみ許可）
    - TerraformでAPI Gatewayがコード化されている
  - 依存関係: T-03
  - ブランチ: feature/api-gateway-setup

- T-08: IAMロールと環境変数設定
  - 概要: Controller LambdaのIAMロールを設定し、必要な環境変数をSecrets Manager経由で管理
  - 受け入れ条件:
    - Lambda InvokeFunctionの権限が付与されている
    - Secrets Manager GetSecretValueの権限が付与されている
    - 全環境変数がSecrets Manager経由で取得される
    - Terraformでロールとポリシーが管理されている
  - 依存関係: T-03
  - ブランチ: feature/iam-secrets-config

- T-09: 統合テストと開発環境での動作確認
  - 概要: 単体テストとAWS開発環境での統合テストを実施
  - 受け入れ条件:
    - Controller Lambdaの単体テストが作成されている
    - AWS開発環境にController Lambdaがデプロイされる
    - API Gateway経由でSlackからアクセスできる
    - 既存Lambdaへのペイロード送信が確認できる
    - CloudWatch Logsでデバッグ可能
  - 依存関係: T-04, T-05, T-06, T-07
  - ブランチ: test/integration-dev-env

- T-10: 本番デプロイとドキュメント整備
  - 概要: 本番環境へのデプロイ手順を整備し、運用ドキュメントを作成
  - 受け入れ条件:
    - 本番環境デプロイ手順書が作成されている
    - Slackコマンドの使い方ガイドが作成されている
    - トラブルシューティングガイドが整備されている
    - README.mdに新機能の説明が追加されている
  - 依存関係: T-09
  - ブランチ: docs/production-deployment

## ブランチ計画
- ベースブランチ: main
- ブランチ命名規則: <type>/<scope>-<short-desc>（kebab-case, 英小文字）
- タスクとブランチ対応:
  - T-01 -> chore/slack-app-permissions
  - T-02 -> feature/google-oauth-setup
  - T-03 -> feature/controller-lambda-base
  - T-04 -> feature/slack-modal-ui
  - T-05 -> feature/drive-search-integration
  - T-06 -> feature/process-lambda-invoke
  - T-07 -> feature/api-gateway-setup
  - T-08 -> feature/iam-secrets-config
  - T-09 -> test/integration-dev-env
  - T-10 -> docs/production-deployment

## 付記
- 実装ディレクトリ: drive-selector/（analyzerとは独立したマイクロサービスとして実装）
- 環境変数/シークレット: drive-selector/.env.local => Terraform => Secrets Manager
- SLACK_BOT_TOKENの流用: 既存のトークンに必要なスコープを追加することで流用可能。ただし、Slack Appの再インストールが必要
- OAuth認証方式: Google Workspace以外の環境でも動作するよう、ユーザーOAuth認証方式を採用
- Controller Lambdaの言語: 設計書に従いRubyで実装。既存のLambdaと同じ言語で統一

## 開発・テスト方針

### アーキテクチャ設計
- **API Gateway REST API**: SlackからのリクエストをLambdaにルーティング
- **マイクロサービス**: drive-selectorディレクトリ内に独立したサービスとして実装
- **ルーティング**: API Gatewayでパスベースのルーティング
  - `POST /slack/commands` → Slashコマンド処理
  - `POST /slack/interactions` → インタラクション処理

### API Gateway設定例（Terraform）
```hcl
# drive-selector/infrastructure/api_gateway.tf
resource "aws_api_gateway_rest_api" "slack_bot" {
  name        = "slack-bot-drive-selector"
  description = "API Gateway for Slack Bot Drive Selector"
}

resource "aws_api_gateway_resource" "slack" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_rest_api.slack_bot.root_resource_id
  path_part   = "slack"
}

resource "aws_api_gateway_resource" "commands" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.slack.id
  path_part   = "commands"
}

resource "aws_api_gateway_resource" "interactions" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.slack.id
  path_part   = "interactions"
}

resource "aws_api_gateway_method" "commands_post" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.commands.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "commands_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.commands.id
  http_method = aws_api_gateway_method.commands_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}
```

### ディレクトリ構造
```
drive-selector/
├── lambda/
│   ├── handler.rb          # メインハンドラー
│   ├── slack_handler.rb    # Slack関連処理
│   ├── drive_handler.rb    # Google Drive関連処理
│   └── Gemfile            # Ruby依存関係
├── infrastructure/
│   ├── main.tf            # Terraform設定
│   ├── api_gateway.tf     # API Gateway設定
│   ├── lambda.tf          # Lambda関数設定
│   └── iam.tf            # IAMロール/ポリシー
├── test/
│   └── spec/              # RSpecテスト
└── README.md              # サービスドキュメント
```

### テスト環境
1. **ローカル**: 単体テストのみ（RSpec）
2. **AWS開発環境**: Slackとの統合テスト（推奨）
3. **LocalStack**: CI/CDパイプライン用（オプション）
