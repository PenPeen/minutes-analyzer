# デプロイメントガイド

## 前提条件

### 必要なツール
- Docker Desktop
- Terraform >= 1.0
- AWS CLI
- Ruby 3.2
- Make

### 必要な権限
- AWS IAMロール（Lambda、S3、Secrets Manager、CloudWatch）
- Google Calendar API（サービスアカウント）
- Slack Bot Token
- Notion API Key

## デプロイ手順

### 1. 開発環境へのデプロイ

#### 初回セットアップ
```bash
# 1. 環境変数の設定
cp infrastructure/environments/local/terraform.tfvars.sample terraform.tfvars
vim terraform.tfvars  # APIキー等を設定

# 2. LocalStackの起動
make setup

# 3. 初回デプロイ
make start
```

#### 更新デプロイ
```bash
# コード変更後
make build-lambda
make deploy-local
```

#### 動作確認
```bash
# Lambda関数のテスト
make test-lambda

# ログの確認
make logs
```

### 2. 本番環境へのデプロイ

#### 事前準備チェックリスト
- [ ] すべてのテストが成功している
- [ ] 開発環境での動作確認完了
- [ ] APIキーがSecrets Managerに設定済み
- [ ] CloudWatchアラームの通知先設定済み
- [ ] バックアップ取得済み

#### デプロイコマンド
```bash
# 1. 本番環境の設定
cd infrastructure/environments/production
cp terraform.tfvars.sample terraform.tfvars
vim terraform.tfvars

# 2. Terraformの初期化
terraform init

# 3. 変更内容の確認
terraform plan

# 4. デプロイ実行
terraform apply

# または Makefileを使用
make deploy-production
```

#### デプロイ後の確認
```bash
# Lambda関数の状態確認
aws lambda get-function \
  --function-name minutes-analyzer-production

# 最新のログ確認
aws logs tail /aws/lambda/minutes-analyzer-production --follow

# メトリクスの確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=minutes-analyzer-production \
  --start-time 2025-01-01T00:00:00Z \
  --end-time 2025-01-01T01:00:00Z \
  --period 300 \
  --statistics Sum
```

## ロールバック手順

### 即座のロールバック
```bash
# 前のバージョンにロールバック
aws lambda update-function-code \
  --function-name minutes-analyzer-production \
  --s3-bucket minutes-analyzer-lambda-production \
  --s3-key lambda-previous.zip

# またはTerraformで前の状態に戻す
terraform apply -target=aws_lambda_function.minutes_analyzer \
  -var="lambda_zip_path=lambda-previous.zip"
```

### Gitベースのロールバック
```bash
# 前のコミットに戻す
git revert HEAD
git push origin main

# CI/CDパイプラインが自動デプロイ
```

## CI/CDパイプライン設定

### GitHub Actions設定例
```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          
      - name: Build Lambda
        run: |
          cd lambda
          bundle install
          zip -r ../lambda.zip .
          
      - name: Deploy to AWS
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: |
          aws lambda update-function-code \
            --function-name minutes-analyzer-production \
            --zip-file fileb://lambda.zip
```

## 環境別設定

### 開発環境（LocalStack）
```hcl
# terraform.tfvars
environment = "local"
aws_region = "ap-northeast-1"
lambda_timeout = 900
lambda_memory_size = 512
log_retention_days = 7
google_calendar_enabled = true
user_mapping_enabled = true
```

### ステージング環境
```hcl
# terraform.tfvars
environment = "staging"
aws_region = "ap-northeast-1"
lambda_timeout = 600
lambda_memory_size = 512
log_retention_days = 14
google_calendar_enabled = true
user_mapping_enabled = true
```

### 本番環境
```hcl
# terraform.tfvars
environment = "production"
aws_region = "ap-northeast-1"
lambda_timeout = 900
lambda_memory_size = 1024
log_retention_days = 30
google_calendar_enabled = true
user_mapping_enabled = true
```

## モニタリングとアラート

### デプロイ後のモニタリング
1. CloudWatch Dashboardを開く
2. 以下のメトリクスを確認：
   - Lambda Invocations
   - Error Rate
   - Duration
   - Success Rate
   - API Call Counts

### アラート設定の確認
```bash
# アラーム一覧
aws cloudwatch describe-alarms \
  --alarm-name-prefix minutes-analyzer-production

# アラーム履歴
aws cloudwatch describe-alarm-history \
  --alarm-name minutes-analyzer-error-rate-production
```

## トラブルシューティング

### デプロイ失敗時

#### Terraform state lock
```bash
# ロックの強制解除
terraform force-unlock <lock-id>
```

#### Lambda更新エラー
```bash
# 関数の状態確認
aws lambda get-function-configuration \
  --function-name minutes-analyzer-production

# 最終更新ステータス確認
aws lambda get-function \
  --function-name minutes-analyzer-production \
  --query 'Configuration.LastUpdateStatus'
```

### パフォーマンス問題

#### コールドスタート対策
```hcl
# 予約された同時実行数を設定
resource "aws_lambda_provisioned_concurrency_config" "main" {
  function_name = aws_lambda_function.minutes_analyzer.function_name
  provisioned_concurrent_executions = 2
  qualifier = aws_lambda_function.minutes_analyzer.version
}
```

#### メモリ最適化
```bash
# CloudWatch Insightsでメモリ使用量を分析
aws logs start-query \
  --log-group-name /aws/lambda/minutes-analyzer-production \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string '
    fields @timestamp, @memorySize, @maxMemoryUsed
    | stats avg(@maxMemoryUsed), max(@maxMemoryUsed), min(@maxMemoryUsed)
  '
```

## セキュリティチェックリスト

### デプロイ前
- [ ] APIキーがコードに含まれていない
- [ ] Secrets Managerのアクセス権限が最小限
- [ ] S3バケットが非公開設定
- [ ] CloudWatchログの暗号化有効

### デプロイ後
- [ ] 不要なIAM権限の削除
- [ ] APIキーのローテーション計画
- [ ] セキュリティグループの確認
- [ ] 監査ログの有効化

## ベストプラクティス

1. **段階的デプロイ**
   - まず開発環境でテスト
   - 次にステージング環境
   - 最後に本番環境

2. **ブルーグリーンデプロイ**
   - Lambda aliasを使用
   - トラフィックの段階的切り替え

3. **自動テスト**
   - デプロイ前にユニットテスト実行
   - デプロイ後に統合テスト実行

4. **ドキュメント更新**
   - 変更内容をCHANGELOG.mdに記載
   - APIドキュメントの更新

5. **通知**
   - デプロイ開始/完了をSlackに通知
   - エラー発生時の自動アラート