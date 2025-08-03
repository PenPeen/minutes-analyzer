FROM ruby:3.2-alpine

# 必要なパッケージを事前にインストール
RUN apk add --no-cache \
    zip \
    unzip \
    build-base \
    git

# bundlerをインストール
RUN gem install bundler

WORKDIR /app

# エントリーポイントスクリプト
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
