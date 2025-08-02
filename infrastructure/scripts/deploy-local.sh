#!/bin/bash

set -e

echo "🚀 LocalStack環境へのデプロイを開始..."

# 環境変数の読み込み
if [ -f .env.local ]; then
    export $(cat .env.local | grep -v '^#' | xargs)
fi

# Lambda関数のビルド
echo "📦 Lambda関数をビルド中..."
make build-lambda

# Terraformでデプロイ
echo "🏗️  Terraformでインフラをデプロイ中..."
make deploy-local

echo "✅ デプロイが完了しました！"
