# Google OAuth 2.0設定手順

## 概要

Google Drive APIアクセス用のOAuth 2.0認証設定ガイドです。ユーザー認証方式により、任意のGoogleアカウントでの議事録ファイルアクセスが可能になります。

## 前提条件

- Google Cloud Platformアカウント
- Google Cloudプロジェクトの作成
- API Gateway URLの取得完了（デプロイ後）

## 設定手順

### 1. Google Drive APIの有効化

1. [Google Cloud Console](https://console.cloud.google.com) にアクセス
2. 対象プロジェクトを選択
3. 「APIとサービス」→「ライブラリ」へ移動
4. 「Google Drive API」を検索・有効化

### 2. OAuth同意画面の設定

1. 「OAuth同意画面」を選択
2. ユーザータイプ：組織内のみは「内部」、一般は「外部」
3. 必須項目：
   - アプリ名: `Minutes Analyzer Drive Selector`
   - ユーザーサポートメール: 管理者のメールアドレス
   - 開発者の連絡先情報: 管理者のメールアドレス
4. スコープ追加：`https://www.googleapis.com/auth/drive.metadata.readonly`
5. 外部アプリの場合はテストユーザーを追加

### 3. OAuth 2.0クライアントIDの作成

1. 「認証情報」→「認証情報を作成」→「OAuth クライアント ID」
2. アプリケーションタイプ：「ウェブアプリケーション」
3. 名前: `Minutes Analyzer Drive Selector`
4. 承認済みリダイレクトURI：
   ```
   https://[API_GATEWAY_ID].execute-api.ap-northeast-1.amazonaws.com/production/oauth/callback
   ```
   ※ API_GATEWAY_IDはデプロイ後に `terraform output` で確認
5. 作成後、クライアントIDとシークレットを保存

### 4. 認証情報の保存

以下の情報をSecrets Managerまたは環境変数に設定：
- `GOOGLE_CLIENT_ID`: 取得したクライアントID
- `GOOGLE_CLIENT_SECRET`: 取得したクライアントシークレット

JSONファイルもダウンロード・保管を推奨。

## OAuth認証フロー

1. ユーザーがSlackで `/meeting-analyzer` コマンド実行
2. Lambda関数がユーザーの認証状態確認
3. 未認証の場合、Google認証URLをSlackに返信
4. ユーザーがGoogle同意画面で権限許可
5. 認証コードがLambdaのコールバックURLに送信
6. Lambdaがアクセストークンを取得・保存
7. 以降のDrive API呼び出しでトークンを使用

## セキュリティ設定

### トークン管理
- DynamoDBで暗号化保存
- ユーザーIDと紐付けて管理
- アクセストークンの自動更新実装

### 最小権限原則
- スコープ: `drive.metadata.readonly`のみ
- ファイル内容の読み取りは不可
- メタデータ（ファイル名、更新日時）のみアクセス

## 環境変数設定

Secrets Managerに以下を設定：

```json
{
  "GOOGLE_CLIENT_ID": "your_client_id",
  "GOOGLE_CLIENT_SECRET": "your_client_secret"
}
```

リダイレクトURIはLambda内で動的生成されます。

## トラブルシューティング

### リダイレクトURI不一致
- Google Cloud ConsoleのリダイレクトURIとAPI Gateway URLの一致を確認
- HTTPSプロトコルとパスの正確性をチェック

### スコープ未承認
- OAuth同意画面のスコープ設定確認
- 外部アプリの場合はテストユーザー登録確認

### トークン期限切れ
- リフレッシュトークンによる自動更新動作確認
- DynamoDBでのトークン保存状態確認

## 次のステップ

1. API Gatewayデプロイ完了
2. Google OAuth設定の実施
3. Slack Appの設定更新
4. OAuth認証フローのテスト
