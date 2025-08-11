#!/bin/sh
set -e

echo "🔨 Lambda関数をビルド中..."

# Gemfileの存在確認
if [ ! -f Gemfile ]; then
    echo "❌ Gemfileが見つかりません"
    exit 1
fi

# 依存関係のインストール
echo "📦 依存関係をインストール中..."
# Lambda環境に合わせた設定
bundle config set --local path 'vendor/bundle'
bundle config set --local deployment 'true'
bundle config set --local without 'development test'
# Ruby 3.2プラットフォーム用にビルド
bundle config set --local force_ruby_platform 'true'
bundle lock --add-platform ruby
bundle install --jobs=4 --retry=3

# 出力パスを /output に固定（docker-compose.ymlでマウント）
OUTPUT_PATH="/output/lambda.zip"

# zipファイルを作成
echo "📦 パッケージング中... ($OUTPUT_PATH)"
# Lambda関数に必要なファイルのみをパッケージング
cd /var/task
zip -qr "$OUTPUT_PATH" . -x \
    'spec/*' \
    '*.git*' \
    'Makefile' \
    '.bundle/*' \
    'vendor/bundle/ruby/*/cache/*' \
    'vendor/bundle/ruby/*/gems/*/test/*' \
    'vendor/bundle/ruby/*/gems/*/spec/*'

if [ -f "$OUTPUT_PATH" ]; then
    echo "✅ Lambda関数のビルドが完了しました"
    ls -la "$OUTPUT_PATH"
else
    echo "❌ zipファイルの作成に失敗しました"
    exit 1
fi
