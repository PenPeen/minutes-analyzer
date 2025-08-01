# 議事録口出しBot

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-≥1.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![Ruby](https://img.shields.io/badge/Ruby-≥3.3-CC342D?logo=ruby)](https://www.ruby-lang.org/)

Google Meetの文字起こしを自動分析し、決定事項・アクション項目・懸念事項を抽出してSlackに通知するシステムです。

## ✨ Features

- 🤖 **AI分析**: Gemini 1.5 Flash APIによる議事録分析
- 📋 **自動抽出**: 決定事項・アクション項目・懸念事項を自動識別
- 📢 **Slack連携**: 分析結果のSlack通知
- 💰 **コスト効率**: 月間$2-4の低コスト運用（100回/日実行時）

## 🚀 クイックスタート

### 前提条件
- Docker & Docker Compose
- Terraform ≥ 1.0
- Ruby ≥ 3.3
- AWS CLI

### セットアップ

```bash
git clone https://github.com/your-username/minutes-analyzer.git
cd minutes-analyzer

# 初期セットアップ
make setup

# 環境変数ファイルをコピーして設定
cp env.sample .env.local
# .env.localを編集してGEMINI_API_KEYを設定

# 開発環境の起動
make dev-setup
```

## 📋 使用可能なコマンド

```bash
make help                    # 利用可能なコマンドを表示
make setup                   # 初期セットアップ
make dev-setup              # 開発環境完全セットアップ
make deploy-local           # LocalStack環境にデプロイ
make test-api               # APIエンドポイントをテスト
make logs                   # CloudWatchログを確認
make clean                  # ローカル環境をクリーンアップ
```

## 🏗️ アーキテクチャ

このプロジェクトは**Google Apps Script + AWS Lambda ハイブリッド型**のアーキテクチャを採用しています：

- **Google Apps Script**: Google Driveの監視・前処理・Slack配信
- **AWS Lambda (Ruby)**: Gemini 1.5 Flash APIを使用した議事録分析
- **API Gateway**: RESTful API エンドポイント
- **LocalStack**: ローカル開発環境でのAWSサービスエミュレート

詳細な設計については [docs/architecture.md](docs/architecture.md) を参照してください。

## 📁 プロジェクト構成

```
minutes-analyzer/
├── 📁 infrastructure/        # Terraform + LocalStack
│   ├── 📁 environments/      # 環境別設定
│   ├── 📁 modules/           # 再利用可能なTerraformモジュール
│   └── 📁 scripts/           # デプロイスクリプト
├── 📁 lambda/               # Ruby Lambda関数
├── 📁 gas/                  # Google Apps Script
├── 📁 docs/                 # ドキュメント
└── 📁 tests/                # 統合テスト
```

## �� 環境変数

### 必須設定
- `GEMINI_API_KEY`: Gemini 1.5 Flash APIキー（[Google AI Studio](https://makersuite.google.com/app/apikey)で取得）

### 任意設定
- `SLACK_ERROR_WEBHOOK_URL`: エラー通知用Slack Webhook URL
- `SLACK_SUCCESS_WEBHOOK_URL`: 成功通知用Slack Webhook URL

## 📖 ドキュメント

- [アーキテクチャ設計](docs/architecture.md)
- [API仕様](docs/api-spec.yaml)
- [実装詳細](docs/implementation.md)
- [プロジェクト構成](project-structure.md)

## 🧪 テスト

```bash
# 基本的なAPIテスト
make test-api

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
