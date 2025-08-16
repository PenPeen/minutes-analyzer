# プロジェクト実装タスク計画

## 概要
Slack上でGoogle Driveファイル（Meet文字起こし）を検索・選択し、既存の議事録分析Lambdaへ起動リクエストを送る機能の実装計画です。

- **目的**: Slack Bot経由でのGoogle Driveファイル選択・分析処理実行
- **成功基準**: /meet-transcript コマンドでDriveファイルを検索・選択し、分析処理を開始可能
- **実装場所**: drive-selectorディレクトリ内（analyzerとは独立したマイクロサービス）

## 主要タスク

### フェーズ1: 基盤実装
- **T-01**: Slack App設定と権限拡張 ✅
- **T-02**: Google OAuth 2.0認証設定  
- **T-03**: Controller Lambda基本実装（Ruby）

### フェーズ2: UI・検索機能  
- **T-04**: モーダルUI実装
- **T-05**: Google Drive検索機能実装

### フェーズ3: 連携・インフラ
- **T-06**: 既存Lambda Invoke連携
- **T-07**: API Gateway設定
- **T-08**: IAMロールと環境変数設定

### フェーズ4: テスト・デプロイ
- **T-09**: 統合テストと開発環境での動作確認
- **T-10**: 本番デプロイとドキュメント整備

## 技術仕様

### アーキテクチャ
- **API Gateway REST API**: SlackからのリクエストをLambdaにルーティング  
- **マイクロサービス**: drive-selectorディレクトリ内に独立実装
- **言語**: Ruby（analyzerと統一）
- **認証**: Google OAuth 2.0（ユーザー権限）
- **環境変数管理**: .env.local → Terraform → Secrets Manager

### ディレクトリ構造
```
drive-selector/
├── lambda/           # Ruby Lambda関数
├── infrastructure/   # Terraform設定
├── test/            # RSpecテスト  
└── README.md        # ドキュメント
```

詳細な技術仕様は [docs/architecture.md](docs/architecture.md) を参照してください。
