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

#### 2. 各サービスの初期セットアップ
```bash
# analyzer（議事録分析エンジン）
cd analyzer
make setup

# drive-selector（SlackBot）
cd drive-selector
make setup
```

#### 3. 環境変数設定

`.env.production` ファイルに設定後、`scripts/set-production-secrets.sh` でSecrets Managerに反映

**必須設定**
- `GEMINI_API_KEY`: Gemini API キー
- `GOOGLE_SERVICE_ACCOUNT_JSON`: Google サービスアカウント認証情報
- `SLACK_BOT_TOKEN`: Slack Bot OAuth Token
- `SLACK_CHANNEL_ID`: 通知先チャンネルID

**オプション設定**
- `NOTION_API_KEY`: Notion Integration トークン
- `NOTION_DATABASE_ID`: 議事録用データベースID
- `NOTION_TASK_DATABASE_ID`: タスク管理用データベースID

詳細な設定手順は[環境変数設定](#-環境変数)セクションを参照してください。

### 開発環境の起動

#### analyzer（議事録分析エンジン）
```bash
cd analyzer
make start        # 環境起動・ビルド・ローカル自動デプロイ
make stop         # 環境停止
make test         # テスト実行
```

#### drive-selector（SlackBot）
```bash
cd drive-selector
make start        # 環境起動・デプロイ
make stop         # 環境停止
make test         # テスト実行
```

#### 本番デプロイ
```bash
# analyzer（議事録分析エンジン）
cd analyzer
make deploy-production

# drive-selector（SlackBot）
cd drive-selector
make deploy-production
```

## 📋 主要コマンド

### analyzer（議事録分析エンジン）
以下のコマンドは`analyzer`ディレクトリ内で実行してください：

```bash
make help           # 利用可能なコマンドを表示
make setup          # 初期セットアップ
make start          # 開発環境起動・デプロイ
make test           # テスト実行
make clean          # 環境クリーンアップ
make deploy-production  # 本番デプロイ
```

### drive-selector（SlackBot）
以下のコマンドは`drive-selector`ディレクトリ内で実行してください：

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

本システムは**マイクロサービス型**のサーバーレスアーキテクチャを採用し、2つの独立したサービスから構成されています：

### マイクロサービス構成

| サービス | 役割 | 技術スタック |
|---------|-----|-------------|
| **drive-selector** | Google Driveファイル選択UI | Slack Bot + AWS Lambda (Ruby) |
| **analyzer** | 議事録AI分析エンジン | AWS Lambda (Ruby) + Gemini 2.5 Flash |

### 連携フロー

```
Slack User → drive-selector → analyzer → Slack/Notion
```

1. **drive-selector**: SlackでGoogle Driveファイルを選択
2. **analyzer**: 選択されたファイルをAI分析。分析結果をSlack通知・Notion連携

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
│   ├── 📁 infrastructure/   # Terraform設定
│   │   ├── 📁 environments/  # 環境別設定
│   │   │   └── 📁 production/# 本番環境設定
│   │   ├── 📁 modules/       # 再利用可能なTerraformモジュール
│   │   └── 📁 scripts/       # デプロイスクリプト
│   ├── 📁 lambda/           # Ruby Lambda関数
│   ├── 📁 prompts/          # AIプロンプト
│   ├── 📁 scripts/          # ユーティリティスクリプト
│   └── 📁 sample-data/      # テストデータ
├── 📁 drive-selector/       # SlackBot（GoogleDrive上のファイルを選択）
│   ├── 📁 infrastructure/   # インフラ設定
│   │   ├── 📁 docker/       # Dockerビルド環境
│   │   └── 📁 environments/ # 環境別設定
│   │       └── 📁 production/# 本番環境設定
│   ├── 📁 lambda/           # Ruby Lambda関数
│   │   ├── 📁 lib/          # ライブラリモジュール
│   │   └── 📁 spec/         # テストファイル
│   ├── 📁 docs/             # Slack・Google API設定ドキュメント
│   └── 📁 scripts/          # デプロイ・設定スクリプト
├── 📁 docs/                 # ドキュメント
└── 📁 test/                 # 統合テスト
```

## 🔐 環境変数

### 必須設定
- `GEMINI_API_KEY`: Gemini API キー（[Google AI Studio](https://makersuite.google.com/app/apikey)で取得）
- `GOOGLE_SERVICE_ACCOUNT_JSON`: Google サービスアカウント認証情報
- `SLACK_BOT_TOKEN`: Slack Bot OAuth Token
- `SLACK_CHANNEL_ID`: 通知先チャンネルID

### オプション設定
- `NOTION_API_KEY`: Notion Integration トークン
- `NOTION_DATABASE_ID`: 議事録用データベースID
- `NOTION_TASK_DATABASE_ID`: タスク管理用データベースID

### 設定ガイド
詳細な設定手順は以下のドキュメントを参照してください：
- [Google Drive API設定](docs/google-drive-api-setup.md)
- [Slack Integration設定](docs/slack-integration-guide.md)

## ⚠️ セキュリティ・機密情報に関する注意点

機密情報を扱う際は以下の点にご注意ください：

1. **Gemini APIのデータ利用について**
   - 無料プランなど特定のプランではオプトアウト不可のため、機密情報の処理は避けてください
   - 詳細は[Gemini APIのプライバシーポリシー](https://ai.google.dev/gemini-api/terms)を確認してください

2. **ネットワークセキュリティについて**
   - VPCエンドポイントなどのセキュリティ機能については本アプリでは未対応です
   - 本番環境では適切なネットワークセキュリティ対策を検討してください

## 📖 ドキュメント

- [システムアーキテクチャ](docs/architecture.md)
- [Google Drive API設定](docs/google-drive-api-setup.md)
- [Slack Integration設定](docs/slack-integration-guide.md)
- [統合テスト手順](docs/integration-test-guide.md)
- [Makefileコマンド](docs/makefile-commands.md)

## 🛠️ トラブルシューティング

### よくある問題と解決方法

**ビルドエラー**
```bash
cd analyzer && make clean  # 完全クリーンアップ
make build-lambda          # Lambda関数再ビルド
```

**GEMINI_API_KEYエラー**
```bash
grep GEMINI_API_KEY analyzer/.env.production  # 設定確認
```
[Google AI Studio](https://makersuite.google.com/app/apikey)でキーを再生成してください。

## 📄 ライセンス

このプロジェクトは [MIT License](LICENSE) の下で公開されています。
