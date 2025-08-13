Slack Bot Drive連携機能の統合テストを実施してください。
以下の手順でお願いします。

# 現在の進捗
Update Todos
  ⎿  ☒ Terraformによるデプロイ準備
     ☒ AWS開発環境へのデプロイ実行
     ☒ API Gateway設定の確認
     ☐ Lambda関数の動作確認
     ☐ Lambda関数のビルドエラー修正
     ☐ Google OAuth設定の確認
     ☐ Slack App設定の確認
     ☐ 疎通確認レポート作成
  ⎿  Claude usage limit reached. Your limit will reset at 1am
     (Asia/Tokyo).

# 最重要事項

Lambdaのビルド、 Terraform への展開などは、すでに ./analyzer で実装済みです。
ビルド等で詰まることがあれば、まずは参考実装がないか確認するようにしてください。

# 対象ディレクトリ

drive-selector

# 環境変数の取得

analyzer を同様に、以下のフローで認証情報をセットする

.env.local => Terraform => Secrets Manager

詳細は ./analyzer を確認してください。

# デプロイ作業等

drive-selector/Makefile を利用するようにしてください。
必要に応じてコマンドを追加してください。

また、実装方針については、既存の analyzer/Makefile　を参考にしてください。

# 作業手順

1. **Terraformによるデプロイ**

   * drive-selector配下のインフラ定義に基づき、AWS開発環境へデプロイしてください。

2. **コンソール上での疎通確認**

   * API Gateway、Lambda、Google OAuth、Slack App設定が正しく動作しているか、AWSマネジメントコンソールやSlackアプリの管理画面で確認してください。

3. **最終検証**

   * 疎通確認がすべて取れたら、私がSlackから最終的な動作検証を行います。

4. **不具合対応**

   * テスト中に不具合が発生した場合は、その場で修正を行い、再テスト後に解消報告をしてください。

# 注意点

参照情報やタスク構造、アーキテクチャは `tasks.md` および `architecture.md` に記載されています。
特に `drive-selector` ディレクトリ内の構成とTerraformの設定を確認しながら進めてください。
