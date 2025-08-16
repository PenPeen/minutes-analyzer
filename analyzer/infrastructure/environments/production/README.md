# 本番環境デプロイ

議事録分析システムの本番環境へのデプロイ手順です。

## デプロイ手順

### 1. AWS認証設定
```bash
export AWS_PROFILE=your-production-profile
```

### 2. 設定ファイル準備
```bash
cp terraform.tfvars.sample terraform.tfvars
# 必要に応じて値を編集
```

### 3. デプロイ実行
```bash
cd analyzer
make deploy-production
```

## 本番環境の特徴

### インフラ構成
- S3ステート管理による状態の永続化
- CloudWatchによる監視・アラート自動設定
- Lambda: 512MB メモリ、15分タイムアウト
- API Gateway: APIキー認証有効

### セキュリティ
- 機密情報はAWS Secrets Managerで管理
- 最小権限IAMポリシー適用
- VPC内でのセキュアな通信

### 運用監視
- CloudWatchログによる詳細ログ出力
- エラー率・実行時間のアラート
- コスト監視ダッシュボード
