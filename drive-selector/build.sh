#!/bin/bash

# Lambda関数のビルドスクリプト
# Ruby 3.2 Lambda関数のデプロイパッケージを作成

set -e

echo "🚀 Building Lambda deployment package..."

# ビルドディレクトリの準備
BUILD_DIR="build"
LAMBDA_DIR="lambda"
OUTPUT_FILE="lambda.zip"

# クリーンアップ
rm -rf $BUILD_DIR
rm -f $OUTPUT_FILE

# ビルドディレクトリ作成
mkdir -p $BUILD_DIR

# Lambda関数のコードをコピー
cp -r $LAMBDA_DIR/* $BUILD_DIR/

# ビルドディレクトリに移動
cd $BUILD_DIR

# Gemfileが存在する場合、依存関係をインストール
if [ -f "Gemfile" ]; then
  echo "📦 Installing Ruby dependencies..."
  
  # Dockerを使用してLambda互換環境でビルド
  docker run --rm \
    -v "$PWD":/var/task \
    -w /var/task \
    public.ecr.aws/lambda/ruby:3.2 \
    bash -c "bundle config set --local path 'vendor/bundle' && \
             bundle config set --local without 'development test' && \
             bundle install && \
             rm -rf vendor/bundle/ruby/*/cache"
fi

# ZIPファイル作成
echo "📦 Creating deployment package..."
zip -r ../$OUTPUT_FILE . -x "*.git*" "spec/*" "*.md" "Gemfile.lock"

cd ..

# ビルドディレクトリをクリーンアップ
rm -rf $BUILD_DIR

echo "✅ Build complete! Output: $OUTPUT_FILE"
echo "📊 Package size: $(du -h $OUTPUT_FILE | cut -f1)"

# ファイルサイズが50MBを超える場合は警告
SIZE_IN_MB=$(du -m $OUTPUT_FILE | cut -f1)
if [ $SIZE_IN_MB -gt 50 ]; then
  echo "⚠️  Warning: Package size exceeds 50MB. Consider using Lambda Layers for dependencies."
fi