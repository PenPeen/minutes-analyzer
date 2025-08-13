# AWS Lambda Ruby 3.2ランタイムを使用
# このイメージはLambda環境と同じ依存関係を持つ
FROM public.ecr.aws/lambda/ruby:3.2

# 必要なパッケージを事前にインストール
RUN yum update -y && \
    yum install -y \
    zip \
    unzip \
    gcc \
    make \
    git && \
    yum clean all

# bundlerをインストール
RUN gem install bundler

# Lambda関数のコード配置先を設定
# /var/taskはLambdaランタイムが期待するディレクトリ
WORKDIR /var/task

# エントリーポイントスクリプト
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]