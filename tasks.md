# 議事録作成Bot 実装タスク計画

## 概要
- 目的: Notion議事録データベースのタイトルに日付を含めて定例会議を見分けやすくする
- 成功基準: 議事録タイトルが「YYYY-MM-DD タイトル」形式で保存される
- スコープ: NotionPageBuilder/タイトル生成ロジック/テスト更新
- 非スコープ: 時刻の追加、既存議事録の更新、他のデータベースフィールドの変更

## タスク一覧
- T-01: 日付フォーマット付きタイトル生成ロジックの実装
  - 概要: NotionPageBuilderのタイトル生成部分を修正し、日付をタイトルの先頭に追加
  - 受け入れ条件:
    - meeting_summaryから日付を取得してタイトルに付与
    - 日付がない場合は現在日付を使用
    - フォーマットは「YYYY-MM-DD タイトル」形式
  - 依存関係: なし
  - ブランチ: feature/notion-title-with-date

- T-02: 単体テストの更新
  - 概要: NotionPageBuilderのテストを更新し、新しいタイトル形式を検証
  - 受け入れ条件:
    - 日付付きタイトルの生成を検証するテストケースが追加
    - 日付がない場合の現在日付使用を検証
    - 既存テストが全てパス
  - 依存関係: T-01
  - ブランチ: test/notion-title-format-specs

- T-03: 統合テストでの動作確認
  - 概要: LocalStack環境で実際のLambda関数を実行し、Notion連携の動作を確認
  - 受け入れ条件:
    - テスト用議事録データで日付付きタイトルが正しく生成される
    - Notion APIへの実際のリクエストで問題がない
    - エラーログが出力されない
  - 依存関係: T-02
  - ブランチ: test/integration-title-verification

## ブランチ計画
- ベースブランチ: test/fix-after-refactoring
- ブランチ命名規則: type/scope-short-desc（kebab-case, 英小文字）
- タスクとブランチ対応:
  - T-01 -> feature/notion-title-with-date
  - T-02 -> test/notion-title-format-specs
  - T-03 -> test/integration-title-verification

## 付記
- 環境変数/シークレット: .env.local => Terraform => Secrets Manager