# 議事録口出しBot

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![Ruby](https://img.shields.io/badge/Ruby-≥3.3-CC342D?logo=ruby)](https://www.ruby-lang.org/)

Google Meetの文字起こしを自動分析し、決定事項・アクション項目・懸念事項を抽出してSlackに通知するシステムです。

## ✨ Features

- 🤖 **AI分析**: Gemini 2.5 Flash APIによる議事録分析
- 📋 **自動抽出**: 決定事項・アクション項目・懸念事項を自動識別
- 📢 **Slack連携**: 分析結果のSlack通知
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
- `GEMINI_API_KEY`: Gemini API キーを設定
- `SLACK_WEBHOOK_URL`: Slack Incoming Webhook URLを設定

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

- **Google Apps Script**: Google Driveの監視・前処理・Slack配信
- **AWS Lambda (Ruby)**: Gemini 2.5 Flash APIを使用した議事録分析
- **API Gateway**: RESTful API エンドポイント
- **LocalStack**: ローカル開発環境でのAWSサービスエミュレート

詳細な設計については [docs/architecture.md](docs/architecture.md) を参照してください。

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
- `SLACK_WEBHOOK_URL`: Slack Incoming Webhook URL（[Slack App](https://api.slack.com/apps)で取得）

## 📖 ドキュメント

- [アーキテクチャ設計](docs/architecture.md)

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

## 🤝 コントリビューション

1. フォークを作成
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

## 📄 ライセンス

このプロジェクトは [MIT License](LICENSE) の下で公開されています。
