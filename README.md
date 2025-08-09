# 議事録口出しBot

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![Ruby](https://img.shields.io/badge/Ruby-≥3.3-CC342D?logo=ruby)](https://www.ruby-lang.org/)

Google Meetの文字起こしを自動分析し、決定事項・アクション項目・懸念事項を抽出してSlackに通知するシステムです。

## ✨ Features

- 🤖 **AI分析**: Gemini 2.5 Flash APIによる議事録分析
- 📋 **自動抽出**: 決定事項・アクション項目・懸念事項を自動識別
- 📢 **Slack連携**: 分析結果のSlack通知
- 📝 **Notion連携**: 議事録とTODOタスクの自動作成
- 💰 **コスト効率**: 月間$2-4の低コスト運用（100回/日実行時）

## 🚀 クイックスタート

### 前提条件

#### macOS (Homebrew)
```bash
# 必要な依存関係をインストール
brew install docker terraform awscli ruby jq
```

- Google Workspace アカウント

### 開発環境セットアップ

#### 1. リポジトリクローン
```bash
git clone https://github.com/your-username/minutes-analyzer.git
cd minutes-analyzer
```

#### 2. 初期セットアップ
```bash
make setup
```

#### 3. 環境変数ファイル作成
```bash
cp env.local.sample .env.local
```

`.env.local`で以下の設定を必ず変更してください：

**必須設定**
- `GEMINI_API_KEY`: Gemini API キー（[Google AI Studio](https://makersuite.google.com/app/apikey)で取得）
- `GOOGLE_SERVICE_ACCOUNT_JSON`: Google サービスアカウント認証情報

**オプション設定**
- `SLACK_BOT_TOKEN`: Slack Bot User OAuth Token（[設定ガイド](docs/slack-integration-guide.md)参照）
- `SLACK_CHANNEL_ID`: Slack 送信先チャンネルID（例: C1234567890）
- `NOTION_API_KEY`: Notion Integration トークン
- `NOTION_DATABASE_ID`: 議事録用データベースID
- `NOTION_TASK_DATABASE_ID`: タスク管理用データベースID

### 開発環境の起動

#### 日常開発フロー
```bash
make start        # 環境起動・ビルド・ローカル自動デプロイ
make stop         # 環境停止
```

#### 本番デプロイ
```bash
make deploy       # 本番環境への手動デプロイ
```


## 📋 使用可能なコマンド

```bash
make help                    # 利用可能なコマンドを表示
make setup                   # 初期セットアップ
make dev-setup              # 開発環境完全セットアップ
make deploy-local           # LocalStack環境にデプロイ
make deploy-production      # 本番環境にデプロイ
make logs                   # CloudWatchログを確認
make clean                  # ローカル環境をクリーンアップ
```

## 🏗️ アーキテクチャ

このプロジェクトは**Google Apps Script + AWS Lambda ハイブリッド型**のアーキテクチャを採用しています：

### 管理方針

| コンポーネント | 管理方法 | 理由 |
|---|---|---|
| **AWS Lambda, API Gateway, IAM** | 🔵 **Terraform** | Infrastructure as Code、バージョン管理、自動化 |
| **Google Apps Script, Google Drive** | 🟡 **手動設定** | OAuth複雑性、トークン管理、設定頻度の低さ |

### システム構成

- **Google Apps Script**: Google Driveの監視・前処理
- **AWS Lambda (Ruby)**: Gemini 2.5 Flash APIを使用した議事録分析
- **API Gateway**: RESTful API エンドポイント
- **Slack Integration**: 分析結果の通知
- **Notion Integration**: 議事録ページとタスクの自動作成
- **LocalStack**: ローカル開発環境でのAWSサービスエミュレート

詳細な設計については [docs/architecture.md](docs/architecture.md) を参照してください。

## 📥 Lambda関数の入力形式

Lambda関数はGoogle DriveのファイルIDを受け取り、ファイルを直接読み取ります：

```json
{
  "file_id": "1234567890abcdef",
  "file_name": "2025年1月15日_新機能リリース進捗確認ミーティング.txt",
}
```

この設計により：
- ファイルサイズの制限なし
- セキュアなファイル転送
- 効率的な処理フロー

Lambda関数内でGoogle Drive APIを使用してファイルを取得し、Gemini APIで分析します。

## 📁 プロジェクト構成

```
minutes-analyzer/
├── 📁 infrastructure/        # Terraform + LocalStack
│   ├── 📁 environments/      # 環境別設定
│   │   ├── 📁 local/         # LocalStack設定
│   │   └── 📁 production/    # 本番環境設定
│   ├── 📁 modules/           # 再利用可能なTerraformモジュール
│   └── 📁 scripts/           # デプロイスクリプト
├── 📁 lambda/               # Ruby Lambda関数
├── 📁 gas/                  # Google Apps Script
├── 📁 docs/                 # ドキュメント
└── 📁 tests/                # 統合テスト
```

## 🔐 環境変数

### 必須設定
- `GEMINI_API_KEY`: Gemini 2.5 Flash APIキー（[Google AI Studio](https://makersuite.google.com/app/apikey)で取得）
- `GOOGLE_SERVICE_ACCOUNT_JSON`: Google Drive API用のサービスアカウント認証情報（JSON形式）

### オプション設定
- `SLACK_BOT_TOKEN`: Slack Bot User OAuth Token（[設定ガイド](docs/slack-integration-guide.md)参照）
- `SLACK_CHANNEL_ID`: Slack 送信先チャンネルID（例: C1234567890）
- `NOTION_API_KEY`: Notion Integration トークン（[Notion開発者ポータル](https://www.notion.so/my-integrations)で取得）
- `NOTION_DATABASE_ID`: 議事録用データベースID
- `NOTION_TASK_DATABASE_ID`: タスク管理用データベースID

### Google Drive API設定手順
詳細な手順は[Google Drive API設定ガイド](docs/google-drive-api-setup.md)を参照してください。

概要：
1. Google Cloud Consoleでプロジェクトを作成
2. Google Drive APIを有効化
3. サービスアカウントを作成し、JSONキーをダウンロード
4. IAMでサービスアカウントに適切な権限を付与
5. JSONキーをBASE64エンコードして環境変数に設定

### Notion設定手順
1. [Notion開発者ポータル](https://www.notion.so/my-integrations)でインテグレーションを作成
2. 議事録用とタスク管理用のデータベースを作成
3. データベースにインテグレーションを招待（編集権限付与）
4. データベースIDをURLから取得して設定

## 📖 ドキュメント

- [アーキテクチャ設計](docs/architecture.md)
- [Google Drive API設定ガイド](docs/google-drive-api-setup.md)
- [Slack Integration設定ガイド](docs/slack-integration-guide.md)
- [統合テスト実施手順書](docs/integration-test-guide.md)

## 🧪 ヘルスチェック

```bash
# ヘルスチェック
make health-check
```

## 🛠️ トラブルシューティング

### LocalStackが起動しない
```bash
# Docker の状態確認
docker ps

# 完全クリーンアップ
make clean
```

### GEMINI_API_KEYエラー
```bash
# APIキーが正しく設定されているか確認
grep GEMINI_API_KEY .env.local

# Google AI Studioでキーを再生成
# https://makersuite.google.com/app/apikey
```

## 📄 ライセンス

このプロジェクトは [MIT License](LICENSE) の下で公開されています。
