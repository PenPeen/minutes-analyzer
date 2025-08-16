# API Gateway設定ガイド

## 概要

Drive Selector Slack Bot用のAPI Gateway設定手順です。SlackからのリクエストをLambda関数に転送し、Google Drive APIと連携します。

## アーキテクチャ

```
Slack → API Gateway → Lambda → Google Drive API
             ↓
        既存議事録分析Lambda
```

## エンドポイント構成

### 基本URL
```
https://{api-id}.execute-api.ap-northeast-1.amazonaws.com/{stage}
```

### エンドポイント一覧

| パス | メソッド | 用途 | 認証 |
|-----|---------|------|-----|
| `/health` | GET | ヘルスチェック | なし |
| `/slack/commands` | POST | Slashコマンド処理 | Slack署名検証 |
| `/slack/interactions` | POST | インタラクション処理 | Slack署名検証 |
| `/oauth/callback` | GET | Google OAuth認証コールバック | なし |

## デプロイ手順

### 1. 初期セットアップ

```bash
cd drive-selector
make setup
```

### 2. 設定ファイル準備

```bash
cd infrastructure
cp terraform.tfvars.sample terraform.tfvars
# 必要な値を設定
vi terraform.tfvars
```

### 3. デプロイ実行

```bash
make deploy
```

### 4. エンドポイントURL取得

```bash
cd infrastructure && terraform output
```

## Slack App設定

デプロイ後にSlack Appの設定を更新してください。詳細は [`slack-app-setup.md`](./slack-app-setup.md) を参照。

### 更新が必要な項目
- Slash Commands Request URL
- Interactivity Request URL and Options Load URL
- Google OAuth Redirect URI

## API Gatewayの特徴

### タイムアウト設定
- Lambda統合タイムアウト: 29秒
- Slackの要求: 3秒以内にACKレスポンス
- 対応: Lambda内で即座にACKを返し、処理は非同期実行

### ロギング・監視
- CloudWatch Logsで全リクエストを記録
- X-Rayトレーシング有効
- エラー率とレスポンス時間の監視

### セキュリティ
- Slack署名検証による認証
- セキュリティヘッダーの設定
- HTTPS必須

### パフォーマンス
- レスポンスタイム: 3秒以内（Slack要件）
- 適切なスロットリング設定

## テスト方法

### 1. ヘルスチェック

```bash
curl https://{api-id}.execute-api.ap-northeast-1.amazonaws.com/production/health
```

期待されるレスポンス：
```json
{
  "status": "healthy",
  "timestamp": "2025-01-15T10:00:00Z"
}
```

### 2. 統合テスト

```bash
make test
```

## トラブルシューティング

### 403 Forbidden エラー

**原因**: Lambda権限が不足
**解決策**:
```bash
terraform apply -target=aws_lambda_permission.api_gateway_invoke
```

### 502 Bad Gateway エラー

**原因**: Lambda関数のレスポンス形式が不正
**確認事項**:
- statusCode、headers、bodyを含むオブジェクトを返しているか
- bodyはJSON文字列化されているか

### タイムアウトエラー

**原因**: Lambda処理が29秒を超過
**解決策**:
- 処理を非同期化
- Lambda関数のタイムアウト値を確認

### CloudWatchログの確認

```bash
# API Gatewayログ
aws logs tail /aws/api-gateway/drive-selector-production --follow

# Lambdaログ
aws logs tail /aws/lambda/drive-selector-controller-production --follow
```

## API仕様

### Slackコマンドリクエスト

```
POST /slack/commands
Content-Type: application/x-www-form-urlencoded
X-Slack-Signature: v0=...

command=/meeting-analyzer&text=&user_id=U123456&team_id=T123456&trigger_id=...
```

### Slackインタラクションリクエスト

```
POST /slack/interactions
Content-Type: application/x-www-form-urlencoded
X-Slack-Signature: v0=...

payload={"type":"block_actions","user":{"id":"U123456"},...}
```

## 監視とアラート

### 重要メトリクス

- **4XXError**: クライアントエラー率
- **5XXError**: サーバーエラー率
- **Count**: API呼び出し回数
- **Latency**: レスポンス時間

### CloudWatchアラーム

エラー率とレスポンス時間の監視アラームが自動設定されます。

## 次のステップ

1. API Gatewayのデプロイ完了後、Slack App設定の更新
2. Google OAuth設定の更新
3. 動作テストの実施
4. 本番環境での監視設定確認
