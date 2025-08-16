# Controller Lambda シーケンス図

本ドキュメントでは、Slack Bot（drive-selector）の基本機能とアーキテクチャを、実装済み機能と将来実装予定機能に分けて説明します。

## 実装済み機能範囲

```mermaid
sequenceDiagram
    participant U as User
    participant S as Slack
    participant AG as API Gateway
    participant CL as Controller Lambda<br/>(drive-selector)
    participant SM as Secrets Manager
    participant GO as Google OAuth

    Note over U,GO: Slack Bot基本認証・インタラクション処理機能

    %% 1. Slackコマンド実行
    U->>S: /meeting-analyzer コマンド実行
    S->>AG: POST /slack/commands<br/>(Slack署名付きリクエスト)
    AG->>CL: Lambda Invoke

    %% 2. リクエスト検証
    CL->>CL: Slack署名検証<br/>(SlackRequestValidator)
    Note over CL: タイムスタンプ検証<br/>リプレイ攻撃対策

    %% 3. 設定情報取得
    CL->>SM: Slack/Google認証情報取得
    SM-->>CL: 機密情報返却

    %% 4. 認証状態確認
    CL->>CL: OAuth認証状態チェック<br/>(メモリキャッシュ)
    Note over CL: セッション基盤認証<br/>(DynamoDB使用せず)

    %% 5. 未認証の場合
    alt 未認証ユーザー
        CL->>GO: 認証URL生成
        GO-->>CL: OAuth認証URL
        CL->>S: 認証を促すメッセージ + 認証URL
        S-->>U: 認証画面案内

        %% 6. OAuth認証フロー
        U->>GO: OAuth認証実行
        GO->>AG: GET /oauth/callback?code=xxx
        AG->>CL: OAuth callback処理
        CL->>GO: 認証コードをトークンに交換
        GO-->>CL: アクセストークン + リフレッシュトークン
        CL->>CL: トークンをメモリキャッシュに保存
        CL->>S: 認証完了通知
        S-->>U: 認証完了メッセージ
    end

    %% 7. インタラクション処理基盤
    Note over U,CL: Slackインタラクション処理基盤
    U->>S: ボタンクリック・モーダル操作
    S->>AG: POST /slack/interactions
    AG->>CL: インタラクション処理
    CL->>CL: 3秒以内ACK応答
    CL->>S: 即座にACK返却

    %% 8. ヘルスチェック
    Note over AG,CL: システム監視
    AG->>CL: GET /health
    CL-->>AG: 200 OK (システム正常)

    %% エラーハンドリング
    Note over CL: 実装されたエラーハンドリング
    Note over CL: • CloudWatchログ出力<br/>• 不正リクエスト排除<br/>• タイムアウト対応
```

## 将来実装予定の機能

```mermaid
sequenceDiagram
    participant U as User
    participant S as Slack
    participant CL as Controller Lambda
    participant GD as Google Drive API
    participant PL as Process Lambda<br/>(analyzer)
    participant GM as Gemini API
    participant N as Notion API

    Note over U,N: ファイル検索・選択・分析実行機能

    %% 認証済みユーザーのフロー
    alt 認証済みユーザー
        CL->>S: ファイル検索モーダル表示
        S-->>U: Drive検索UI表示

        U->>S: ファイル名で検索
        S->>CL: 検索クエリ
        CL->>GD: ファイル検索実行
        GD-->>CL: 検索結果リスト
        CL->>S: 検索結果をモーダルに表示
        S-->>U: ファイル選択肢表示

        U->>S: ファイル選択 + 送信
        S->>CL: 選択されたファイル情報
        CL->>PL: Lambda Invoke（既存analyzer Lambda連携）
        Note over CL,PL: {"file_id": "xxx", "file_name": "yyy"}

        PL->>GD: ファイル内容取得
        PL->>GM: 議事録分析実行
        PL->>S: 分析結果通知
        PL->>N: 議事録・タスク作成

        CL->>S: 処理開始通知
        S-->>U: "分析を開始しました"
    end
```

## 実装されたコンポーネント

### 1. 基盤インフラストラクチャ
- **API Gateway**: Slackからのリクエスト受付
  - `/slack/commands` - Slashコマンド
  - `/slack/interactions` - インタラクション
  - `/oauth/callback` - OAuth認証
  - `/health` - ヘルスチェック

### 2. Controller Lambda (Ruby)
- **handler.rb**: ルーティングとエントリーポイント
- **SlackRequestValidator**: 署名検証とセキュリティ
- **SlackCommandHandler**: コマンド処理基盤
- **SlackInteractionHandler**: インタラクション処理基盤
- **GoogleOAuthClient**: OAuth認証（セッション基盤）

### 3. セキュリティ機能
- Slack署名検証によるリクエスト検証
- タイムスタンプ検証でリプレイ攻撃対策
- Secrets Managerによる機密情報管理
- IAMによる最小権限アクセス制御

### 4. 運用機能
- CloudWatch Logsによるログ管理
- エラーハンドリング
- 3秒ACK応答保証
- ヘルスチェックエンドポイント

## アーキテクチャ上の変更点

### KMS/DynamoDB除去
- **Before**: OAuth トークンをDynamoDBで永続化、KMSで暗号化
- **After**: セッション基盤でメモリ内キャッシュ、暗号化なし

### セッション基盤認証のメリット
1. **シンプル**: 複雑なデータベース管理が不要
2. **低コスト**: DynamoDB・KMSの課金なし
3. **高速**: メモリアクセスで高速動作
4. **セキュア**: Lambdaコンテナ内でのみ保持

### セッション基盤認証の制約
1. **一時的**: Lambdaコンテナ再起動でトークン失効
2. **単一セッション**: 複数デバイス間での認証状態共有不可

この制約は、議事録分析という用途では許容範囲内と判断されます。
