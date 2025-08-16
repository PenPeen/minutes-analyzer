# Makefileコマンド一覧

議事録分析システムで使用するMakefileコマンドの概要です。

## analyzer/Makefile（メイン分析機能）

### 開発コマンド

| コマンド | 役割 |
|---------|------|
| `help` | 利用可能コマンド表示 |
| `setup` | 初期セットアップ（.env.local作成、依存関係インストール） |
| `start` | LocalStack開発環境起動 |
| `deploy-local` | ローカル環境への完全デプロイ |
| `stop` | 開発環境停止 |

### 本番デプロイ

| コマンド | 役割 |
|---------|------|
| `deploy-production` | 本番環境への完全デプロイ |
| `destroy-production` | 本番環境リソース削除 |

### テスト・メンテナンス

| コマンド | 役割 |
|---------|------|
| `test` | RSpecテスト実行 |
| `health-check` | APIエンドポイント動作確認 |
| `clean` | 環境クリーンアップ |

## drive-selector/Makefile（Slack Bot機能）

### 基本コマンド

| コマンド | 役割 |
|---------|------|
| `setup` | 初期セットアップ |
| `deploy-production` | 本番環境デプロイ |
| `test` | RSpecテスト実行 |
| `logs` | CloudWatch Logs表示 |

## プロジェクト間の主な違い

- **analyzer**: LocalStack対応、ローカル開発環境あり
- **drive-selector**: 本番環境のみ、よりシンプルな構成

## 基本的な開発フロー

### analyzer（ローカル開発）
```bash
cd analyzer
make setup           # 初回のみ
make start           # LocalStack起動
make deploy-local    # アプリケーションデプロイ
make test           # テスト実行
```

### 本番デプロイ
```bash
# analyzer
cd analyzer && make deploy-production

# drive-selector
cd drive-selector && make deploy-production
```