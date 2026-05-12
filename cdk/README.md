# Minutes Analyzer CDK Project

AWS CDKを使用した議事録分析システムのインフラストラクチャ定義です。

## セットアップ

```bash
npm install
```

## ビルド

```bash
npm run build
```

## デプロイ

```bash
# 全スタックをデプロイ
npm run deploy:all

# 個別にデプロイ
npm run deploy:analyzer
npm run deploy:drive-selector
```

## 削除

```bash
npm run destroy:analyzer
npm run destroy:drive-selector
```

## 構成

- `bin/app.ts`: CDKアプリケーションのエントリーポイント
- `lib/analyzer-stack.ts`: 議事録分析エンジンのスタック定義
- `lib/drive-selector-stack.ts`: Slack Botのスタック定義
