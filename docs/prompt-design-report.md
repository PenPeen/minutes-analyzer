# Gemini議事録分析API プロンプト設計レポート

## 📋 概要

本レポートは、Geminiが自動生成する議事録から「決定事項」「今後のアクション」「MTGレビュー」を自動抽出・分析するためのプロンプト設計をまとめたものです。Gemini 2.5 Flashを使用して実装することを前提としています。

## 🎯 レポートの出力要件と実現性評価

### 基本機能要件の検討（テストデータに基づく評価）

| 機能カテゴリ | 要件内容 | 実現性 | 根拠 |
|------------|---------|--------|------|
| **決定事項** | MTGで決定した決定事項の列挙 | ✅ | 議事録全体から「決定」「確認」「合意」等の表現を抽出して特定可能 |
| **今後のアクション** | NextActionの列挙 | ✅ | 議事録全体から「実施」「予定」「する」等の未来形表現を抽出可能 |
| | 優先順位付け | ✅ | 期限の緊急度や文脈から優先度を推論可能 |
| | 期日の記載 | ✅ | 「今週末」「来週」などの時間表現が発言内に含まれる |
| **MTGレビュー** | 会議の健全性スコアリング | ✅ | 決定事項数、議論の活発さ、時間効率から定量評価可能 |
| | 矛盾点/未解決課題の検出 | ✅ | 課題や懸念事項は通常明示的に発言される |
| | 担当者・期日未定項目のチェック | ✅ | 参加者リストと発言者の照合により担当者を特定可能 |
| | 会議の温度感分析 | ✅ | 使用される語彙や表現から雰囲気を分析可能 |
| **改善アドバイス** | 発言の偏り分析 | ✅ | 発言回数・割合を計算し、参加の均等性を評価（発言していない人も含む） |
| | 時間効率性：実際時間の計算 | ✅ | 最初と最後のタイムスタンプから実際の所要時間を算出可能 |
| | 時間効率性：予定時間との比較 | ❌ | Gemini議事録には予定時間情報が含まれない |

### 実現できない理由の詳細

- **予定時間との比較**: Gemini議事録には会議の実際の内容のみが記録され、事前の予定情報（会議招集時の予定時間など）は含まれていないため

### Slack/Notion連携の活用設計

#### Slack通知の最適化
```json
{
  "blocks": [
    {
      "type": "header",
      "text": "📝 新機能リリース進捗確認MTG"
    },
    {
      "type": "section",
      "fields": [
        {"type": "mrkdwn", "text": "*🎯 決定事項:* 2件"},
        {"type": "mrkdwn", "text": "*📋 アクション:* 3件"}
      ]
    },
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "*📋 アクション一覧*\n1. 脆弱性テストの実施 - セキュリティチーム（2025/08/10）\n2. 品質保証開始 - QAチーム（2025/08/15）\n3. API連携の課題解決 - 開発チーム（期日未定）"}
    },
    {
      "type": "actions",
      "elements": [
        {"type": "button", "text": "詳細を見る", "url": "notion_url"}
      ]
    }
  ]
}
```

#### Notion連携の構造
```
議事録データベース
├── 基本情報（日時、参加者、所要時間）
├── 決定事項（リレーション: プロジェクトDB）
├── アクション項目（リレーション: タスクDB）
├── 分析結果（健全性スコア、改善提案）
└── 関連議事録（自動サジェスト）
```

## 📝 最終プロンプト設計

### 統合プロンプト

```markdown
あなたはGemini自動生成議事録の分析専門家です。以下の議事録を分析し、JSON形式で構造化された分析結果を出力してください。

# 入力議事録の構造
入力として以下の構造のJSONデータを受け取ります：
{
  "transcript": {
    "date": "YYYY-MM-DD形式の日付",
    "title": "会議のタイトル",
    "participants": ["参加者名のリスト"],
    "summary": "Geminiが生成した会議全体の要約",
    "details": "主要トピックの箇条書き（タイムスタンプ付き）",
    "full_text": "タイムスタンプ付きの全文字起こし（HH:MM:SS\n話者名: 発言内容）"
  },
  "metadata": {
    "file_id": "Google DriveのファイルID（Notion連携時の参照用）",
    "scheduled_duration": "予定時間（オプション）",
    "actual_duration": "実際の所要時間（タイムスタンプから計算）"
  }
}

# 分析指示

## 1. 決定事項の抽出
議事録全体（まとめ、詳細、文字起こし）から、明確に決定された事項を抽出してください。
- 「決定」「確認」「合意」「設定」等の表現に注目
- 価格設定、スケジュール、方針、合意事項など
- 各決定事項にタイムスタンプと決定者を付与

## 2. 今後のアクションの分析
議事録全体から、実行すべきタスクを抽出し、以下の情報を付与してください。
- タスク内容と担当者（参加者リストと照合）
- 優先度（high/medium/low）を文脈から判断
- 期日（明記されている場合は抽出、ない場合はnull）
- deadline_formatted（期日をYYYY/MM/DD形式に変換、またはnullの場合は'期日未定'）
- 実行手順の提案（2-3ステップの簡潔な手順）
- アクションのサマリー情報（総数、期日あり/なしの数、高優先度の数）を生成

## 3. 会議の健全性評価
以下の観点から会議を評価してください。

### 3.1 基本指標
- 健全性スコア（0-100）：決定事項の明確さ、議論の活発さ、時間効率から総合評価
- 矛盾点・未解決課題：議論中の不整合や保留事項を列挙
- 未定項目：担当者や期日が決まっていないアクションを特定

### 3.2 参加度分析
- 各参加者の発言回数と発言時間の割合を計算
- 発言の偏り度合いをスコア化（0-100、100が完全に均等）
- 発言が少ないまたはない参加者がいる場合は、ファシリテーションの改善点として提案

### 3.3 時間効率性
- 会議の実際の所要時間（最初と最後のタイムスタンプから計算）
- 各議題の所要時間
- 予定時間が議事録に記載されている場合は比較、ない場合は「記載なし」と出力

### 3.4 会議の温度感
- 全体的な雰囲気（positive/neutral/negative）
- 根拠となる発言や表現を引用

## 4. 改善提案
上記の分析結果に基づき、次回の会議改善のための具体的な提案を3つ生成してください。
- 各提案は実行可能で具体的な内容
- 建設的で前向きな表現を使用
- ファシリテーション技術の向上に関するアドバイスを含む

# 出力形式
以下のJSON構造で分析結果を出力してください。このデータはSlack通知とNotion DBへの保存に使用されます：
**JSON以外の出力は禁止**です。

{
  "meeting_summary": {
    "date": "YYYY-MM-DD",
    "title": "会議タイトル",
    "duration_minutes": 数値,
    "participants": ["参加者1", "参加者2", ...]
  },
  "decisions": [
    {
      "content": "決定内容",
      "category": "pricing/schedule/policy/other",
      "timestamp": "HH:MM:SS",
      "decided_by": "決定者名"
    }
  ],
  "actions": [
    {
      "task": "タスク内容",
      "assignee": "担当者名",
      "priority": "high/medium/low",
      "deadline": "期日またはnull",
      "deadline_formatted": "YYYY/MM/DD形式または'期日未定'",  // Slack通知用のフォーマット済み日付
      "suggested_steps": ["ステップ1", "ステップ2", "ステップ3"],
      "timestamp": "HH:MM:SS",
      "notion_task_id": null  // Notion DB連携時に後から付与されるID
    }
  ],
  "actions_summary": {
    "total_count": 3,
    "with_deadline": 2,
    "without_deadline": 1,  // 期日なしアクションの数（Slack通知で使用）
    "high_priority_count": 1
  },
  "health_assessment": {
    "overall_score": 0-100,
    "contradictions": ["矛盾点1", "矛盾点2"],
    "unresolved_issues": ["未解決課題1", "未解決課題2"],
    "undefined_items": [
      {
        "task": "タスク内容",
        "missing": ["assignee", "deadline"]
      }
    ]
  },
  "participation_analysis": {
    "balance_score": 0-100,
    "speaker_stats": {
      "参加者名": {
        "speaking_count": 数値,
        "speaking_ratio": "XX%"
      }
    },
    "silent_participants": ["参加者名"]
  },
  "time_efficiency": {
    "actual_duration": "XX分",
    "scheduled_duration": "XX分または「記載なし」",
    "topic_durations": {
      "トピック名": "XX分"
    }
  },
  "atmosphere": {
    "overall_tone": "positive/neutral/negative",
    "evidence": ["根拠となる発言1", "根拠となる発言2"]
  },
  "improvement_suggestions": [
    {
      "category": "participation/time_management/decision_making/facilitation",
      "suggestion": "具体的な改善提案",
      "expected_impact": "期待される効果"
    }
  ]
}

# 分析時の注意事項
- 個人を批判的に評価しない
- 数値は根拠（タイムスタンプ、発言回数等）と共に算出
- 推測が必要な場合は保守的に評価
- 建設的で実行可能な提案を心がける
```

## 🔄 データスキーマとAPI連携

### 入力データスキーマ（Lambda関数への入力）

```json
{
  "transcript": {
    "date": "2025-01-15",
    "title": "新機能リリース進捗確認ミーティング",
    "participants": ["平岡健児氏", "小田まゆか", "Ayumi Tanigawa"],
    "summary": "会議全体の要約テキスト...",
    "details": "箇条書きの詳細情報...",
    "full_text": "タイムスタンプ付きの全文字起こし..."
  },
  "metadata": {
    "file_id": "google_drive_file_id",  // Notion連携時の参照リンク作成、トレーサビリティ確保のため
    "scheduled_duration": "30分",  // Google Calendar APIから取得（オプション）
    "actual_duration": "20分35秒"  // Gemini議事録のタイムスタンプから計算可能
  }
}
```

**メタデータの説明：**
- `file_id`: Google DriveファイルIDを保持することで、Notion連携時に元ファイルへのリンクを作成可能。また、再処理時の重複チェックにも使用
- `scheduled_duration`: Google Calendar APIと連携すれば取得可能だが、現状は実装対象外
- `actual_duration`: Gemini議事録の最初と最後のタイムスタンプから自動計算可能

### 期待出力スキーマ（Gemini APIレスポンス）

```json
{
  "meeting_summary": {
    "date": "2025-01-15",
    "title": "新機能リリース進捗確認ミーティング",
    "duration_minutes": 20,
    "participants": ["平岡健児氏", "小田まゆか", "Ayumi Tanigawa"]
  },
  "decisions": [
    {
      "content": "価格設定：基本プラン500円/ユーザー、プレミアムプラン8,000円",
      "category": "pricing",
      "timestamp": "00:02:13",
      "decided_by": "小田まゆか"
    }
  ],
  "actions": [
    {
      "task": "脆弱性テストの実施",
      "assignee": "セキュリティチーム",
      "priority": "high",
      "deadline": "今週末",
      "deadline_formatted": "2025/08/10",
      "suggested_steps": [
        "OWASP Top 10の項目をチェック",
        "ペネトレーションテストの実行",
        "結果レポートの作成と共有"
      ],
      "timestamp": "00:03:58"
    },
    {
      "task": "品質保証開始",
      "assignee": "QAチーム",
      "priority": "medium",
      "deadline": "来週",
      "deadline_formatted": "2025/08/15",
      "suggested_steps": [
        "テストケースの作成",
        "機能テストの実施",
        "バグレポートの作成"
      ],
      "timestamp": "00:04:05"
    },
    {
      "task": "API連携の課題解決",
      "assignee": "開発チーム",
      "priority": "high",
      "deadline": null,
      "deadline_formatted": "期日未定",
      "suggested_steps": [
        "API仕様変更の詳細確認",
        "実装の修正",
        "動作確認テスト"
      ],
      "timestamp": "00:03:05"
    }
  ],
  "actions_summary": {
    "total_count": 3,
    "with_deadline": 2,
    "without_deadline": 1,
    "high_priority_count": 2
  },
  "health_assessment": {
    "overall_score": 92,
    "contradictions": ["外部APIとの連携部分で軽微な遅延"],
    "unresolved_issues": ["API仕様変更への対応"],
    "undefined_items": []
  },
  "participation_analysis": {
    "balance_score": 85,
    "speaker_stats": {
      "平岡健児氏": {
        "speaking_count": 15,
        "speaking_ratio": "42%"
      },
      "小田まゆか": {
        "speaking_count": 11,
        "speaking_ratio": "31%"
      },
      "Ayumi Tanigawa": {
        "speaking_count": 10,
        "speaking_ratio": "27%"
      }
    },
    "low_participation_members": []  // 発言が少ない参加者（個人攻撃を避けるため空の場合あり）
  },
  "time_efficiency": {
    "actual_duration": "20分35秒",
    "scheduled_duration": "記載なし",
    "topic_durations": {
      "フロントエンド進捗": "3分",
      "バックエンド進捗": "4分",
      "価格設定確認": "2分",
      "セキュリティ対応": "3分",
      "リスク管理": "5分"
    }
  },
  "atmosphere": {
    "overall_tone": "positive",
    "evidence": [
      "素晴らしい進捗ですね（00:01:15）",
      "高い評価をいただいています（00:00:23）",
      "順調に進んでいます（00:01:23）"
    ]
  },
  "improvement_suggestions": [
    {
      "category": "participation",
      "suggestion": "発言の割合は比較的バランスが取れていますが、より均等な参加を促すため、各議題で全員から意見を求める時間を設けると良いでしょう",
      "expected_impact": "チーム全体の当事者意識向上"
    },
    {
      "category": "time_management",
      "suggestion": "20分で多くの議題をカバーしていますが、リスク管理に5分かかっています。事前に課題リストを共有しておくと効率化できます",
      "expected_impact": "会議時間の10-15%短縮"
    },
    {
      "category": "decision_making",
      "suggestion": "外部API連携の課題について、具体的な解決期限を設定することをお勧めします",
      "expected_impact": "課題解決の確実性向上"
    },
    {
      "category": "facilitation",
      "suggestion": "各議題の開始時に「この議題で決めたいこと」を明確にすると、議論がより焦点を絞れます",
      "expected_impact": "意思決定の迅速化と議論の質向上"
    }
  ]
}
```

## 💡 Slack通知パターン

### 通知パターン一覧

#### 1. 基本パターン（アクションあり・期日あり）
```json
{
  "text": "📝 新機能リリース進捗確認MTGの議事録レビューが完了しました！",
  "blocks": [
    {
      "type": "header",
      "text": {"type": "plain_text", "text": "📝 新機能リリース進捗確認MTG"}
    },
    {
      "type": "section",
      "fields": [
        {"type": "mrkdwn", "text": "*🎯 決定事項:* 2件"},
        {"type": "mrkdwn", "text": "*📋 アクション:* 3件"}
      ]
    },
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "*📋 アクション一覧*\n1. 脆弱性テストの実施 - セキュリティチーム（2025/08/10）\n2. 品質保証開始 - QAチーム（2025/08/15）\n3. マーケティング施策の準備 - マーケチーム（2025/08/20）"}
    }
  ]
}
```

#### 2. 期日なしアクションがある場合
```json
{
  "blocks": [
    // ヘッダー部分は同じ
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "*📋 アクション一覧*\n1. 脆弱性テストの実施 - セキュリティチーム（2025/08/10）\n2. 品質保証開始 - QAチーム（2025/08/15）\n3. 広告キャンペーンの進捗報告 - マーケチーム（期日未定）⚠️\n4. API連携の課題解決 - 開発チーム（期日未定）⚠️"}
    }
  ]
}
```

#### 3. アクションがない場合
```json
{
  "blocks": [
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "🔍 *今回の会議ではアクション項目はありませんでした*"}
    }
  ]
}
```

### 通知ロジック
```python
def create_slack_notification(analysis_result):
    actions = analysis_result.get('actions', [])

    # アクションの期日状態をチェック
    actions_without_deadline = [a for a in actions if a['deadline'] is None]

    if not actions:
        return create_no_action_notification(analysis_result)
    elif actions_without_deadline:
        return create_deadline_warning_notification(analysis_result, actions_without_deadline)
    else:
        return create_standard_notification(analysis_result)
```

## 📚 Notion連携の拡張性

### アクション項目の自動管理フロー
```
1. Lambda関数がGemini APIレスポンスを受信
2. actions配列の各項目をNotion タスクDBに自動登録
3. Notion APIからタスクIDを取得し、notion_task_idに格納
4. 期日が近づいたら自動でSlackリマインダーを送信
5. タスク完了時にNotion DBのステータスを自動更新
```

### Notion DB構造の推奨設計
```
議事録DB (Minutes Database)
├── 基本情報フィールド
│   ├── 日時 (Date)
│   ├── タイトル (Title)
│   ├── 参加者 (Multi-select)
│   └── Google DriveリンクURL)
├── 分析結果フィールド
│   ├── 健全性スコア (Number)
│   ├── 決定事項 (Rich Text)
│   └── 改善提案 (Rich Text)
└── リレーション
    ├── 関連タスク → タスクDB
    └── 関連プロジェクト → プロジェクトDB

タスクDB (Actions Database)
├── タスク情報
│   ├── タスク内容 (Title)
│   ├── 担当者 (Person)
│   ├── 優先度 (Select: high/medium/low)
│   ├── 期限 (Date)
│   └── ステータス (Select: 未着手/進行中/完了)
└── リレーション
    └── 元の議事録 → 議事録DB
```

この設計により、議事録から抽出されたアクション項目が自動的にタスク管理システムに統合され、進捗管理が可能になります。


---

*本設計は、Gemini 2.5 Flashの能力とGemini生成議事録の構造を最大限に活用し、実用的で価値の高い分析を実現することを目指しています。*
