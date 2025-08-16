# 議事録分析システム

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![Ruby](https://img.shields.io/badge/Ruby-≥3.3-CC342D?logo=ruby)](https://www.ruby-lang.org/)

Google Meetの議事録をAIで自動分析し、決定事項やアクション項目を構造化してSlack/Notionに通知するシステムです。

## ✨ 主要機能

- 🤖 **AI分析**: Gemini 2.5 Flash APIによる高精度な議事録分析
- 📋 **自動抽出**: 決定事項・アクション項目・改善提案を自動識別
- 📊 **タスク詳細化**: アクション項目に背景情報と実行手順を自動追加
- 📢 **Slack通知**: 分析結果をリアルタイムで通知
- 📝 **Notion連携**: 議事録とタスクの自動データベース化
- 👥 **ユーザーマッピング**: 参加者の自動識別とアサイン
- 💰 **コスト効率**: 月額$2-4の低コスト運用

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
git clone https://github.com/PenPeen/minutes-analyzer.git
cd minutes-analyzer
```

#### 2. 初期セットアップ
```bash
cd analyzer
make setup
```

#### 3. 環境変数設定
```bash
cp env.local.sample .env.local
```

`.env.local`で以下の環境変数を設定してください：

**必須設定**
- `GEMINI_API_KEY`: Gemini API キー
- `GOOGLE_SERVICE_ACCOUNT_JSON`: Google サービスアカウント認証情報

**オプション設定**
- `SLACK_BOT_TOKEN`: Slack Bot OAuth Token
- `SLACK_CHANNEL_ID`: 通知先チャンネルID
- `NOTION_API_KEY`: Notion Integration トークン
- `NOTION_DATABASE_ID`: 議事録用データベースID
- `NOTION_TASK_DATABASE_ID`: タスク管理用データベースID

詳細な設定手順は[環境変数設定](#-環境変数)セクションを参照してください。

### 開発環境の起動

#### 日常開発フロー
```bash
cd analyzer
make start        # 環境起動・ビルド・ローカル自動デプロイ
make stop         # 環境停止
```

#### 本番デプロイ
```bash
cd analyzer
make deploy-production   # 本番環境への手動デプロイ
```


## 📋 主要コマンド

以下のコマンドは`analyzer`ディレクトリ内で実行してください：

```bash
make help           # 利用可能なコマンドを表示
make setup          # 初期セットアップ
make start          # 開発環境起動・デプロイ
make test           # テスト実行
make clean          # 環境クリーンアップ
make deploy-production  # 本番デプロイ
```

詳細なコマンドについては[Makefileコマンドガイド](docs/makefile-commands.md)を参照してください。

## 🏗️ システム構成

**Slack Bot + AWS Lambda**のサーバーレスアーキテクチャを採用：

### 主要コンポーネント

- **drive-selector**: Google Driveファイル選択用SlackBot
- **AWS Lambda**: Gemini 2.5 Flash APIによる議事録分析エンジン
- **Slack/Notion連携**: 分析結果の自動通知・データベース化
- **LocalStack**: ローカル開発環境

### 管理方針

| コンポーネント | 管理方法 |
|---|---|
| AWS Lambda, IAM | Terraform（IaC） |
| Slack App, Google Drive | 手動設定 |

詳細な設計については [docs/architecture.md](docs/architecture.md) を参照してください。

## 📥 データフロー

1. **ファイル選択**: SlackBotでGoogle Driveファイルを選択
2. **ファイル取得**: Lambda関数がGoogle Drive APIでファイルを直接読み込み
3. **AI分析**: Gemini 2.5 Flash APIで議事録を構造化分析
4. **結果配信**: Slack通知とNotion自動作成

### 入力形式
```json
{
  "file_id": "1234567890abcdef",
  "file_name": "2025年1月15日_新機能リリース進捗確認ミーティング.txt"
}
```

## 📁 プロジェクト構成

```
minutes-analyzer/
├── 📁 analyzer/             # メインアプリケーション
│   ├── 📁 infrastructure/   # Terraform + LocalStack
│   │   ├── 📁 environments/  # 環境別設定
│   │   │   ├── 📁 local/     # LocalStack設定
│   │   │   └── 📁 production/# 本番環境設定
│   │   ├── 📁 modules/       # 再利用可能なTerraformモジュール
│   │   └── 📁 scripts/       # デプロイスクリプト
│   ├── 📁 lambda/           # Ruby Lambda関数
│   ├── 📁 prompts/          # AIプロンプト
│   ├── 📁 scripts/          # ユーティリティスクリプト
│   └── 📁 sample-data/      # テストデータ
├── 📁 drive-selector/       # SlackBot（GoogleDrive上のファイルを選択）
├── 📁 docs/                 # ドキュメント
└── 📁 test/                 # 統合テスト
```

## 🔐 環境変数

### 必須設定
- `GEMINI_API_KEY`: Gemini API キー（[Google AI Studio](https://makersuite.google.com/app/apikey)で取得）
- `GOOGLE_SERVICE_ACCOUNT_JSON`: Google サービスアカウント認証情報

### オプション設定
- `SLACK_BOT_TOKEN`: Slack Bot OAuth Token
- `SLACK_CHANNEL_ID`: 通知先チャンネルID
- `NOTION_API_KEY`: Notion Integration トークン
- `NOTION_DATABASE_ID`: 議事録用データベースID
- `NOTION_TASK_DATABASE_ID`: タスク管理用データベースID

### 設定ガイド
詳細な設定手順は以下のドキュメントを参照してください：
- [Google Drive API設定](docs/google-drive-api-setup.md)
- [Slack Integration設定](docs/slack-integration-guide.md)

## 📖 ドキュメント

- [システムアーキテクチャ](docs/architecture.md)
- [Google Drive API設定](docs/google-drive-api-setup.md) 
- [Slack Integration設定](docs/slack-integration-guide.md)
- [統合テスト手順](docs/integration-test-guide.md)
- [Makefileコマンド](docs/makefile-commands.md)

## 🛠️ トラブルシューティング

### よくある問題と解決方法

**LocalStackが起動しない**
```bash
cd analyzer && make clean  # 完全クリーンアップ
docker ps                 # Docker状態確認
```

**GEMINI_API_KEYエラー**
```bash
grep GEMINI_API_KEY analyzer/.env.local  # 設定確認
```
[Google AI Studio](https://makersuite.google.com/app/apikey)でキーを再生成してください。

## 📄 ライセンス

このプロジェクトは [MIT License](LICENSE) の下で公開されています。
