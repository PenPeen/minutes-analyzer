# Google Drive API 設定手順

このドキュメントでは、議事録分析システムでGoogle Drive APIを使用するための設定手順を説明します。

## 概要

本システムでは、Google Meetで生成された議事録ファイルをGoogle Drive APIで読み取るため、サービスアカウントを使用します。<br>

IAMを活用することで、個別のフォルダ共有は不要になり、組織全体での権限管理が可能になります。

## 設定手順

### 1. Google Cloud Consoleでプロジェクトを作成

1. [Google Cloud Console](https://console.cloud.google.com)にアクセス
2. 新しいプロジェクトを作成（または既存のプロジェクトを選択）
3. プロジェクトIDをメモしておく

### 2. Google Drive APIを有効化

1. 左メニューから「APIとサービス」→「ライブラリ」を選択
2. 検索バーで「Google Drive API」を検索
3. 「Google Drive API」をクリック
4. 「有効にする」ボタンをクリック

### 3. サービスアカウントを作成

1. 左メニューから「APIとサービス」→「認証情報」を選択
2. 上部の「認証情報を作成」→「サービスアカウント」を選択
3. サービスアカウントの詳細を入力：
   - **サービスアカウント名**: `minutes-analyzer`（任意）
   - **サービスアカウントID**: 自動生成されるものでOK
   - **説明**: 議事録ファイル読み取り用（任意）
4. 「作成して続行」をクリック
5. **重要**: ロールの選択画面はスキップ（後でIAMで設定）
6. 「完了」をクリック

### 4. サービスアカウントキー（JSON）を作成

1. 作成したサービスアカウントの名前をクリック
2. 上部の「キー」タブを選択
3. 「鍵を追加」→「新しい鍵を作成」をクリック
4. キーのタイプで「JSON」を選択
5. 「作成」をクリック
6. JSONファイルが自動的にダウンロードされる（安全に保管）

### 5. IAMでサービスアカウントに権限を付与

1. サービスアカウントの詳細ページで「権限」タブを選択
2. 「アクセスを許可」をクリック
3. 新しいプリンシパルとして、議事録ファイルの所有者またはドメイン管理者のメールアドレスを入力
4. ロールとして以下のいずれかを選択：
   - **Storage オブジェクト閲覧者**
5. 「保存」をクリック

### 6. サービスアカウントキーのBASE64エンコード

ダウンロードしたJSONファイルを環境変数で使用するため、BASE64エンコードします：

```bash
# Linux/Unix
cat ~/Downloads/your-service-account-key.json | base64

# macOS（改行なしで出力）
cat ~/Downloads/your-service-account-key.json | base64 -b 0

# Windows (PowerShell)
[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content ~/Downloads/your-service-account-key.json -Raw)))
```

### 7. 環境変数に設定

1. プロジェクトルートの`.env.local`ファイルを編集
2. 以下の行を見つけて、BASE64エンコードした文字列を設定：
   ```
   GOOGLE_SERVICE_ACCOUNT_JSON_BASE64=<ここに長いBASE64文字列を貼り付け>
   ```

## セキュリティのベストプラクティス

1. **最小権限の原則**: サービスアカウントには必要最小限の権限のみを付与
2. **キーのローテーション**: 定期的にサービスアカウントキーを更新
3. **監査ログ**: Cloud Auditログで不正なアクセスを監視
4. **キーの保護**: JSONキーファイルは安全に保管し、Gitにコミットしない

## トラブルシューティング

### 「権限がありません」エラーが発生する場合

1. サービスアカウントのメールアドレスが正しいか確認
2. IAMで適切なロールが付与されているか確認
3. 権限の伝播に最大7分かかる場合があるため、少し待つ

### ファイルが見つからない場合

1. ファイルIDが正しいか確認
2. サービスアカウントがファイルの存在するプロジェクトにアクセス権を持っているか確認

### 認証エラーが発生する場合

1. JSONキーが正しくBASE64エンコードされているか確認
2. 環境変数が正しく設定されているか確認
3. サービスアカウントが有効か確認

## 参考リンク

- [Google Cloud IAM ドキュメント](https://cloud.google.com/iam/docs)
- [Google Drive API ドキュメント](https://developers.google.com/drive/api/v3/about-sdk)
- [サービスアカウントのベストプラクティス](https://cloud.google.com/iam/docs/best-practices-for-using-service-accounts)
