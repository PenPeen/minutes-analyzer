# Makefileコマンド一覧と役割

## analyzer/Makefile

### 基本コマンド

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `help` | ヘルプ表示 | 利用可能なコマンドとその説明を表示 |
| `setup` | 初期セットアップ | .env.localの作成、Ruby依存関係のインストール |
| `start` | 開発環境起動 | Docker・LocalStackの起動のみ（デプロイは含まない） |
| `stop` | 開発環境停止 | Dockerコンテナの停止 |

### ビルド関連

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `build-lambda` | Lambda関数ビルド | Dockerを使用してRuby Lambda関数をビルド（内部用） |
| `build-local` | ローカル環境用ビルド | ローカル環境用Lambda関数ビルド |
| `build-production` | 本番環境用ビルド | 本番環境用Lambda関数ビルド |

### LocalStack環境（ローカル開発）

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `deploy-local` | ローカル環境デプロイ | tf-plan→tf-apply→プロンプトアップロード（完全デプロイ） |
| `destroy-local` | ローカル環境破棄 | terraform destroyでローカルリソースを削除 |
| `upload-prompts-local` | ローカル環境プロンプトアップロード | ローカル環境のS3にプロンプトファイルをアップロード |

### 本番環境

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `deploy-production` | 本番環境デプロイ | ビルド→tfvars生成→S3バケット確保→terraform→シークレット設定→プロンプトアップロード |
| `destroy-production` | 本番環境破棄 | terraform destroy + 手動リソース削除（S3、Secrets Manager等） |
| `upload-prompts-production` | 本番環境プロンプトアップロード | 本番環境のS3にプロンプトファイルをアップロード |

### Terraform関連（ローカル環境）

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `tf-init-local` | ローカル環境Terraform初期化 | ローカル環境用terraform initを実行 |
| `tf-plan-local` | ローカル環境Terraformプラン | ローカル環境用terraform planで変更内容を確認 |
| `tf-apply-local` | ローカル環境Terraform適用 | ローカル環境用terraform applyでリソースを作成/更新 |

### Terraform関連（本番環境）

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `tf-init-production` | 本番環境Terraform初期化 | 本番環境用terraform initを実行 |
| `tf-plan-production` | 本番環境Terraformプラン | 本番環境用terraform planで変更内容を確認 |
| `tf-apply-production` | 本番環境Terraform適用 | 本番環境用terraform applyでリソースを作成/更新 |

### 設定・ユーティリティ

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `generate-tfvars-local` | ローカル用設定生成 | .env.localからterraform.tfvarsを生成 |
| `generate-tfvars-production` | 本番用設定生成 | .env.productionからterraform.tfvarsを生成 |
| `ensure-terraform-backend-bucket-production` | 本番S3バケット確保 | 本番環境用Terraform state S3バケットの作成 |
| `wait-for-localstack` | LocalStack待機 | LocalStackの起動完了を待機 |

### テスト・メンテナンス

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `test` | テスト実行 | RSpecを使用したLambda関数のテスト |
| `health-check` | ヘルスチェック | APIエンドポイントの動作確認 |
| `clean` | クリーンアップ | Docker、ビルド成果物、Terraform状態の削除 |

---

## drive-selector/Makefile

### 基本コマンド

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `help` | ヘルプ表示 | 利用可能なコマンドとその説明を表示 |
| `setup` | 初期セットアップ | .env.productionの確認、Ruby依存関係のインストール |

### ビルド関連

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `build-lambda` | Lambda関数ビルド | Dockerを使用してRuby Lambda関数をビルド（内部用） |
| `build-production` | 本番環境用ビルド | 外部向けのビルドコマンド |

### 本番環境のみ

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `deploy-production` | 本番環境デプロイ | tfvars生成→S3バケット確保→ビルド→terraform→シークレット設定 |
| `destroy-production` | 本番環境破棄 | terraform destroyでリソースを削除 |

### Terraform関連

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `tf-init-production` | 本番環境Terraform初期化 | 本番環境用terraform initを実行 |
| `tf-plan-production` | 本番環境Terraformプラン | 本番環境用terraform planで変更内容を確認 |
| `tf-apply-production` | 本番環境Terraform適用 | 本番環境用terraform applyでリソースを作成/更新 |

### 設定・ユーティリティ

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `generate-tfvars-production` | 本番用設定生成 | .env.productionからterraform.tfvarsを生成 |
| `ensure-terraform-backend-bucket-production` | 本番S3バケット確保 | 本番環境用Terraform state S3バケットの作成 |

### テスト・メンテナンス

| コマンド | 役割 | 詳細 |
|---------|------|------|
| `test` | テスト実行 | RSpecを使用したLambda関数のテスト |
| `health-check` | ヘルスチェック | APIエンドポイントの動作確認 |
| `logs` | ログ確認 | Lambda関数のCloudWatch Logsを表示 |
| `check-resources` | リソース確認 | AWSリソースとTerraform状態の整合性チェック |
| `clean` | クリーンアップ | ビルド成果物、Terraform状態の削除 |

---

## 主な違い

1. **analyzer**: LocalStack対応でローカル開発環境あり
2. **drive-selector**: 本番環境のみ、ローカル開発環境なし
3. **analyzer**: より複雑な依存関係（Google認証、プロンプト管理）
4. **drive-selector**: よりシンプルな構成

## 開発フロー

### analyzer での開発フロー
```bash
# 初回セットアップ
cd analyzer
make setup

# 開発サイクル
make start          # Docker・LocalStack起動（1回だけ）
make deploy-local   # アプリケーションデプロイ
# ... コード変更 ...
make deploy-local   # 再デプロイ（即時反映）

# 終了
make stop           # 環境停止
```

### drive-selector での開発フロー
```bash
# 初回セットアップ
cd drive-selector
make setup

# 本番デプロイ
make build-production    # ビルド
make deploy-production   # 本番環境デプロイ
```

## 統一されたコマンド体系

### 共通コマンド
- `make setup` - 初期セットアップ
- `make build-production` - 本番環境用ビルド
- `make deploy-production` - 本番環境デプロイ
- `make destroy-production` - 本番環境破棄
- `make test` - テスト実行
- `make clean` - クリーンアップ
- `make health-check` - ヘルスチェック

### analyzer固有（LocalStack対応）
- `make start` - 開発環境起動
- `make build-local` - ローカル環境用ビルド
- `make deploy-local` - ローカル環境デプロイ
- `make destroy-local` - ローカル環境破棄
- `make stop` - 開発環境停止