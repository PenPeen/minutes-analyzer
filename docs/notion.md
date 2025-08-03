# Notion API連携 運用設計書

## 概要

議事録分析システムとNotion APIを連携し、議事録データの一元管理とタスクの自動化を実現する運用設計をまとめたドキュメントです。

## 技術的実現性

### ✅ 実現可能な理由

1. **Notion API の成熟度**
   - v2.0が安定稼働中（2023年以降）
   - データベースへの読み書きが完全サポート
   - リレーション機能のAPI対応
   - Rate Limit: 3リクエスト/秒（十分な余裕）

2. **Lambda関数からの連携**
   - AWS SDKとNotion SDKの併用が可能
   - 非同期処理による効率的な実装
   - エラーハンドリングの実装が容易

3. **必要な権限スコープ**
   - `pages:read` - 議事録ページの読み取り
   - `pages:write` - 議事録ページの作成
   - `databases:read` - データベースの参照
   - `databases:write` - タスク項目の追加

## データベース設計

### 議事録DB (Meeting Minutes)

```
Properties:
├── タイトル (Title) - テキスト
├── 日時 (Date) - 日付
├── 参加者 (Participants) - マルチセレクト
├── 所要時間 (Duration) - 数値（分）
├── 健全性スコア (Health Score) - 数値（0-100）
├── Google Drive URL - URL
├── 決定事項 (Decisions) - リッチテキスト
├── 改善提案 (Improvements) - リッチテキスト
└── Relations:
    ├── アクション項目 → Actions DB
    └── プロジェクト → Projects DB
```

### アクションDB (Actions)

```
Properties:
├── タスク名 (Task) - タイトル
├── 担当者 (Assignee) - ユーザー
├── 優先度 (Priority) - セレクト [High/Medium/Low]
├── 期限 (Due Date) - 日付
├── ステータス (Status) - セレクト [未着手/進行中/完了]
├── 作成日 (Created) - 作成日時
├── 完了日 (Completed) - 日付
└── Relations:
    └── 元の議事録 → Meeting Minutes DB
```

## 実装フロー

### 1. 初期セットアップ

```python
# 環境変数
NOTION_API_KEY = "secret_xxx"
NOTION_MINUTES_DB_ID = "xxx-xxx-xxx"
NOTION_ACTIONS_DB_ID = "yyy-yyy-yyy"
```

### 2. Lambda関数での処理

```python
import os
from notion_client import Client
from datetime import datetime

class NotionIntegration:
    def __init__(self):
        self.notion = Client(auth=os.environ["NOTION_API_KEY"])
        self.minutes_db = os.environ["NOTION_MINUTES_DB_ID"]
        self.actions_db = os.environ["NOTION_ACTIONS_DB_ID"]
    
    def create_meeting_record(self, analysis_result):
        """議事録レコードの作成"""
        page = self.notion.pages.create(
            parent={"database_id": self.minutes_db},
            properties={
                "タイトル": {"title": [{"text": {"content": analysis_result["meeting_summary"]["title"]}}]},
                "日時": {"date": {"start": analysis_result["meeting_summary"]["date"]}},
                "参加者": {"multi_select": [{"name": p} for p in analysis_result["meeting_summary"]["participants"]]},
                "所要時間": {"number": analysis_result["meeting_summary"]["duration_minutes"]},
                "健全性スコア": {"number": analysis_result["health_assessment"]["overall_score"]}
            },
            children=[
                # 決定事項セクション
                {"object": "block", "type": "heading_2", "heading_2": {"rich_text": [{"text": {"content": "決定事項"}}]}},
                *self._create_decision_blocks(analysis_result["decisions"]),
                # 改善提案セクション
                {"object": "block", "type": "heading_2", "heading_2": {"rich_text": [{"text": {"content": "改善提案"}}]}},
                *self._create_improvement_blocks(analysis_result["improvement_suggestions"])
            ]
        )
        return page["id"]
    
    def create_action_items(self, actions, meeting_page_id):
        """アクション項目の一括作成"""
        created_tasks = []
        for action in actions:
            task = self.notion.pages.create(
                parent={"database_id": self.actions_db},
                properties={
                    "タスク名": {"title": [{"text": {"content": action["task"]}}]},
                    "担当者": {"people": [{"object": "user", "id": self._get_user_id(action["assignee"])}]},
                    "優先度": {"select": {"name": action["priority"].capitalize()}},
                    "期限": {"date": {"start": self._parse_deadline(action["deadline"])}} if action["deadline"] else {},
                    "ステータス": {"select": {"name": "未着手"}},
                    "元の議事録": {"relation": [{"id": meeting_page_id}]}
                }
            )
            created_tasks.append({"notion_id": task["id"], "original_task": action["task"]})
        return created_tasks
```

### 3. エラーハンドリング

```python
def safe_notion_operation(func):
    """Notion API操作のエラーハンドリングデコレータ"""
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except APIResponseError as e:
            if e.status == 429:  # Rate limit
                time.sleep(1)
                return func(*args, **kwargs)
            else:
                logger.error(f"Notion API error: {e}")
                # Slackに通知だけ送信し、処理は継続
                return None
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            return None
    return wrapper
```

## 運用上の考慮事項

### 1. 権限管理

- **Notion Integration の作成**
  - Organization管理者による承認が必要
  - 必要最小限のスコープのみ付与
  - 定期的なトークンローテーション

- **データベースアクセス**
  - IntegrationをDBに招待する必要あり
  - 読み書き権限の適切な設定

### 2. データ同期

- **重複防止**
  - Google Drive file_idでの重複チェック
  - 既存レコードの更新 vs 新規作成の判定

- **整合性確保**
  - トランザクション的な処理は不可
  - 部分的な成功を許容する設計

### 3. パフォーマンス

- **Rate Limit対策**
  - バッチ処理の活用
  - 指数バックオフの実装
  - 非同期処理の活用

- **大量データ対応**
  - ページネーションの実装
  - 必要なプロパティのみ取得

### 4. 監視・アラート

```python
# CloudWatchメトリクス
def publish_metrics(success_count, error_count):
    cloudwatch.put_metric_data(
        Namespace='MinutesAnalyzer/Notion',
        MetricData=[
            {
                'MetricName': 'SuccessfulWrites',
                'Value': success_count,
                'Unit': 'Count'
            },
            {
                'MetricName': 'FailedWrites',
                'Value': error_count,
                'Unit': 'Count'
            }
        ]
    )
```

## 導入ステップ

### Phase 1: 基本連携（1-2週間）
1. Notion Integrationの作成と承認
2. データベースの作成
3. Lambda関数への連携コード追加
4. エラーハンドリングの実装

### Phase 2: 自動化強化（2-3週間）
1. 期限リマインダー機能
2. ステータス自動更新
3. 週次レポート生成

### Phase 3: 高度な分析（1ヶ月〜）
1. 過去議事録との関連付け
2. プロジェクト横断分析
3. チーム生産性ダッシュボード

## コスト試算

- **Notion API**: 無料（Enterpriseプランに含まれる）
- **追加のLambda実行時間**: 約10秒/議事録
- **月間コスト増分**: $1-2程度

## リスクと対策

| リスク | 影響度 | 対策 |
|--------|--------|------|
| Notion APIの仕様変更 | 中 | バージョン固定、変更通知の監視 |
| Rate Limit超過 | 低 | リトライロジック、バッチ処理 |
| データ不整合 | 中 | 定期的な整合性チェック、手動修正UI |
| 権限エラー | 低 | 事前の権限チェック、フォールバック |

## まとめ

Notion API連携は技術的に十分実現可能であり、以下のメリットが期待できます：

1. **議事録の一元管理**: 散在していた議事録をNotionに集約
2. **タスクの自動化**: アクション項目の自動登録と追跡
3. **可視化の向上**: Notionのビュー機能を活用した分析

導入は段階的に進めることで、リスクを最小化しながら価値を最大化できます。