# Slack Bot: Drive検索 external_select + OAuth/DWD（Ruby, MVP）

## 1. ゴールとスコープ

- 目的
  - Slack上でGoogle Driveファイル（主にMeet文字起こし）を検索・選択し、既存のLambdaへ起動リクエストを送る。
  - 既存Lambdaの入力形式に厳密に合わせる。

- 既存Lambdaの想定入力（Invoke時Payload）
  ```
  {
    "body": "{\"file_id\": \"<GoogleDriveFileId>\", \"file_name\": \"<FileName>\"}",
    "headers": { "Content-Type": "application/json" }
  }
  ```

- スコープ（MVP）
  - Slackアプリ（/meeting-analyzer、モーダル、external_select 検索）
  - AWS API Gateway（HTTP）→ Controller Lambda（Ruby）
  - Google Drive 検索（DWDを推奨初期設定。必要に応じてユーザーOAuthも選択可能）
  - 既存Lambdaの非同期Invoke
  - 最小限のセキュリティ（Slack署名検証、OAuth state検証）



## 2. 全体アーキテクチャ

- Slack App
  - Slashコマンド: /meeting-analyzer
  - モーダル（Block Kit）
  - external_select によるサーバサイド検索（block_suggestion）

- AWS
  - API Gateway（HTTP API, Lambdaプロキシ統合）
  - Controller Lambda（Ruby）
    - Slack署名検証、3秒ACK
    - views.open（モーダル表示）
    - block_suggestion（Drive検索）
    - view_submission（確定→既存Lambda Invoke）
  - 既存Lambda（ProcessLambda, 変更なし）

- Google
  - Drive API v3（検索・メタ取得）
  - 認可方式は2択
    - 初期推奨: DWD（ドメイン全体委任、ユーザー同意不要）
    - 代替: ユーザーOAuth（初回のみ同意、ユーザー権限で検索）

テキストフロー
1) ユーザー: /meeting-analyzer
2) Controller: モーダル表示（検索欄）
3) ユーザー: 検索語入力 → external_select発火
4) Controller: Drive検索 → 候補返却
5) ユーザー: ファイル選択 → Submit
6) Controller: ファイル名取得（または任意上書き）→ 既存Lambda Invoke
7) Slack: モーダル閉 → 簡易「処理開始」通知（任意）


## 3. Slackアプリ仕様

- 機能
  - Slashコマンド: /meeting-analyzer
  - Interactivity: ON（Request URL = /slack/interactions）
  - OAuth & Permissions → Botトークン発行

- 必要スコープ（最小）
  - commands
  - chat:write
  - users:read.email（DWDやユーザー識別にメールが必要な場合）

- モーダルUI（Block Kit）
  ```
  {
    "type": "modal",
    "callback_id": "meet_transcript_modal",
    "title": { "type": "plain_text", "text": "Meet文字起こし - ファイル選択" },
    "submit": { "type": "plain_text", "text": "実行" },
    "close": { "type": "plain_text", "text": "キャンセル" },
    "blocks": [
      {
        "type": "input",
        "block_id": "file_select_block",
        "label": { "type": "plain_text", "text": "Google Driveファイルを検索" },
        "element": {
          "type": "external_select",
          "action_id": "drive_file_select",
          "min_query_length": 1,
          "placeholder": { "type": "plain_text", "text": "会議名・日付で検索（例: 2025-08-10 定例）" }
        }
      },
      {
        "type": "input",
        "block_id": "file_name_override_block",
        "optional": true,
        "label": { "type": "plain_text", "text": "ファイル名（任意で上書き）" },
        "element": { "type": "plain_text_input", "action_id": "file_name_override" }
      }
    ]
  }
  ```

- external_select 応答
  - リクエスト: type=block_suggestion
  - レスポンス例（最大20件程度）
    ```
    { "options": [
      { "text": { "type": "plain_text", "text": "2025-08-10_定例_議事録" }, "value": "1gr4YjB-..." }
    ] }
    ```
  - value は fileId のみを格納（fileNameは後段で再取得）


## 4. Google連携（DWD / ユーザーOAuth）

- 方式A: DWD（推奨MVP）
  - サービスアカウントに「ドメイン全体の委任」を付与
  - 管理コンソールでクライアントIDにスコープ付与
    - drive.metadata.readonly
  - 検索時に sub にユーザーのGoogleメール（Slack users.info で取得）を指定しインパーソネート

- 方式B: ユーザーOAuth（将来対応）
  - MVPではスコープアウト
  - DWD方式で実装し、必要に応じて将来追加


## 5. Drive検索仕様（MVP）

- クエリ方針（Meet文字起こしを想定）
  - 条件
    - trashed=false
    - mimeType='application/vnd.google-apps.document'（Googleドキュメント）
    - name contains '<ユーザー入力>'
  - 共有ドライブ対応
    - includeItemsFromAllDrives: true
    - supportsAllDrives: true
    - corpora: "allDrives"
  - 件数・並び
    - pageSize: 20
    - orderBy: "modifiedTime desc"
  - fields 最適化
    - files(id,name,modifiedTime)

- 例
  ```
  q = "trashed=false and mimeType='application/vnd.google-apps.document' and name contains '定例'"
  ```

- ファイル名決定
  - 優先: モーダルの任意上書き
  - それ以外: files.get(fileId, fields=name)


## 6. API設計（AWS側）

- POST /slack/commands
  - Content-Type: application/x-www-form-urlencoded
  - 動作
    - Slack署名検証
    - views.open でモーダル表示
    - 200でACK（空レスポンス）

- POST /slack/interactions
  - Content-Type: application/x-www-form-urlencoded（payload=...）
  - type=block_suggestion
    - external_select 検索語に応じて Drive 検索 → options 返却
  - type=view_submission
    - 送信内容から file_id と file_name（任意上書き or Driveメタ）を確定
    - 既存Lambdaを Invoke（非同期）
    - モーダルを閉じる（response_action=clear）



## 7. 環境変数・シークレット

- SLACK_SIGNING_SECRET（Secrets Manager推奨）
- SLACK_BOT_TOKEN（Secrets Manager）
- PROCESS_LAMBDA_ARN
- USE_DWD=true/false（trueをMVPデフォルト推奨）
- GOOGLE_SERVICE_ACCOUNT_JSON（DWD時、JSON文字列）
- ALLOWED_DOMAIN（例: example.com、任意）


## 8. IAM（最小）

- Controller Lambda 実行ロール
  - 既存LambdaのInvoke
    ```
    {
      "Effect": "Allow",
      "Action": ["lambda:InvokeFunction"],
      "Resource": "arn:aws:lambda:<region>:<account>:function:<ProcessLambdaName>"
    }
    ```
  - Secrets取得（必要な場合のみ）
    ```
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:<region>:<account>:secret:<prefix>*"
    }
    ```


## 9. 実装（Ruby）スケッチ

- 目的: 最小限の全体像。実運用では例外処理・ログ整備を追加。

```ruby
# handler.rb
require "json"
require "openssl"
require "uri"
require "net/http"
require "google/apis/drive_v3"
require "googleauth"
require "aws-sdk-lambda"

SLACK_SIGNING_SECRET = ENV["SLACK_SIGNING_SECRET"]
SLACK_BOT_TOKEN      = ENV["SLACK_BOT_TOKEN"]
PROCESS_LAMBDA_ARN   = ENV["PROCESS_LAMBDA_ARN"]
USE_DWD              = ENV["USE_DWD"] == "true"
SERVICE_ACCOUNT_JSON = ENV["GOOGLE_SERVICE_ACCOUNT_JSON"]
ALLOWED_DOMAIN       = ENV["ALLOWED_DOMAIN"]

def handler(event:, context:)
  raw_body = event["body"] || ""
  path = event.dig("requestContext", "http", "path") || event["rawPath"]
  headers = (event["headers"] || {}).transform_keys(&:downcase)

  case path
  when "/slack/commands"
    verify_slack!(headers, raw_body)
    params = URI.decode_www_form(raw_body).to_h
    return open_modal(params["trigger_id"])
  when "/slack/interactions"
    verify_slack!(headers, raw_body)
    payload = JSON.parse(URI.decode_www_form(raw_body).to_h["payload"])
    case payload["type"]
    when "block_suggestion"
      return drive_options(payload)
    when "view_submission"
      return submit_and_invoke(payload)
    else
      return json(200, {})
    end
  else
    return text(404, "not found")
  end
end

def verify_slack!(headers, raw)
  ts  = headers["x-slack-request-timestamp"]
  sig = headers["x-slack-signature"]
  raise "ts" if (Time.now.to_i - ts.to_i).abs > 300
  base = "v0:#{ts}:#{raw}"
  my   = "v0=" + OpenSSL::HMAC.hexdigest("sha256", SLACK_SIGNING_SECRET, base)
  raise "sig" unless secure_compare(my, sig)
end

def open_modal(trigger_id)
  modal = {
    type: "modal",
    callback_id: "meet_transcript_modal",
    title: { type: "plain_text", text: "Meet文字起こし - ファイル選択" },
    submit: { type: "plain_text", text: "実行" },
    close:  { type: "plain_text", text: "キャンセル" },
    blocks: [
      {
        type: "input",
        block_id: "file_select_block",
        label: { type: "plain_text", text: "Google Driveファイルを検索" },
        element: {
          type: "external_select",
          action_id: "drive_file_select",
          min_query_length: 1,
          placeholder: { type: "plain_text", text: "会議名・日付で検索（例: 2025-08-10 定例）" }
        }
      },
      {
        type: "input",
        block_id: "file_name_override_block",
        optional: true,
        label: { type: "plain_text", text: "ファイル名（任意で上書き）" },
        element: { type: "plain_text_input", action_id: "file_name_override" }
      }
    ]
  }
  slack_api("views.open", { trigger_id:, view: modal })
  text(200, "") # ACK
end

def drive_options(payload)
  slack_user = payload.dig("user", "id")
  email = slack_user_email(slack_user)
  return json(200, { options: [] }) if ALLOWED_DOMAIN && !email.to_s.end_with?("@#{ALLOWED_DOMAIN}")

  query = payload["value"].to_s.strip
  files = drive_search(email:, query:, limit: 20)
  options = files.map { |f| { text: { type: "plain_text", text: "#{f[:name]}" }, value: f[:id] } }
  json(200, { options: options })
end

def submit_and_invoke(payload)
  state = payload.dig("view", "state", "values")
  file_id = state.dig("file_select_block", "drive_file_select", "selected_option", "value")
  override = state.dig("file_name_override_block", "file_name_override", "value").to_s

  email = slack_user_email(payload.dig("user", "id"))
  file_name = override.empty? ? drive_file_name(email:, file_id:) : override

  invoke_process_lambda(file_id:, file_name:)
  json(200, { response_action: "clear" })
end

def invoke_process_lambda(file_id:, file_name:)
  client = Aws::Lambda::Client.new
  payload = {
    body: { file_id:, file_name: }.to_json,
    headers: { "Content-Type" => "application/json" }
  }
  client.invoke(function_name: PROCESS_LAMBDA_ARN, invocation_type: "Event", payload: payload.to_json)
end

# Slack API
def slack_api(method, data)
  uri = URI("https://slack.com/api/#{method}")
  req = Net::HTTP::Post.new(uri)
  req["Authorization"] = "Bearer #{SLACK_BOT_TOKEN}"
  req["Content-Type"] = "application/json; charset=utf-8"
  req.body = data.to_json
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  JSON.parse(res.body)
end

def slack_user_email(user_id)
  res = slack_api("users.info", { user: user_id })
  res.dig("user", "profile", "email")
end

# Google Drive
def drive_service(email:)
  if USE_DWD
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(SERVICE_ACCOUNT_JSON),
      scope: ["https://www.googleapis.com/auth/drive.metadata.readonly"]
    )
    authorizer.sub = email
    authorizer.fetch_access_token!
    svc = Google::Apis::DriveV3::DriveService.new
    svc.authorization = authorizer
    return svc
  else
    # MVPではDWDのみサポート
    raise "DWD must be enabled for MVP"
  end
end

def drive_search(email:, query:, limit:)
  svc = drive_service(email:)
  q_parts = ["trashed=false", "mimeType='application/vnd.google-apps.document'"]
  q_parts << "name contains '#{query.gsub("'", "\\\\'")}'" unless query.empty?
  res = svc.list_files(
    q: q_parts.join(" and "),
    fields: "files(id,name,modifiedTime)",
    page_size: limit,
    order_by: "modifiedTime desc",
    include_items_from_all_drives: true,
    supports_all_drives: true,
    corpora: "allDrives"
  )
  (res.files || []).map { |f| { id: f.id, name: f.name } }
end

def drive_file_name(email:, file_id:)
  svc = drive_service(email:)
  f = svc.get_file(file_id, fields: "name", supports_all_drives: true)
  f.name
end

# Utils
def json(status, obj) = { "statusCode" => status, "headers" => { "Content-Type" => "application/json" }, "body" => obj.to_json }
def text(status, body) = { "statusCode" => status, "headers" => { "Content-Type" => "text/plain" }, "body" => body }
def secure_compare(a, b)
  return false if a.nil? || b.nil? || a.bytesize != b.bytesize
  l = a.unpack "C#{a.bytesize}"; res = 0; b.each_byte { |c| res |= c ^ l.shift }; res.zero?
end
```

- 備考（MVP方針）
  - DWDをtrueにして使用（MVPではDWDのみサポート）
  - external_selectの応答は20件上限、fieldsを最小化して応答時間を短縮
  - 3秒ACKを守るため、モーダル表示とexternal_select応答は軽量に


## 10. デプロイ手順（MVP）

1) Google（DWD方式）
- サービスアカウント作成（JSON鍵ダウンロード）
- 管理コンソール > セキュリティ > API制御 > ドメイン全体の委任
  - クライアントIDに以下スコープを付与
    - https://www.googleapis.com/auth/drive.metadata.readonly

2) Slack App
- アプリ作成 → OAuth & Permissions
  - スコープ: commands, chat:write, users:read.email
- Interactivity: ON（Request URL = https://<api-domain>/slack/interactions）
- Slashコマンド: /meeting-analyzer（Request URL = https://<api-domain>/slack/commands）
- ワークスペースにインストール → Botトークン取得

3) AWS
- API Gateway（HTTP API）を作成 → Lambda（Controller）にルーティング
- Lambda 環境変数設定
  - SLACK_SIGNING_SECRET, SLACK_BOT_TOKEN（Secrets推奨）
  - PROCESS_LAMBDA_ARN
  - USE_DWD=true
  - GOOGLE_SERVICE_ACCOUNT_JSON（シークレットの値をそのまま設定 or Secrets参照して取得する実装に変更）
  - ALLOWED_DOMAIN（任意）
- IAMポリシー（Invoke/Secrets）
- 既存Lambdaは変更不要

4) 動作確認
- /meeting-analyzer → モーダルが開く
- 検索語入力 → 候補表示
- 選択→実行 → 既存LambdaへInvokeされる
- CloudWatch Logsでpayload確認


## 11. テスト観点（MVP）

- 正常系
  - モーダル表示、検索、選択、Invoke までの一連
  - 日本語・英数字混在の検索
  - 共有ドライブ内のアイテム検索

- 例外系（簡易）
  - 署名不一致 → 401
  - 検索結果0件 → options空配列
  - ファイル名取得失敗 → file_nameを"unknown"等にフォールバック（要合意）

- 結合確認
  - 既存Lambdaで受領したPayloadが仕様通りか（ネストJSON）


## 12. セキュリティ（MVPの最小要件）

- Slack署名検証（X-Slack-Signature, X-Slack-Request-Timestamp）
- シークレットはSecrets Managerに保管（推奨）
- メールドメイン制限（ALLOWED_DOMAIN、任意）
- ログには必要最小限の情報のみ（file_idは必要な時のみ出力）


## 13. 運用メモ（MVP）

- タイムアウト
  - Lambdaハンドラ: 10秒程度（external_select応答が重くならないよう注意）
- クォータ
  - Drive APIのクォータを想定し、pageSizeを小さく
- 告知
  - 初回展開時に「/meeting-analyzer → 検索 → 実行」の使い方をガイド


## 14. 将来拡張（次フェーズ）

- ユーザーOAuth対応の実装
- 「Meet Recordings」配下だけのプリセット絞り込み
- 完了通知（スレッド/DM）


## 15. まとめ

- 本MVPは、DWD方式をデフォルトにして最小の構築で「Slack上のDrive検索→ファイル選択→既存Lambda起動」を実現する。
- 既存Lambdaのペイロード仕様を厳守し、Slackの3秒ACKと最小権限を守る。
- 将来はユーザーOAuthや通知を段階的に追加可能。
