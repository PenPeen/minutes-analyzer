# Google Meet議事録 自動ユーザー紐付けシステム 実装タスクリスト

## 前提・背景
- **重要**: Google Meetの録画ファイルは自動的にCalendar eventのattachmentsフィールドに追加される
- この仕組みを活用することで、定例会議でも確実に会議を特定可能
- GAS（Google Apps Script）から録画ファイルIDを受け取り、Lambda関数で処理する設計
- 実装言語: Ruby（既存のLambda関数に統合）

## 1. Google Calendar API連携基盤

### 1.1 Calendar APIクライアント実装
- [ ] `lambda/lib/google_calendar_client.rb`を新規作成
- [ ] Google Calendar API認証処理を実装（サービスアカウント認証）
- [ ] 必要なスコープ設定（`https://www.googleapis.com/auth/calendar.readonly`）
- [ ] Gemfileにgoogle-api-clientの依存関係を追加

### 1.2 録画ファイルからCalendar Event特定機能
- [ ] `find_meeting_by_recording_file`メソッドの実装
- [ ] ファイルIDからGoogle Driveのファイル情報取得処理を実装（createdTime取得）
- [ ] ファイル作成時刻の前後24時間のイベント検索機能を実装
- [ ] **重要**: attachmentsフィールドからファイルIDで一致するイベントを特定する処理を実装
- [ ] attachments[].fileIdでの直接照合処理を実装（最も確実な方法）
- [ ] attachments[].fileUrlでのパターンマッチング処理を実装（フォールバック）
- [ ] フォールバック処理（時刻とタイトルでの照合）を実装
- [ ] 定例会議でも一意に特定可能なロジックの実装

### 1.3 Calendar Event参加者情報取得
- [ ] イベントから参加者リスト（attendees）を取得する処理を実装
- [ ] リソース（会議室等）を除外するフィルタリング処理を実装
- [ ] メールアドレスのリストを返す処理を実装

## 2. Slack API拡張機能

### 2.1 SlackユーザールックアップAPI実装
- [ ] `lambda/lib/slack_user_manager.rb`を新規作成
- [ ] Slack Web APIクライアントの初期化処理を実装
- [ ] users.lookupByEmail APIメソッドを実装
- [ ] OAuth Bot Tokenを使用した認証設定（users:read, users:read.emailスコープ）

### 2.2 レート制限対応
- [ ] RateLimiterクラスの実装（最大50リクエスト/分）
- [ ] rate_limited エラーのハンドリングとリトライ処理を実装
- [ ] Retry-Afterヘッダーに基づく待機処理を実装

### 2.3 ユーザーID取得・メンション生成
- [ ] メールアドレスからSlackユーザーIDを取得する処理を実装
- [ ] メンション形式（`<@USER_ID>`）の生成処理を実装
- [ ] ユーザーが見つからない場合のエラーハンドリングを実装

## 3. Notion API拡張機能

### 3.1 Notionユーザー管理機能
- [ ] `lambda/lib/notion_user_manager.rb`を新規作成
- [ ] users.list APIを使用した全ユーザー取得処理を実装
- [ ] ページネーション対応（100件ずつ取得）を実装
- [ ] メールアドレスでインデックス化したキャッシュ構造を実装

### 3.2 キャッシング機能
- [ ] ユーザー情報のメモリキャッシュ実装（TTL: 10分）
- [ ] キャッシュの有効期限チェック処理を実装
- [ ] キャッシュリフレッシュ処理を実装

### 3.3 タスクDB担当者更新機能
- [ ] メールアドレスからNotionユーザーIDを検索する処理を実装
- [ ] タスクページの担当者（people）プロパティ更新処理を実装
- [ ] バッチ更新処理の実装（複数タスクの一括更新）

## 4. Lambda統合処理

### 4.1 メイン処理クラス実装
- [ ] `lambda/lib/meeting_transcript_processor.rb`を新規作成
- [ ] Google Calendar、Notion、Slackの各クライアントを統合する処理を実装
- [ ] ファイルIDから会議を特定する処理を実装
- [ ] 参加者メールアドレスの取得処理を実装

### 4.2 並列処理実装（Ruby）
- [ ] Concurrent-ruby gemの追加（Gemfile更新）
- [ ] 複数参加者の並列マッピング処理を実装（Concurrent::Promise使用）
- [ ] Notion/Slack API呼び出しの並列実行を実装
- [ ] ThreadPoolExecutorの設定（最大スレッド数の調整）
- [ ] エラーハンドリングと部分的失敗の許容処理を実装

### 4.3 統計情報生成
- [ ] マッピング成功/失敗の統計情報を生成する処理を実装
- [ ] 処理時間の計測とログ出力を実装
- [ ] CloudWatchメトリクス送信処理を実装

## 5. 環境設定・インフラ

### 5.1 Secrets Manager設定
- [ ] Google Calendar API用のサービスアカウントJSON追加
- [ ] Slack Bot Token追加（OAuth Token）
- [ ] **重要**: Notion API権限レベルの更新（User Information With Email Addresses - 最高権限レベル必須）
- [ ] Notion APIトークンの再発行（権限レベル変更後）
- [ ] Terraformでのシークレット定義更新

### 5.2 IAMロール・権限設定
- [ ] Lambda実行ロールにSecrets Manager読み取り権限を追加
- [ ] CloudWatch Logs書き込み権限の確認
- [ ] Google APIアクセス用のサービスアカウント権限設定

### 5.3 Lambda環境変数設定
- [ ] GOOGLE_CALENDAR_ENABLED フラグ追加
- [ ] USER_MAPPING_ENABLED フラグ追加
- [ ] CACHE_TTL設定（デフォルト: 600秒）

## 6. テスト実装

### 6.1 単体テスト
- [ ] `spec/google_calendar_client_spec.rb`の作成
- [ ] `spec/slack_user_manager_spec.rb`の作成
- [ ] `spec/notion_user_manager_spec.rb`の作成
- [ ] `spec/meeting_transcript_processor_spec.rb`の作成

### 6.2 結合テスト
- [ ] 録画ファイルID→Calendar Event特定のE2Eテスト作成
- [ ] メールアドレス→Slack/Notionユーザー紐付けのE2Eテスト作成
- [ ] エラーケースのテスト（ユーザー未発見、API障害等）

### 6.3 テストデータ準備
- [ ] サンプル録画ファイルIDの準備
- [ ] テスト用Calendarイベントの作成
- [ ] モックレスポンスデータの作成

## 7. モニタリング・ログ

### 7.1 CloudWatchログ設定
- [ ] 各API呼び出しの詳細ログ出力実装
- [ ] エラーログの構造化（JSON形式）
- [ ] ログレベル設定（DEBUG/INFO/WARN/ERROR）

### 7.2 メトリクス設定
- [ ] API呼び出し回数のメトリクス送信
- [ ] 処理時間のメトリクス送信
- [ ] 成功率のメトリクス送信

### 7.3 アラート設定
- [ ] エラー率閾値超過時のアラート設定
- [ ] API Rate Limit到達時のアラート設定
- [ ] 処理遅延時のアラート設定

### 7.4 Dead Letter Queue設定
- [ ] SQS Dead Letter Queueの設定
- [ ] 失敗したリクエストの自動リトライ設定
- [ ] 最大リトライ回数の設定（3回推奨）

## 8. ドキュメント

### 8.1 技術ドキュメント
- [ ] API認証設定手順書の作成
- [ ] トラブルシューティングガイドの作成
- [ ] アーキテクチャ図の更新

### 8.2 運用ドキュメント
- [ ] デプロイ手順書の作成
- [ ] 監視ダッシュボード設定手順の作成
- [ ] インシデント対応手順書の作成

## 9. デプロイ・リリース

### 9.1 開発環境デプロイ
- [ ] ローカル環境での動作確認
- [ ] 開発環境へのデプロイ（make deploy-local）
- [ ] 開発環境での結合テスト実施

### 9.2 本番環境デプロイ
- [ ] 本番環境用のTerraform設定更新
- [ ] 本番環境へのデプロイ（make deploy-production）
- [ ] 本番環境での動作確認
