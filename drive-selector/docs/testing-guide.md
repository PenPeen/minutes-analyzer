# テストガイド

## 概要

Drive Selector Slack Botの包括的なテスト戦略と実行方法について説明します。

## テストレベル

### 1. 単体テスト（Unit Tests）

個々のクラスやメソッドの動作を検証します。

```bash
# 全単体テスト実行
make test

# 特定のファイルのみ実行
cd lambda
bundle exec rspec spec/lib/slack_verifier_spec.rb
```

### 2. 統合テスト（Integration Tests）

複数のコンポーネント間の連携を検証します。

```bash
# 統合テスト実行
make test-integration

# カバレッジ付き実行
make test-coverage
```

### 3. E2Eテスト（End-to-End Tests）

実際のAWS環境でシステム全体の動作を検証します。

```bash
# 環境変数設定
export API_GATEWAY_URL=https://xxx.execute-api.region.amazonaws.com/stage
export SLACK_SIGNING_SECRET=your-secret
export FUNCTION_NAME=drive-selector-controller-development

# E2Eテスト実行
make test-e2e
```

## テストカバレッジ

現在のテストカバレッジ目標：

| コンポーネント | 目標 | 現状 |
|--------------|------|------|
| Handler | 90% | 85% |
| Slack関連 | 85% | 80% |
| Google Drive | 80% | 75% |
| Lambda Invoker | 85% | 82% |

## テストシナリオ

### 基本フロー

1. **Slashコマンド受信**
   - 署名検証成功
   - モーダル表示
   - エラーハンドリング

2. **Google Drive検索**
   - 認証済みユーザー
   - 未認証ユーザー
   - 検索結果あり/なし

3. **ファイル選択**
   - 正常な選択
   - タイムアウト処理
   - Lambda呼び出し

### エラーケース

1. **認証エラー**
   - 無効な署名
   - 期限切れトークン
   - 権限不足

2. **APIエラー**
   - Google Drive API制限
   - Slack API制限
   - AWS APIエラー

3. **システムエラー**
   - Lambda関数エラー
   - DynamoDBエラー
   - ネットワークエラー

## ローカルテスト環境

### 環境構築

```bash
# 依存関係インストール
cd lambda
bundle install

# LocalStack起動（オプション）
docker-compose up -d localstack
```

### モックサーバー

```ruby
# spec/support/mock_servers.rb
require 'webmock/rspec'

RSpec.configure do |config|
  config.before(:each) do
    # Slack APIモック
    stub_request(:post, /slack.com/)
      .to_return(status: 200, body: '{"ok": true}')
    
    # Google Drive APIモック
    stub_request(:get, /googleapis.com/)
      .to_return(status: 200, body: '{"files": []}')
  end
end
```

## CI/CDパイプライン

### GitHub Actions設定

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: 3.2
        bundler-cache: true
    
    - name: Run tests
      run: |
        cd lambda
        bundle exec rspec
    
    - name: Upload coverage
      uses: codecov/codecov-action@v2
      with:
        file: ./lambda/coverage/.resultset.json
```

## テストデータ

### サンプルペイロード

```json
// Slackコマンド
{
  "command": "/meet-transcript",
  "user_id": "U123456",
  "team_id": "T123456",
  "trigger_id": "123.456.789"
}

// Slackインタラクション
{
  "type": "view_submission",
  "view": {
    "state": {
      "values": {
        "file_select_block": {
          "file_select": {
            "selected_option": {
              "value": "file_id_123",
              "text": {"text": "議事録.txt"}
            }
          }
        }
      }
    }
  }
}
```

## パフォーマンステスト

### 負荷テスト

```bash
# Apache Benchを使用
ab -n 1000 -c 10 -H "Content-Type: application/json" \
   https://api.example.com/health

# 結果の評価基準
# - 平均レスポンス時間: < 500ms
# - 95パーセンタイル: < 1000ms
# - エラー率: < 1%
```

### メモリ使用量測定

```ruby
# spec/performance/memory_spec.rb
require 'memory_profiler'

RSpec.describe 'Memory Usage' do
  it 'uses less than 50MB for processing' do
    report = MemoryProfiler.report do
      # テスト対象の処理
    end
    
    expect(report.total_allocated_memsize).to be < 50_000_000
  end
end
```

## セキュリティテスト

### 脆弱性スキャン

```bash
# 依存関係の脆弱性チェック
bundle audit check

# 静的解析
bundle exec brakeman
```

### ペネトレーションテスト項目

1. **インジェクション攻撃**
   - SQLインジェクション（N/A - NoSQL使用）
   - コマンドインジェクション
   - XSS

2. **認証・認可**
   - 署名偽装
   - トークン盗用
   - 権限昇格

3. **データ保護**
   - 暗号化確認
   - 機密情報漏洩

## デバッグ方法

### ログ確認

```bash
# CloudWatchログ確認
make logs ENVIRONMENT=development

# 特定のエラーを検索
aws logs filter-log-events \
  --log-group-name /aws/lambda/drive-selector-controller-development \
  --filter-pattern "ERROR"
```

### ローカルデバッグ

```ruby
# byebugを使用
require 'byebug'

def some_method
  byebug  # ブレークポイント
  # 処理
end
```

### リモートデバッグ

```bash
# X-Rayトレース有効化
aws lambda update-function-configuration \
  --function-name drive-selector-controller-development \
  --tracing-config Mode=Active
```

## トラブルシューティング

### よくある問題

1. **テストが失敗する**
   ```bash
   # 依存関係をクリア
   rm -rf lambda/vendor
   bundle install
   ```

2. **モックが動作しない**
   ```ruby
   # WebMockを明示的に有効化
   WebMock.enable!
   ```

3. **タイムアウトエラー**
   ```ruby
   # タイムアウト値を増やす
   RSpec.configure do |config|
     config.default_timeout = 10
   end
   ```

## ベストプラクティス

### テスト作成のガイドライン

1. **AAA パターン**
   - Arrange: テストデータ準備
   - Act: 実行
   - Assert: 検証

2. **テストの独立性**
   - 各テストは独立して実行可能
   - 順序依存なし
   - 共有状態なし

3. **明確な命名**
   ```ruby
   describe '#method_name' do
     context 'when condition' do
       it 'returns expected result' do
         # テスト
       end
     end
   end
   ```

4. **モックの適切な使用**
   - 外部サービスは必ずモック
   - 内部ロジックは実装をテスト

## チェックリスト

### PRマージ前チェック

- [ ] 全テストがパス
- [ ] カバレッジ80%以上
- [ ] Lintエラーなし
- [ ] セキュリティチェックパス
- [ ] ドキュメント更新

### リリース前チェック

- [ ] E2Eテスト成功
- [ ] パフォーマンステスト基準クリア
- [ ] セキュリティテスト完了
- [ ] ステージング環境で動作確認
- [ ] ロールバック計画準備

## まとめ

包括的なテスト戦略により、高品質で信頼性の高いシステムを維持します。定期的にテストを実行し、カバレッジを監視してください。