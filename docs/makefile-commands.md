# Makefileコマンド一覧

議事録分析システムで使用するMakefileコマンドの概要です。

## analyzer/Makefile（メイン分析機能）

### 開発コマンド

| コマンド | 役割 |
|---------|------|
| `help` | 利用可能コマンド表示 |
| `setup` | 初期セットアップ（依存関係インストール） |
| `build-lambda` | Lambda関数ビルド |
| `test` | RSpecテスト実行 |

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

## 基本的な開発フロー

### analyzer（開発・テスト）
```bash
cd analyzer
make setup           # 初回のみ
make build-lambda    # Lambda関数ビルド
make test           # テスト実行
```

### 本番デプロイ
```bash
# analyzer
cd analyzer && make deploy-production

# drive-selector
cd drive-selector && make deploy-production
```