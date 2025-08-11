# Production Environment

本番環境へのデプロイ設定

## 必須の事前準備

### 1. S3バケットの作成（必須）

**重要**: Terraformが動作するために、状態ファイル保存用のS3バケットを**必ず最初に**作成してください。

```bash
# S3バケットを作成
aws s3api create-bucket \
  --bucket minutes-analyzer-terraform-state \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1
```

このバケットがないとデプロイは失敗します。

## デプロイ手順

### 1. AWS認証情報の設定
```bash
export AWS_PROFILE=your-production-profile
# または
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
```

### 2. 設定ファイルの準備
```bash
# サンプルファイルからコピー
cp terraform.tfvars.sample terraform.tfvars
# 必要に応じて値を編集
```

### 3. デプロイ実行
```bash
make deploy-production
```

## 重要事項

- Gemini API キーなどの機密情報は、デプロイ後にAWS Secrets Managerで設定
- CloudWatchアラームが自動設定される

## Differences from Local Environment

- No LocalStack endpoints configuration
- S3 backend for state management
- Production-grade monitoring with CloudWatch alarms
- Higher Lambda memory (512MB) and timeout (15 minutes)
- API key required for API Gateway