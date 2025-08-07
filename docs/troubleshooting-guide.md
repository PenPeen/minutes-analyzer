# トラブルシューティングガイド

## 目次
1. [環境構築の問題](#環境構築の問題)
2. [API関連のエラー](#api関連のエラー)
3. [Lambda実行エラー](#lambda実行エラー)
4. [データ処理の問題](#データ処理の問題)
5. [パフォーマンスの問題](#パフォーマンスの問題)

## 環境構築の問題

### LocalStackが起動しない

**症状**: `make start`実行時にLocalStackコンテナが起動しない

**原因と解決方法**:
1. Dockerが起動していることを確認
   ```bash
   docker info
   ```

2. ポートの競合を確認
   ```bash
   lsof -i :4566
   ```
   別のプロセスが使用している場合は停止

3. LocalStackコンテナをリセット
   ```bash
   docker-compose down -v
   docker-compose up -d
   ```

### Terraformエラー

**症状**: `terraform apply`が失敗する

**解決方法**:
1. 状態ファイルをリフレッシュ
   ```bash
   terraform refresh
   terraform plan
   ```

2. 必要に応じて状態をリセット
   ```bash
   terraform destroy -auto-approve
   terraform apply -auto-approve
   ```

## API関連のエラー

### Google Calendar API

#### "Daily Limit Exceeded"
**原因**: API利用制限に到達

**解決方法**:
1. Google Cloud Consoleで使用量を確認
2. 必要に応じてクォータの引き上げをリクエスト
3. キャッシュを活用してAPI呼び出しを削減

#### "Not Found"エラー
**原因**: カレンダーまたはイベントが見つからない

**チェックリスト**:
- [ ] サービスアカウントにカレンダーへのアクセス権限がある
- [ ] カレンダーIDが正しい
- [ ] イベントが指定期間内に存在する

### Slack API

#### Rate Limiting (429エラー)
**症状**: "rate_limited"エラーが発生

**解決方法**:
```ruby
# SlackUserManagerのレート制限設定を調整
RATE_LIMIT_PER_MINUTE = 30  # デフォルト50から下げる
```

#### ユーザーが見つからない
**原因**: メールアドレスの不一致

**解決方法**:
1. Slackのプロフィールでメールアドレスを確認
2. 大文字小文字の違いをチェック
3. エイリアスメールアドレスの使用を確認

### Notion API

#### "validation_error"
**原因**: プロパティタイプの不一致

**解決方法**:
1. データベーススキーマを確認
   ```ruby
   # プロパティタイプを確認
   notion_client.retrieve_database(database_id)
   ```

2. 送信データの形式を修正
   ```ruby
   # 正しい形式の例
   {
     "Assignee": {
       "people": [{"id": "user-id"}]
     }
   }
   ```

#### 権限エラー
**症状**: "unauthorized"または"restricted_resource"

**チェックリスト**:
- [ ] インテグレーションがデータベースに接続されている
- [ ] User Information With Email Addresses権限が有効
- [ ] APIキーが正しくコピーされている

## Lambda実行エラー

### タイムアウト

**症状**: Task timed out after X seconds

**解決方法**:
1. タイムアウト値を増やす
   ```hcl
   # terraform.tfvars
   lambda_timeout = 900  # 15分に増加
   ```

2. 処理を最適化
   - 並列処理を活用
   - 不要なAPI呼び出しを削減
   - キャッシュを活用

### メモリ不足

**症状**: Runtime exited with error: signal: killed

**解決方法**:
```hcl
# terraform.tfvars
lambda_memory_size = 1024  # 512MBから1GBに増加
```

### 依存関係エラー

**症状**: cannot load such file

**解決方法**:
1. Gemfileの依存関係を確認
2. Lambda zipを再ビルド
   ```bash
   make build-lambda
   make deploy-local
   ```

## データ処理の問題

### 議事録の解析失敗

**症状**: 議事録から情報を抽出できない

**チェックリスト**:
- [ ] ファイル形式が正しい（UTF-8テキスト）
- [ ] Gemini議事録の標準フォーマットに準拠
- [ ] ファイルサイズが制限内（10MB以下）

### 参加者マッピング失敗

**症状**: 参加者がSlack/Notionユーザーにマッピングされない

**デバッグ手順**:
1. ログを確認
   ```bash
   aws logs tail /aws/lambda/minutes-analyzer-local --follow
   ```

2. メールアドレスの形式を確認
   ```ruby
   # デバッグ用コード
   puts "Calendar participants: #{participants.inspect}"
   puts "Slack lookup result: #{slack_user.inspect}"
   ```

### アクション項目の抽出漏れ

**原因**: プロンプトの精度不足

**解決方法**:
1. プロンプトファイルを更新
   ```bash
   aws s3 cp updated_prompt.txt s3://minutes-analyzer-prompts-local/
   ```

2. スキーマファイルを調整
   ```json
   {
     "actions": {
       "type": "array",
       "minItems": 0,
       "items": {...}
     }
   }
   ```

## パフォーマンスの問題

### 処理速度が遅い

**最適化ポイント**:

1. **並列処理の活用**
   ```ruby
   config[:parallel_processing] = true
   config[:max_threads] = 10
   ```

2. **キャッシュの活用**
   ```ruby
   CACHE_TTL = 1800  # 30分に延長
   ```

3. **バッチ処理**
   ```ruby
   # 個別処理の代わりにバッチ処理を使用
   batch_lookup_users(emails)
   ```

### API呼び出しの最適化

**レート制限の回避**:
```ruby
# API呼び出し間隔を調整
sleep(0.1) between API calls

# リトライロジックの実装
max_retries = 3
retry_count = 0
begin
  api_call()
rescue RateLimitError => e
  retry_count += 1
  sleep(e.retry_after)
  retry if retry_count < max_retries
end
```

## ログとモニタリング

### CloudWatchログの確認

```bash
# 最新のエラーログを取得
aws logs filter-log-events \
  --log-group-name /aws/lambda/minutes-analyzer-local \
  --filter-pattern "ERROR"

# 特定のリクエストIDでフィルタ
aws logs filter-log-events \
  --log-group-name /aws/lambda/minutes-analyzer-local \
  --filter-pattern "{$.request_id = \"xxx\"}"
```

### メトリクスの確認

```bash
# カスタムメトリクスを取得
aws cloudwatch get-metric-statistics \
  --namespace MinutesAnalyzer \
  --metric-name SuccessRate \
  --start-time 2025-01-01T00:00:00Z \
  --end-time 2025-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average
```

### Dead Letter Queueの確認

```bash
# DLQのメッセージを確認
aws sqs receive-message \
  --queue-url https://sqs.region.amazonaws.com/xxx/minutes-analyzer-dlq-local \
  --max-number-of-messages 10
```

## 緊急時の対応

### サービス停止時

1. **CloudWatchアラームの確認**
2. **最新のデプロイをロールバック**
   ```bash
   git revert HEAD
   make deploy-production
   ```
3. **DLQからメッセージを再処理**

### データ不整合

1. **影響範囲の特定**
2. **バックアップからの復旧**
3. **再処理の実行**

## サポート

問題が解決しない場合は、以下の情報と共に報告してください：

1. エラーメッセージ全文
2. 実行環境（ローカル/本番）
3. 関連するログ（request_id含む）
4. 再現手順
5. 試した解決方法