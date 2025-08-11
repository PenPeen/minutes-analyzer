# 本番環境 統合テスト実施手順書

## 概要
本書は、議事録分析システムの本番環境（AWS）での統合テストを実施するための手順書です。
Lambda Function URLを使用して直接Lambda関数を呼び出す方式を採用しています。

## 前提条件

### 必要な環境
- AWS CLIがインストールされ、認証情報が設定されていること
- 本番環境へのデプロイが完了していること
- Lambda Function URLが設定済みであること

### 必要な認証情報
- Google Drive のテストファイルID
- AWS Secrets Manager に以下が設定済み：
  - GEMINI_API_KEY
  - GOOGLE_SERVICE_ACCOUNT_JSON
  - SLACK_BOT_TOKEN（オプション）
  - NOTION_API_KEY（オプション）

## テスト実施手順

### 1. デプロイ情報の確認

```bash
# デプロイ済みのリソース情報を取得
cd infrastructure/environments/production
terraform output

# 以下の情報をメモ：
# - lambda_function_url: Lambda Function URL
# - lambda_function_name: Lambda関数名
# - cloudwatch_log_group: ログ確認用のCloudWatch Log Group名
```

### 2. テストデータの準備

既存のテストファイル `test/sample-data/test_prod_api_gateway_payload.json` を使用します：

```json
{
  "file_id": "1gr4YjB-m98qSqa4739VOXgI5UZa1GBtvsur04bpG-rg",
  "file_name": "議事録テストファイル.txt"
}
```

**注意**: `file_id` は実際のGoogle Drive上のファイルIDです。必要に応じて変更してください。

### 3. Lambda Function URL経由でのテスト実行

Lambda Function URLを使用して直接Lambda関数を呼び出します。
この方式では最大15分までの処理に対応可能です。

```bash
# Lambda Function URLを取得
export LAMBDA_URL=$(cd infrastructure/environments/production && terraform output -raw lambda_function_url)

# Lambda Function URL経由でテスト実行
curl -X POST "$LAMBDA_URL" \
  -H "Content-Type: application/json" \
  -d @test/sample-data/test_prod_api_gateway_payload.json \
  -o lambda_url_test_result.json

# 結果を整形して表示
cat lambda_url_test_result.json | jq '.'
```

### 4. テストペイロードのカスタマイズ

`test/sample-data/test_prod_api_gateway_payload.json` の `file_id` を実際のGoogle DriveファイルIDに変更して使用してください：

```json
{
  "file_id": "YOUR_GOOGLE_DRIVE_FILE_ID",
  "file_name": "議事録テストファイル.txt"
}
```

### 5. ログの確認

Lambda関数の実行ログはCloudWatch Logsで確認できます：

```bash
# ログストリームを確認
aws logs describe-log-streams \
  --log-group-name "/aws/lambda/minutes-analyzer-production" \
  --order-by LastEventTime \
  --descending \
  --limit 5

# 最新のログを取得
aws logs get-log-events \
  --log-group-name "/aws/lambda/minutes-analyzer-production" \
  --log-stream-name "最新のログストリーム名" \
  --limit 50
```

### 6. トラブルシューティング

#### タイムアウトエラー
- Lambda Function URLは最大15分までの処理に対応しています
- それでもタイムアウトする場合は、Lambda関数のタイムアウト設定を確認してください

#### 認証エラー
- Secrets Managerに必要な認証情報が設定されているか確認
- Google Service Accountの権限が適切に設定されているか確認

#### エンコーディングエラー
- Lambda関数内でUTF-8エンコーディングが正しく設定されているか確認

## 本番環境へのデプロイ

本番環境へのデプロイはMakefileを使用して実行します：

```bash
# 本番環境へのデプロイ
make deploy-production

# デプロイ状態の確認
cd infrastructure/environments/production
terraform output

# リソースの削除（必要な場合）
make destroy-production
```

## セキュリティ上の注意事項

1. **Lambda Function URLのセキュリティ**
   - 現在は認証なし（`authorization_type = "NONE"`）で設定されています
   - 本番運用時は必要に応じてIAM認証（`AWS_IAM`）への変更を検討してください

2. **シークレット管理**
   - すべての認証情報はAWS Secrets Managerで管理されています
   - 定期的にシークレットのローテーションを実施してください

3. **ログ管理**
   - CloudWatch Logsの保存期間は環境変数で設定されています
   - 機密情報がログに含まれないよう注意してください
