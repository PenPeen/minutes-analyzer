#!/bin/sh
set -e

echo "🔨 Lambda関数をビルド中..."

# Gemfileの存在確認
if [ ! -f Gemfile ]; then
    echo "❌ Gemfileが見つかりません"
    exit 1
fi

# 依存関係のインストール
if [ ! -f .bundle/config ] || [ Gemfile -nt .bundle/config ] || [ Gemfile.lock -nt .bundle/config ]; then
    echo "📦 依存関係をインストール中..."
    bundle install --deployment --without development test
    touch .bundle/config
else
    echo "✅ 依存関係は最新です"
fi

# 出力パスを /output に固定（docker-compose.ymlでマウント）
OUTPUT_PATH="/output/lambda.zip"

# zipファイルを作成
echo "📦 パッケージング中... ($OUTPUT_PATH)"
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
