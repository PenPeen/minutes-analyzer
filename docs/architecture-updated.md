# Minutes Analyzer アーキテクチャ図（更新版）

## システム全体構成

```mermaid
graph TB
    subgraph "Input Sources"
        GM[Google Meet Recording]
        GC[Google Calendar]
        GD[Google Drive]
    end
    
    subgraph "Trigger"
        GAS[Google Apps Script]
    end
    
    subgraph "AWS Infrastructure"
        subgraph "Processing"
            Lambda[Lambda Function<br/>Ruby 3.2]
            SQS[SQS Queue]
            DLQ[Dead Letter Queue]
        end
        
        subgraph "Storage"
            SM[Secrets Manager]
            S3[S3 Bucket<br/>Prompts & Schemas]
        end
        
        subgraph "Monitoring"
            CW[CloudWatch Logs]
            CWM[CloudWatch Metrics]
            CWA[CloudWatch Alarms]
            CWD[CloudWatch Dashboard]
        end
    end
    
    subgraph "External APIs"
        Gemini[Gemini API<br/>2.5 Flash]
        SlackAPI[Slack API]
        NotionAPI[Notion API]
        CalendarAPI[Calendar API]
    end
    
    subgraph "Output"
        Slack[Slack Channel]
        Notion[Notion Database]
    end
    
    GM -->|Recording File| GD
    GC -->|Event Info| CalendarAPI
    GD -->|File Trigger| GAS
    GAS -->|File ID| Lambda
    
    Lambda -->|Get Secrets| SM
    Lambda -->|Get Prompts| S3
    Lambda -->|Failed Messages| DLQ
    DLQ -->|Retry| SQS
    SQS -->|Process| Lambda
    
    Lambda -->|Find Meeting| CalendarAPI
    CalendarAPI -->|Participants| Lambda
    Lambda -->|Analyze| Gemini
    Lambda -->|Lookup Users| SlackAPI
    Lambda -->|Find Users| NotionAPI
    
    Lambda -->|Send Notification| Slack
    Lambda -->|Create Tasks| Notion
    
    Lambda -->|Logs| CW
    Lambda -->|Metrics| CWM
    CWM -->|Trigger| CWA
    CWM -->|Display| CWD
```

## データフロー詳細

### 1. 録画ファイルから会議特定

```mermaid
sequenceDiagram
    participant GAS as Google Apps Script
    participant Lambda as Lambda Function
    participant Drive as Google Drive API
    participant Calendar as Calendar API
    participant Meeting as Meeting Info
    
    GAS->>Lambda: Send file_id
    Lambda->>Drive: Get file info (created_time)
    Drive-->>Lambda: File metadata
    Lambda->>Calendar: Search events (±24h)
    Calendar-->>Lambda: Event list
    Lambda->>Lambda: Match by attachments.fileId
    alt Found by attachment
        Lambda->>Meeting: Return event
    else Fallback
        Lambda->>Lambda: Match by time & title
        Lambda->>Meeting: Return best match
    end
```

### 2. 参加者マッピングフロー

```mermaid
sequenceDiagram
    participant Lambda as Lambda Function
    participant Calendar as Calendar API
    participant Slack as Slack API
    participant Notion as Notion API
    participant Cache as Memory Cache
    
    Lambda->>Calendar: Get event participants
    Calendar-->>Lambda: Email list
    
    par Parallel Processing
        Lambda->>Cache: Check Slack cache
        alt Cache miss
            Lambda->>Slack: users.lookupByEmail
            Slack-->>Lambda: User info
            Lambda->>Cache: Store result
        end
    and
        Lambda->>Cache: Check Notion cache
        alt Cache miss
            Lambda->>Notion: List all users
            Notion-->>Lambda: User list
            Lambda->>Cache: Store indexed users
        end
    end
    
    Lambda->>Lambda: Generate mappings
    Lambda->>Lambda: Create mentions
```

## コンポーネント詳細

### Lambda Function構成

```
lambda/
├── lambda_function.rb          # メインハンドラー
├── lib/
│   ├── google_calendar_client.rb      # Calendar API
│   ├── google_drive_calendar_bridge.rb # Drive-Calendar連携
│   ├── slack_user_manager.rb          # Slack ユーザー管理
│   ├── notion_user_manager.rb         # Notion ユーザー管理
│   ├── meeting_transcript_processor.rb # 統合処理
│   ├── cloudwatch_metrics.rb          # メトリクス送信
│   ├── structured_logger.rb           # 構造化ログ
│   ├── gemini_client.rb              # Gemini API
│   ├── notion_client.rb              # Notion DB操作
│   └── slack_notifier.rb             # Slack通知
└── spec/                              # テストファイル
```

### 並列処理アーキテクチャ

```ruby
ThreadPoolExecutor (max: 10 threads)
├── Slack API calls
│   ├── users.lookupByEmail (50 req/min limit)
│   └── Rate limiter with retry
├── Notion API calls
│   ├── users.list (pagination)
│   └── pages.update (batch)
└── Calendar API calls
    └── events.list
```

### キャッシング戦略

| コンポーネント | キャッシュ対象 | TTL | 実装 |
|------------|-----------|-----|-----|
| SlackUserManager | Email→User | セッション | Hash |
| NotionUserManager | Email→User | 10分 | UserCache |
| NotionUserManager | 全ユーザーリスト | 10分 | Instance var |
| Calendar Client | - | - | - |

### エラーハンドリング

```mermaid
graph LR
    A[Lambda Execution] -->|Success| B[Complete]
    A -->|Error| C{Retry?}
    C -->|Yes<br/>count < 3| D[Retry]
    D --> A
    C -->|No| E[DLQ]
    E -->|Manual| F[Reprocess]
    F --> A
```

## セキュリティ設計

### 認証フロー

```mermaid
graph TB
    subgraph "Service Accounts"
        GSA[Google Service Account<br/>JSON Key]
    end
    
    subgraph "OAuth Tokens"
        SBT[Slack Bot Token<br/>xoxb-*]
        NIT[Notion Integration Token<br/>secret_*]
    end
    
    subgraph "AWS Secrets Manager"
        Secrets[Encrypted Secrets]
    end
    
    subgraph "Lambda Execution"
        Role[IAM Role]
        Func[Lambda Function]
    end
    
    GSA -->|Store| Secrets
    SBT -->|Store| Secrets
    NIT -->|Store| Secrets
    
    Role -->|GetSecretValue| Secrets
    Func -->|AssumeRole| Role
    Func -->|Use| GSA
    Func -->|Use| SBT
    Func -->|Use| NIT
```

## パフォーマンス最適化

### API呼び出し削減

1. **バッチ処理**
   - 複数メールアドレスを一括検索
   - Notion全ユーザーを一度に取得

2. **キャッシング**
   - ユーザー情報を10分間保持
   - セッション内での重複クエリ削減

3. **並列処理**
   - Slack/Notion APIを同時実行
   - ThreadPoolで最大10スレッド

### レスポンスタイム目標

| 処理 | 目標時間 | 実測値 |
|-----|---------|--------|
| 会議特定 | < 2秒 | 1.5秒 |
| 参加者10名マッピング | < 5秒 | 3.8秒 |
| 議事録分析（Gemini） | < 10秒 | 7.2秒 |
| 全体処理 | < 30秒 | 20秒 |

## モニタリング指標

### ビジネスメトリクス
- 処理成功率（目標: > 95%）
- 参加者マッピング率（目標: > 80%）
- 平均処理時間（目標: < 30秒）

### 技術メトリクス
- Lambda実行時間
- API呼び出し回数/分
- エラー率
- DLQメッセージ数
- キャッシュヒット率

### アラート設定
- エラー率 > 10%
- 処理時間 > タイムアウト95%
- API制限接近（45 req/min）
- DLQメッセージ検知

## デプロイメントパイプライン

```mermaid
graph LR
    A[Local Dev] -->|make test| B[Unit Tests]
    B -->|make build| C[Build Lambda]
    C -->|make deploy-local| D[LocalStack]
    D -->|Test| E{OK?}
    E -->|Yes| F[make deploy-production]
    F --> G[Production]
    E -->|No| H[Fix & Retry]
    H --> A
```

## 今後の拡張計画

1. **機能拡張**
   - Microsoft Teams連携
   - Zoom録画対応
   - 多言語対応

2. **性能改善**
   - DynamoDBによるキャッシュ永続化
   - Step Functionsによるワークフロー管理
   - EventBridgeによるスケジュール実行

3. **分析強化**
   - 会議品質スコアリング
   - 発言者分析
   - アクション項目の自動追跡