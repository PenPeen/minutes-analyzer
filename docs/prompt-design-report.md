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
入力としてGemini議事録の全文テキストをそのまま受け取ります。これには以下の情報が含まれます：
- 日付（YYYY年MM月DD日形式）
- 会議タイトル
- 参加者リスト（「録音済み」の後に記載）
- まとめセクション（会議全体の要約）
- 詳細セクション（主要トピックの箇条書き、タイムスタンプ付き）
- 文字起こし全文（HH:MM:SS形式のタイムスタンプと話者名付き）

議事録の構造は変更される可能性がありますが、AIが柔軟に解析して必要な情報を抽出します。

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
- タスクの背景・文脈（なぜこのタスクが必要か、議論の背景を簡潔に記載）
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

### 3.3 会議の温度感
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
      "category": "pricing/schedule/policy/other"
    }
  ],
  "actions": [
    {
      "task": "タスク内容",
      "assignee": "担当者名",
      "priority": "high/medium/low",
      "deadline": "期日またはnull",
      "deadline_formatted": "YYYY/MM/DD形式または'期日未定'",  // Slack通知用のフォーマット済み日付
      "task_context": "タスクの背景・文脈情報",  // なぜこのタスクが必要か
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

**実装方針：**
- GASは議事録ファイルのメタデータのみを送信
- Lambda関数がGoogle Drive APIを使用してファイルを直接読み取り
- ファイルサイズに関わらず統一的な処理が可能

```json
{
  "file_id": "1234567890abcdef",  // Google DriveのファイルID
  "file_name": "2025年1月15日_新機能リリース進捗確認ミーティング.txt",
}
```

**処理フロー：**
1. GASが新しい議事録ファイルを検知
2. ファイルIDとメタデータをLambda関数に送信
3. Lambda関数がGoogle Drive APIを使用してファイルを取得
4. 取得したテキストをGemini APIに送信して分析
5. 分析結果をSlack/Notionに配信

**設計の利点：**
1. **統一性**: ファイルサイズに関わらず同じ処理フロー
2. **スケーラビリティ**: Lambdaのペイロード制限（6MB）を気にする必要なし
3. **セキュリティ**: ファイル内容をネットワーク経由で送信しない
4. **効率性**: 大きなテキストデータの転送が不要
5. **トレーサビリティ**: ファイルIDで元データを追跡可能

**Google Drive API認証：**
- サービスアカウントを使用
- 必要な権限: `drive.readonly`
- ファイルへのアクセス権限の事前付与が必要

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
      "category": "pricing"
    }
  ],
  "actions": [
    {
      "task": "脆弱性テストの実施",
      "assignee": "セキュリティチーム",
      "priority": "high",
      "deadline": "今週末",
      "deadline_formatted": "2025/08/10",
      "task_context": "リリース前の最終セキュリティチェックとして、外部向けAPIの脆弱性評価が必要",
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
      "task_context": "フロントエンド・バックエンドの主要機能が完成したため、統合テストを開始する段階",
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
      "task_context": "外部APIの仕様変更により軽微な遅延が発生、早急な対応が必要",
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
    "silent_participants": []
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

### 通知仕様

#### 表示制限ルール
- **決定事項**: 最大3件表示（超過時は「…他〇件」を表示）
- **アクション**: 最大3件表示（超過時は「…他〇件」を表示）
- **参加者**: 最大3名表示（超過時は「…他〇名」を表示）
- **健全性スコア**: Slack通知では非表示

#### アクションの並び順
1. **優先度順**（high → medium → low）
2. **同一優先度内では期日順**（早い期日 → 遅い期日 → 期日未定）

### 通知パターン一覧

#### 1. 基本パターン（3件以内の場合）
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
      "text": {"type": "mrkdwn", "text": "*📋 アクション一覧*\n1. 🔴 脆弱性テストの実施 - セキュリティチーム（2025/08/10）\n2. 🔴 品質保証開始 - QAチーム（2025/08/15）\n3. 🟡 マーケティング施策の準備 - マーケチーム（2025/08/20）"}
    }
  ]
}
```

#### 2. 項目数が多い場合（省略表示あり）
```json
{
  "blocks": [
    {
      "type": "section",
      "fields": [
        {"type": "mrkdwn", "text": "*🎯 決定事項:* 5件"},
        {"type": "mrkdwn", "text": "*📋 アクション:* 7件"}
      ]
    },
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "*🎯 主な決定事項*\n1. 価格設定を月額500円に決定\n2. リリース日を2月1日に設定\n3. セキュリティ要件の確定\n…他2件"}
    },
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "*📋 アクション一覧*\n1. 🔴 脆弱性テストの実施 - セキュリティチーム（2025/08/10）\n2. 🔴 品質保証開始 - QAチーム（2025/08/15）\n3. 🟡 API連携の実装 - 開発チーム（期日未定）\n…他4件"}
    }
  ]
}
```

#### 3. 期日なしアクションの警告表示
```json
{
  "blocks": [
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "*📋 アクション一覧*\n1. 🔴 脆弱性テストの実施 - セキュリティチーム（2025/08/10）\n2. 🟡 品質保証開始 - QAチーム（期日未定）\n3. ⚪ API連携の実装 - 開発チーム（期日未定）"}
    },
    {
      "type": "context",
      "elements": [
        {"type": "mrkdwn", "text": "⚠️ *2件のアクションに期日が設定されていません*"}
      ]
    }
  ]
}
```

#### 4. アクションがない場合
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
