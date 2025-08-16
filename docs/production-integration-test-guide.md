# 本番環境 統合テスト手順

議事録分析システムの本番環境での統合テストを実施する手順です。

## 前提条件

- AWS CLIの設定完了
- 本番環境デプロイ完了
- Lambda Function URL設定済み
- 必要な認証情報がSecrets Managerに設定済み

## テスト実施手順

### 1. テスト実行

```bash
# 1. デプロイ情報確認
cd analyzer/infrastructure/environments/production
terraform output

# 2. Lambda Function URL取得
export LAMBDA_URL=$(terraform output -raw lambda_function_url)

# 3. テスト実行
curl -X POST "$LAMBDA_URL" \
  -H "Content-Type: application/json" \
  -d @../../sample-data/test_prod_api_gateway_payload.json \
  -o test_result.json

# 4. 結果確認
cat test_result.json | jq '.'
```

### 4. テストペイロードのカスタマイズ

`analyzer/sample-data/test_prod_api_gateway_payload.json` の `file_id` を実際のGoogle DriveファイルIDに変更して使用してください：

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
cd analyzer
make deploy-production

# デプロイ状態の確認
cd analyzer/infrastructure/environments/production
terraform output

# リソースの削除（必要な場合）
cd analyzer
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
