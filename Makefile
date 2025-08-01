.PHONY: help setup build-lambda deploy-local destroy-local test-api clean logs

# デフォルトターゲット
help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# 環境変数
LOCALSTACK_ENDPOINT = http://localhost:4566
AWS_REGION = ap-northeast-1
PROJECT_NAME = minutes-analyzer
ENVIRONMENT = local

# 初期セットアップ（OSS公開用）
setup: ## 初期セットアップを実行
	@./scripts/setup.sh

# LocalStack環境のセットアップ
setup-local: ## LocalStack環境をセットアップ
	@echo "🚀 LocalStack環境をセットアップ中..."
	@if [ ! -f .env.local ]; then \
		echo "❌ .env.localファイルが見つかりません。make setup を最初に実行してください。"; \
		exit 1; \
	fi
	@export $$(cat .env.local | grep -v '^#' | xargs) && \
	docker-compose -f infrastructure/docker-compose.yml up -d localstack
	@echo "⏳ LocalStackの起動を待機中..."
	@sleep 10
	@echo "✅ LocalStackが起動しました: $(LOCALSTACK_ENDPOINT)"

# LocalStackの状態確認
check-localstack: ## LocalStackの状態を確認
	@echo "🔍 LocalStackの状態を確認中..."
	@curl -s $(LOCALSTACK_ENDPOINT)/health | jq . || echo "❌ LocalStackに接続できません"

# Lambda関数のビルド
build-lambda: ## Lambda関数をビルド
	@echo "🔨 Lambda関数をビルド中..."
	@cd lambda && bundle install --deployment --without development test
	@cd lambda && zip -r ../infrastructure/modules/lambda/lambda.zip . -x "spec/*" "*.git*" "Makefile"
	@echo "✅ Lambda関数のビルドが完了しました"

# Terraformの初期化
tf-init: ## Terraformを初期化
	@echo "🏗️  Terraform初期化中..."
	@cd infrastructure/environments/local && terraform init
	@echo "✅ Terraformの初期化が完了しました"

# Terraformプランの実行
tf-plan: tf-init ## Terraformプランを実行
	@echo "📋 Terraformプランを実行中..."
	@cd infrastructure/environments/local && \
	export TF_VAR_gemini_api_key="$${GEMINI_API_KEY}" && \
	export TF_VAR_slack_error_webhook_url="$${SLACK_ERROR_WEBHOOK_URL}" && \
	terraform plan
	@echo "✅ Terraformプランが完了しました"

# LocalStack環境にデプロイ
deploy-local: build-lambda tf-plan ## LocalStack環境にデプロイ
	@echo "🚀 LocalStack環境にデプロイ中..."
	@cd infrastructure/environments/local && \
	export TF_VAR_gemini_api_key="$${GEMINI_API_KEY}" && \
	export TF_VAR_slack_error_webhook_url="$${SLACK_ERROR_WEBHOOK_URL}" && \
	terraform apply -auto-approve
	@echo "✅ デプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd infrastructure/environments/local && terraform output

# LocalStack環境を破棄
destroy-local: ## LocalStack環境を破棄
	@echo "🗑️  LocalStack環境を破棄中..."
	@cd infrastructure/environments/local && \
	export TF_VAR_gemini_api_key="$${GEMINI_API_KEY}" && \
	export TF_VAR_slack_error_webhook_url="$${SLACK_ERROR_WEBHOOK_URL}" && \
	terraform destroy -auto-approve
	@echo "✅ 環境の破棄が完了しました"

# APIのテスト
test-api: ## APIエンドポイントをテスト
	@echo "🧪 APIをテスト中..."
	@API_URL=$$(cd infrastructure/environments/local && terraform output -raw api_endpoint_url); \
	API_KEY=$$(cd infrastructure/environments/local && terraform output -raw api_key_value); \
	echo "API URL: $$API_URL"; \
	echo "テスト実行中..."; \
	curl -X POST "$$API_URL" \
		-H "Content-Type: application/json" \
		-H "x-api-key: $$API_KEY" \
		-d '{"transcript":"これはテスト用の会議文字起こしです。新機能のリリース日を来月15日に決定します。","metadata":{"participants":["田中","佐藤"],"duration":1800}}' \
		-w "\n\nHTTP Status: %{http_code}\n" \
		| jq . || echo "JSON解析に失敗しました"

# 簡単なヘルスチェック
health-check: ## APIヘルスチェック
	@echo "❤️  APIヘルスチェック中..."
	@API_URL=$$(cd infrastructure/environments/local && terraform output -raw api_gateway_url); \
	curl -s "$$API_URL/health" -w "\nHTTP Status: %{http_code}\n" || echo "ヘルスチェックに失敗しました"

# ログの確認
logs: ## CloudWatchログを確認（LocalStack）
	@echo "📋 ログを確認中..."
	@LOG_GROUP=$$(cd infrastructure/environments/local && terraform output -raw lambda_log_group_name); \
	aws --endpoint-url=$(LOCALSTACK_ENDPOINT) logs describe-log-streams \
		--log-group-name "$$LOG_GROUP" \
		--region $(AWS_REGION) || echo "ログの取得に失敗しました"

# ローカル環境のクリーンアップ
clean: ## ローカル環境をクリーンアップ
	@echo "🧹 ローカル環境をクリーンアップ中..."
	docker-compose -f infrastructure/docker-compose.yml down -v
	@rm -f infrastructure/modules/lambda/lambda.zip
	@cd infrastructure/environments/local && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
	@echo "✅ クリーンアップが完了しました"

# 開発環境の完全セットアップ
dev-setup: setup-local deploy-local test-api ## 開発環境を完全にセットアップ
	@echo "🎉 開発環境のセットアップが完了しました！"
	@echo ""
	@echo "📋 利用可能な情報："
	@cd infrastructure/environments/local && \
	echo "API エンドポイント: $$(terraform output -raw api_endpoint_url 2>/dev/null || echo 'N/A')" && \
	echo "API キー: $$(terraform output -raw api_key_value 2>/dev/null || echo 'N/A')"
	@echo ""
	@echo "📋 次のステップ："
	@echo "• テスト実行: make test-api"
	@echo "• ログ確認: make logs"
	@echo "• 環境停止: make clean"

# 実際のLambda関数のテスト実行
test-lambda-local: ## Lambda関数をローカルでテスト
	@echo "🧪 Lambda関数をローカルでテスト中..."
	@cd lambda && ruby -r './src/lambda_function.rb' -e 'puts lambda_handler(event: {"body": "{\"transcript\":\"テスト会議です\"}"}, context: OpenStruct.new(aws_request_id: "test-123"))'

# AWS本番環境用のコマンド
deploy-production: ## 本番環境にデプロイ
	@echo "🚀 本番環境にデプロイ中..."
	@echo "⚠️  本番環境のデプロイは infrastructure/environments/production/ で設定してください"
	@echo "📖 詳細は docs/architecture.md を参照してください"
