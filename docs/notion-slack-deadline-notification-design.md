# NotionからSlackへの期限通知システム設計書

## 📋 概要

本設計書は、Notionに登録されたタスクの期限情報を定期的に監視し、期限当日または期限切れのタスクをSlackに自動通知するシステムの実装方針をまとめたものです。

### システム要件
- **機能要件**: 毎日決まった時刻にNotionから本日期限のタスクを抽出し、Slackに通知
- **非機能要件**: 高可用性、コスト効率、保守性、拡張性
- **制約**: 既存の議事録分析システムとの統合、AWS環境での運用

## 🎯 実装アプローチ比較

### 1️⃣ Notion-Slack直接連携（理想案）

#### 概要
Notion公式のSlack連携機能とAutomationを使用した最もシンプルなアプローチです。

#### アーキテクチャ
```
Notion Database → Notion Automation → Slack Webhook
```

#### 実装方法
1. **Notion Automation設定**
   - トリガー: データベースプロパティの変更（期限フィールド）
   - 条件: 期限が本日または過去
   - アクション: Slack Webhook送信

2. **Slack Webhook設定**
   - Incoming Webhookを作成
   - 通知先チャンネルを指定

#### メリット
- ✅ **実装コスト最小**: ノーコードで実装可能
- ✅ **運用コスト最小**: AWS不要、月額$0
- ✅ **レスポンス高速**: リアルタイム通知
- ✅ **保守性高**: Notion/Slack公式機能のため安定

#### デメリット
- ❌ **機能制限**: 複雑な通知ロジックは実装困難
- ❌ **Notion Pro必須**: Automation機能は有料プランでのみ利用可能
- ❌ **時刻指定不可**: 毎日決まった時刻の実行は困難
- ❌ **通知形式固定**: リッチなSlackメッセージ形式は制限あり

#### 推定コスト
- Notion Pro: $10/月/ユーザー
- Slack: 既存契約
- **合計**: $10-50/月（ユーザー数による）

### 2️⃣ AWS Lambda定期実行（推奨案）

#### 概要
AWS LambdaとEventBridge（CloudWatch Events）を使用した定期実行システムです。既存の議事録分析システムのインフラを活用できます。

#### アーキテクチャ
```
EventBridge (Cron) → Lambda Function → Notion API → Slack API
                            ↓
                      CloudWatch Logs
```

#### 実装方法

##### Lambda関数の構成
```ruby
# lambda/deadline_notifier.rb
require_relative 'lib/notion_task_checker'
require_relative 'lib/slack_deadline_notifier'

def lambda_handler(event:, context:)
  logger = Logger.new(STDOUT)
  
  # 環境変数から設定を取得
  notion_api_key = ENV['NOTION_API_KEY']
  notion_task_db_id = ENV['NOTION_TASK_DATABASE_ID']
  slack_bot_token = ENV['SLACK_BOT_TOKEN']
  slack_channel_id = ENV['SLACK_CHANNEL_ID']
  
  # Notionからタスクを取得
  task_checker = NotionTaskChecker.new(notion_api_key, notion_task_db_id, logger)
  due_tasks = task_checker.get_tasks_due_today
  overdue_tasks = task_checker.get_overdue_tasks
  
  # Slackに通知
  notifier = SlackDeadlineNotifier.new(slack_bot_token, slack_channel_id, logger)
  result = notifier.send_deadline_notification(due_tasks, overdue_tasks)
  
  {
    statusCode: 200,
    body: {
      message: "Notification sent successfully",
      due_tasks_count: due_tasks.length,
      overdue_tasks_count: overdue_tasks.length,
      success: result[:success]
    }.to_json
  }
rescue => e
  logger.error("Error in deadline notification: #{e.message}")
  {
    statusCode: 500,
    body: { error: e.message }.to_json
  }
end
```

##### NotionTaskChecker実装
```ruby
# lib/notion_task_checker.rb
class NotionTaskChecker
  def initialize(api_key, database_id, logger)
    @api_key = api_key
    @database_id = database_id
    @logger = logger
  end
  
  def get_tasks_due_today
    today = Date.today.to_s
    query_notion_tasks({
      filter: {
        and: [
          { property: "期限", date: { equals: today } },
          { property: "ステータス", select: { does_not_equal: "完了" } }
        ]
      }
    })
  end
  
  def get_overdue_tasks
    today = Date.today.to_s
    query_notion_tasks({
      filter: {
        and: [
          { property: "期限", date: { before: today } },
          { property: "ステータス", select: { does_not_equal: "完了" } }
        ]
      }
    })
  end
  
  private
  
  def query_notion_tasks(query_params)
    # Notion API実装
    uri = URI("https://api.notion.com/v1/databases/#{@database_id}/query")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Notion-Version'] = '2022-06-28'
    request['Content-Type'] = 'application/json'
    request.body = query_params.to_json
    
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
    
    if response.code == '200'
      JSON.parse(response.body)['results']
    else
      @logger.error("Failed to query Notion: #{response.body}")
      []
    end
  end
end
```

##### SlackDeadlineNotifier実装
```ruby
# lib/slack_deadline_notifier.rb
class SlackDeadlineNotifier
  def initialize(bot_token, channel_id, logger)
    @bot_token = bot_token
    @channel_id = channel_id
    @logger = logger
  end
  
  def send_deadline_notification(due_tasks, overdue_tasks)
    return { success: true, message: "No tasks to notify" } if due_tasks.empty? && overdue_tasks.empty?
    
    blocks = build_notification_blocks(due_tasks, overdue_tasks)
    send_slack_message(blocks)
  end
  
  private
  
  def build_notification_blocks(due_tasks, overdue_tasks)
    blocks = []
    
    # ヘッダー
    blocks << {
      type: "header",
      text: {
        type: "plain_text",
        text: "📅 タスク期限通知",
        emoji: true
      }
    }
    
    # 本日期限のタスク
    if due_tasks.any?
      blocks << {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*📋 本日期限のタスク (#{due_tasks.length}件)*"
        }
      }
      
      due_tasks.each do |task|
        blocks << build_task_block(task, "🟡")
      end
    end
    
    # 期限切れタスク
    if overdue_tasks.any?
      blocks << {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*🚨 期限切れタスク (#{overdue_tasks.length}件)*"
        }
      }
      
      overdue_tasks.each do |task|
        blocks << build_task_block(task, "🔴")
      end
    end
    
    # フッター
    blocks << {
      type: "context",
      elements: [
        {
          type: "mrkdwn",
          text: "📝 <https://www.notion.so/#{@task_database_id.gsub('-', '')}|タスク一覧を確認>"
        }
      ]
    }
    
    blocks
  end
  
  def build_task_block(task, priority_emoji)
    properties = task['properties']
    title = properties['タスク名']['title'][0]['text']['content'] rescue "無題のタスク"
    assignee = properties['担当者']['rich_text'][0]['text']['content'] rescue "未定"
    deadline = properties['期限']['date']['start'] rescue "期限未設定"
    
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "#{priority_emoji} *#{title}*\n担当者: #{assignee} | 期限: #{deadline}"
      },
      accessory: {
        type: "button",
        text: {
          type: "plain_text",
          text: "詳細を見る",
          emoji: true
        },
        url: task['url']
      }
    }
  end
  
  def send_slack_message(blocks)
    uri = URI('https://slack.com/api/chat.postMessage')
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@bot_token}"
    request['Content-Type'] = 'application/json'
    
    payload = {
      channel: @channel_id,
      blocks: blocks,
      text: "タスク期限通知"
    }
    request.body = payload.to_json
    
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
    
    if response.code == '200'
      result = JSON.parse(response.body)
      if result['ok']
        @logger.info("Successfully sent deadline notification")
        { success: true }
      else
        @logger.error("Slack API error: #{result['error']}")
        { success: false, error: result['error'] }
      end
    else
      @logger.error("HTTP error: #{response.code} #{response.message}")
      { success: false, error: "HTTP #{response.code}" }
    end
  end
end
```

##### EventBridge設定（Terraform）
```hcl
# infrastructure/deadline_notification.tf
resource "aws_cloudwatch_event_rule" "deadline_notification" {
  name                = "notion-deadline-notification"
  description         = "Trigger deadline notification Lambda daily at 9:00 AM JST"
  schedule_expression = "cron(0 0 * * ? *)"  # 毎日9:00 AM JST (UTC 0:00)
}

resource "aws_cloudwatch_event_target" "deadline_notification_target" {
  rule      = aws_cloudwatch_event_rule.deadline_notification.name
  target_id = "DeadlineNotificationLambdaTarget"
  arn       = aws_lambda_function.deadline_notifier.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.deadline_notifier.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.deadline_notification.arn
}

resource "aws_lambda_function" "deadline_notifier" {
  filename         = "deadline_notifier.zip"
  function_name    = "notion-deadline-notifier"
  role            = aws_iam_role.deadline_notifier_role.arn
  handler         = "deadline_notifier.lambda_handler"
  runtime         = "ruby3.2"
  timeout         = 30
  
  environment {
    variables = {
      NOTION_API_KEY         = var.notion_api_key
      NOTION_TASK_DATABASE_ID = var.notion_task_database_id
      SLACK_BOT_TOKEN        = var.slack_bot_token
      SLACK_CHANNEL_ID       = var.slack_channel_id
    }
  }
}
```

#### メリット
- ✅ **柔軟な通知ロジック**: 複雑な条件分岐やフィルタリングが可能
- ✅ **リッチな通知**: Slackブロックを使った視覚的な通知
- ✅ **時刻指定**: 毎日決まった時刻の実行が可能
- ✅ **既存インフラ活用**: 議事録分析システムと同じAWS環境
- ✅ **拡張性**: 機能追加やカスタマイズが容易

#### デメリット
- ❌ **実装コスト**: 開発・テスト工数が必要
- ❌ **運用コスト**: AWS利用料金が発生
- ❌ **保守性**: 自前システムのため保守が必要

#### 推定コスト
- Lambda実行: $0.01/月（月30回実行想定）
- CloudWatch Logs: $0.50/月
- EventBridge: $0.01/月
- **合計**: $1/月未満

### 3️⃣ GitHub Actions定期実行

#### 概要
GitHub Actionsのcron機能を使用して定期実行するアプローチです。

#### アーキテクチャ
```
GitHub Actions (Cron) → Ruby Script → Notion API → Slack API
```

#### 実装方法
```yaml
# .github/workflows/deadline-notification.yml
name: Notion Deadline Notification

on:
  schedule:
    - cron: '0 0 * * *'  # 毎日9:00 AM JST (UTC 0:00)
  workflow_dispatch:  # 手動実行も可能

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
          
      - name: Run deadline notification
        run: ruby scripts/deadline_notifier.rb
        env:
          NOTION_API_KEY: ${{ secrets.NOTION_API_KEY }}
          NOTION_TASK_DATABASE_ID: ${{ secrets.NOTION_TASK_DATABASE_ID }}
          SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
          SLACK_CHANNEL_ID: ${{ secrets.SLACK_CHANNEL_ID }}
```

#### メリット
- ✅ **コスト最小**: GitHub Actions無料枠内で実行可能
- ✅ **管理容易**: GitHubで一元管理
- ✅ **デバッグ容易**: ログが見やすい

#### デメリット
- ❌ **実行時間制限**: 6時間の制限あり
- ❌ **信頼性**: GitHub Actionsの可用性に依存
- ❌ **時差問題**: UTC基準のため時刻調整が必要

#### 推定コスト
- GitHub Actions: $0/月（無料枠内）
- **合計**: $0/月

### 4️⃣ Zapier/Make.com連携

#### 概要
ノーコード/ローコード自動化ツールを使用するアプローチです。

#### アーキテクチャ
```
Schedule → Zapier/Make → Notion API → Slack API
```

#### メリット
- ✅ **実装速度**: GUIで素早く構築可能
- ✅ **保守性**: UI操作で設定変更可能

#### デメリット
- ❌ **月額費用**: $20-50/月程度
- ❌ **機能制限**: 複雑なロジックは困難
- ❌ **ベンダーロックイン**: プラットフォーム依存

## 🏗️ 推奨実装プラン

### 段階的実装アプローチ

#### Phase 1: MVP実装（AWS Lambda）
期間: 2-3日
- 基本的なタスク期限通知機能
- 本日期限・期限切れタスクの検出
- シンプルなSlack通知

#### Phase 2: 機能拡張
期間: 2-3日
- リッチなSlack通知（ブロック形式）
- 通知条件のカスタマイズ
- エラーハンドリング強化

#### Phase 3: 運用最適化
期間: 1-2日
- 監視・アラート設定
- ドキュメント整備
- テストケース拡充

### ディレクトリ構造
```
analyzer/
├── lambda/
│   ├── deadline_notifier.rb          # メインハンドラー
│   └── lib/
│       ├── notion_task_checker.rb    # Notionタスク取得
│       └── slack_deadline_notifier.rb # Slack通知
├── infrastructure/
│   └── deadline_notification.tf      # Terraform設定
└── spec/
    ├── deadline_notifier_spec.rb     # テスト
    └── lib/
        ├── notion_task_checker_spec.rb
        └── slack_deadline_notifier_spec.rb
```

## 📊 実装詳細仕様

### Notion API仕様

#### データベース構造要件
```
タスクデータベース必須プロパティ:
- タスク名 (Title)
- 期限 (Date)
- ステータス (Select: 未着手, 進行中, 完了)
- 担当者 (Rich Text or Person)
```

#### APIクエリ例
```json
{
  "filter": {
    "and": [
      {
        "property": "期限",
        "date": {
          "equals": "2024-01-15"
        }
      },
      {
        "property": "ステータス",
        "select": {
          "does_not_equal": "完了"
        }
      }
    ]
  },
  "sorts": [
    {
      "property": "優先度",
      "direction": "ascending"
    }
  ]
}
```

### Slack通知仕様

#### 通知タイミング
- **本日期限**: 毎日9:00 AM JST
- **期限切れ**: 毎日9:00 AM JST（まとめて通知）

#### 通知形式
```json
{
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "📅 タスク期限通知"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*📋 本日期限のタスク (2件)*"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "🟡 *セキュリティテストの完了*\n担当者: 田中さん | 期限: 2024-01-15"
      },
      "accessory": {
        "type": "button",
        "text": {
          "type": "plain_text",
          "text": "詳細を見る"
        },
        "url": "https://notion.so/task-id"
      }
    }
  ]
}
```

### エラーハンドリング

#### Notion API エラー
- 401 Unauthorized: APIキーの確認を促すエラーメッセージ
- 404 Not Found: データベースIDの確認を促す
- 429 Rate Limit: リトライ機構の実装

#### Slack API エラー
- invalid_auth: トークンの確認を促す
- channel_not_found: チャンネルIDの確認を促す

### 監視・運用

#### CloudWatch メトリクス
- 実行成功率
- 通知送信件数
- エラー発生率
- レスポンス時間

#### アラート設定
- Lambda実行失敗時
- API エラー率が閾値超過時
- 3日連続でタスクが0件の場合（設定ミスの可能性）

## 💰 コスト分析

### 月間運用コスト比較

| 実装方式 | 初期開発コスト | 月間運用コスト | 年間総コスト |
|---------|---------------|---------------|-------------|
| Notion直接連携 | $0 | $10-50 | $120-600 |
| AWS Lambda | $500-1000 | $1 | $500-1012 |
| GitHub Actions | $300-500 | $0 | $300-500 |
| Zapier/Make | $100-200 | $20-50 | $340-800 |

### ROI（投資対効果）分析

**AWS Lambda実装のメリット**:
- 1年目: 初期投資$1000でも、柔軟性と拡張性を確保
- 2年目以降: 年間$12の運用コストのみ
- 既存システムとの統合によるシナジー効果

## 🔒 セキュリティ考慮事項

### APIキー管理
- AWS Secrets Managerまたは環境変数での管理
- 最小権限の原則（Notion: 読み取りのみ、Slack: 投稿のみ）

### データ保護
- 個人情報を含むタスク情報の適切な取り扱い
- ログ出力時の機密情報マスキング

## 📈 将来拡張計画

### Phase 4以降の機能拡張
1. **通知カスタマイズ**
   - ユーザー別通知設定
   - プロジェクト別チャンネル振り分け

2. **分析機能**
   - タスク完了率の分析
   - 期限遵守率レポート

3. **他ツール連携**
   - Google Calendar連携
   - Microsoft Teams対応

## 🎯 推奨決定

**AWS Lambda実装**を推奨します。

### 推奨理由
1. **コストパフォーマンス**: 年間$12の運用コストで高機能
2. **既存システム統合**: 議事録分析システムとのシナジー
3. **柔軟性**: 複雑な通知ロジックに対応可能
4. **スケーラビリティ**: 将来の機能拡張に対応

### 実装スケジュール
- **Week 1**: Lambda関数とTerraform設定
- **Week 2**: テスト・デバッグ・ドキュメント作成
- **Week 3**: 本番デプロイ・運用開始

この設計に基づき、効果的なタスク期限通知システムを構築することで、チームの生産性向上とタスク管理の効率化を実現できます。