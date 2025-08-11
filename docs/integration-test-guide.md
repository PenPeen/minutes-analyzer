# 統合テスト実施手順書

## 概要
本書は、議事録分析システムの統合テストを実施するための手順書です。LocalStack環境でのテストから本番環境でのテストまでを網羅しています。

## 前提条件

### 必要な環境
- Docker および Docker Compose が起動していること
- LocalStack が稼働していること
- AWS CLI がインストールされていること
- 必要な環境変数が `.env.local` に設定されていること

### 必要な認証情報
- Google Drive API のサービスアカウント認証情報
- Gemini API キー
- Slack Bot Token とChannel ID（オプション）
- Notion API キーとDatabase ID（オプション）

## テスト実施手順

### 1. 環境のセットアップ

```bash
# 開発環境の起動（LocalStack、ビルド、デプロイを一括実行）
cd analyzer
make start
```

### 2. テストデータの準備

#### テストペイロードファイル
`analyzer/sample-data/test_dev_integration_payload.json` を使用してください。

```json
{
  "body": "{\"file_id\": \"1gr4YjB-m98qSqa4739VOXgI5UZa1GBtvsur04bpG-rg\", \"file_name\": \"議事録テストファイル.txt\"}",
  "headers": {
    "Content-Type": "application/json"
  }
}
```

**注意**: `file_id` は実際のGoogle Drive上のファイルIDに置き換えてください。

### 3. Lambda関数の呼び出し

#### LocalStack環境でのテスト

```bash
# 統合テストの実行
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
aws --endpoint-url=http://localhost:4566 --region=ap-northeast-1 \
lambda invoke \
--function-name minutes-analyzer-local \
--payload fileb://analyzer/sample-data/test_dev_integration_payload.json \
--cli-read-timeout 120 \
integration_test_result.json

# 実行結果の確認
cat integration_test_result.json | jq '.'
```

#### 本番環境でのテスト（オプション）

```bash
# 本番環境へのデプロイ後
aws lambda invoke \
--function-name minutes-analyzer-production \
--payload fileb://analyzer/sample-data/test_prod_api_gateway_payload.json \
--cli-read-timeout 120 \
production_test_result.json
```

### 4. テスト結果の確認

#### 成功時のレスポンス例

```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": {
    "message": "Analysis complete.",
    "analysis": {
      "meeting_summary": {
        "title": "会議タイトル",
        "date": "YYYY-MM-DD",
        "duration_minutes": 30,
        "participants": ["参加者1", "参加者2"]
      },
      "decisions": [...],
      "actions": [...],
      "health_assessment": {...},
      "improvement_suggestions": [...]
    },
    "integrations": {
      "slack": "sent/not_sent",
      "notion": "created/not_created"
    }
  }
}
```

### 5. ログの確認

#### CloudWatch Logs（LocalStack）での確認

```bash
# 最新のログストリームを確認
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
aws --endpoint-url=http://localhost:4566 --region=ap-northeast-1 \
logs describe-log-streams \
--log-group-name="/aws/lambda/minutes-analyzer-local" \
--order-by LastEventTime --descending --limit 1

# ログイベントの取得
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
aws --endpoint-url=http://localhost:4566 --region=ap-northeast-1 \
logs get-log-events \
--log-group-name="/aws/lambda/minutes-analyzer-local" \
--log-stream-name="<取得したログストリーム名>"
```

## テスト項目チェックリスト

### 基本機能（正常系）
- [ ] Lambda関数が正常に起動する
- [ ] Google Drive APIでファイルを取得できる
- [ ] Gemini APIで議事録分析が実行される
- [ ] 分析結果がJSON形式で返される

### エラーケーステスト（異常系）
- [ ] 無効なfile_idでのエラーハンドリング
- [ ] Google Drive認証失敗時の適切なエラーメッセージ
- [ ] Gemini API制限超過時のリトライ動作
- [ ] Slack/Notion連携失敗時の部分的成功レスポンス
- [ ] タイムアウト時の適切な処理

### 分析結果の確認
- [ ] 会議サマリーが抽出されている
- [ ] 決定事項が正しく抽出されている
- [ ] アクション項目が抽出されている
  - [ ] タスクの背景・文脈情報（task_context）が含まれている
  - [ ] 実行手順（suggested_steps）が含まれている
- [ ] 健全性評価が含まれている
- [ ] 改善提案が生成されている

### 外部連携（設定時のみ）
- [ ] Slack通知が送信される（SLACK_BOT_TOKEN設定時）
- [ ] Notion ページが作成される（NOTION_API_KEY設定時）
- [ ] エラー時も Lambda は200を返す（部分的成功）

## トラブルシューティング

### よくあるエラーと対処法

#### 1. Google Drive API エラー
```
"error": "Google credentials missing"
```
**対処法**:
- `.env.local` に `GOOGLE_SERVICE_ACCOUNT_JSON` が設定されているか確認
- Secrets Manager に正しく同期されているか確認
- サービスアカウントにファイルへのアクセス権限があるか確認

#### 2. Gemini API エラー
```
"error": "API key is missing"
```
**対処法**:
- `.env.local` に `GEMINI_API_KEY` が設定されているか確認
- APIキーが有効か確認（Google AI Studioで確認）

#### 3. Slack 通知エラー
```
"slack_notification": {"success": false, "error": "missing_scope"}
```
**対処法**:
- Slack Bot Token に `chat:write` スコープがあるか確認
- Channel ID が正しい形式（C で始まるID）か確認

#### 4. Notion 連携エラー
```
"notion_result": {"success": false, "error": "undefined method '[]' for nil:NilClass"}
```
**対処法**:
- Notion API キーが正しいか確認
- Database ID が正しいか確認
- Notion Integration がデータベースに招待されているか確認

### デバッグ用コマンド

```bash
# Secrets Manager の内容確認
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
aws --endpoint-url=http://localhost:4566 --region=ap-northeast-1 \
secretsmanager get-secret-value \
--secret-id minutes-analyzer-secrets-local \
--query SecretString --output text | jq '.'

# Lambda 関数の設定確認
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
aws --endpoint-url=http://localhost:4566 --region=ap-northeast-1 \
lambda get-function \
--function-name minutes-analyzer-local
```

## 継続的な統合テスト

### 日次テスト
```bash
# Makefile コマンドで簡単実行（今後実装予定）
cd analyzer
make integration-test
```

### CI/CD パイプラインでの実行
GitHub Actions や他のCI/CDツールで、プルリクエスト時に自動実行することを推奨します。

## 改善提案

1. **テストデータの拡充**: 様々なパターンの議事録でテスト
2. **自動化の強化**: テスト結果の自動検証スクリプトの作成
3. **パフォーマンステスト**: 大規模な議事録での処理時間測定
4. **エラーケーステスト**: 異常系のテストケース追加

## 参考資料

- [アーキテクチャ設計](architecture.md)
- [Google Drive API設定ガイド](google-drive-api-setup.md)
- [Notion API設定ガイド](notion-api-setup.md)
- [README](../README.md)
