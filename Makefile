.PHONY: help setup start build-lambda deploy-local destroy-local test-api clean check-localstack-ready stop

# デフォルトターゲット
help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# 環境変数
LOCALSTACK_ENDPOINT ?= http://localhost:4566
LOCALSTACK_TIMEOUT ?= 60
LOCALSTACK_CHECK_INTERVAL ?= 3
AWS_REGION = ap-northeast-1
PROJECT_NAME = minutes-analyzer
ENVIRONMENT = local

# 初期セットアップ（OSS公開用）
setup: ## 初期セットアップを実行
	@./scripts/setup.sh

# 開発環境起動（ビルド・デプロイ含む）
start: ## 開発環境を起動・デプロイ
	@echo "🚀 開発環境を起動中..."
	@export $(cat .env.local | grep -v '^#' | xargs) && \
	cd infrastructure && docker compose up -d
	$(MAKE) wait-for-localstack
	$(MAKE) build-lambda
	$(MAKE) deploy-local
	@echo "✅ 開発環境の起動が完了しました"

# LocalStack環境のセットアップ
setup-local: ## LocalStack環境をセットアップ
	@echo "🚀 LocalStack環境をセットアップ中..."
	@if [ ! -f .env.local ]; then \
		echo "❌ .env.localファイルが見つかりません。make setup を最初に実行してください。"; \
		exit 1; \
	fi
	@export $(cat .env.local | grep -v '^#' | xargs) && \
	docker compose -f $(DOCKER_COMPOSE_FILE) --profile dev up -d
	$(MAKE) wait-for-localstack
	@echo "✅ LocalStackが起動しました: $(LOCALSTACK_ENDPOINT)"

# LocalStackの状態確認
check-localstack: ## LocalStackの状態を確認
	@echo "🔍 LocalStackの状態を確認中..."
	@curl -sf $(LOCALSTACK_ENDPOINT)/_localstack/health || (echo "❌ LocalStackに接続できません" && exit 1)

## LocalStackの起動を待機
wait-for-localstack: ## LocalStackの起動を待機
	@echo "⏳ LocalStackの起動を待機中..."
	@timeout=60; \
	while [ $$timeout -gt 0 ]; do \
		if curl -sf $(LOCALSTACK_ENDPOINT)/_localstack/health > /dev/null 2>&1; then \
			echo "✅ LocalStackが起動しました"; \
			exit 0; \
		fi; \
		echo "LocalStack起動待機中... (残り $${timeout}秒)"; \
		sleep 3; \
		timeout=$$((timeout - 3)); \
	done; \
	echo "❌ LocalStackの起動がタイムアウトしました"; \
	exit 1

# Lambda関数のビルド
build-lambda: ## Lambda関数をビルド
	@echo "🔨 Lambda関数をビルド中..."
	@cd lambda && bundle install --deployment --without development test
	@cd lambda && zip -qr ../infrastructure/modules/lambda/lambda.zip . -x "spec/*" "*.git*" "Makefile"
	@echo "✅ Lambda関数のビルドが完了しました"

tf-init: ## Terraformを初期化
	@echo "Terraform初期化中..."
	@if [ ! -f $(TF_DIR)/.terraform.lock.hcl ]; then \
		cd $(TF_DIR) && terraform init; \
	else \
		echo "Terraformは既に初期化されています"; \
	fi
	@echo "Terraformの初期化が完了しました"

# Terraformプランの実行
tf-plan: tf-init ## Terraformプランを実行
	@echo "📋 Terraformプランを実行中..."
	@cd infrastructure/environments/local && terraform plan
	@echo "✅ Terraformプランが完了しました"

# LocalStack環境にデプロイ
deploy-local: build-lambda tf-plan ## LocalStack環境にデプロイ
	@echo "🚀 LocalStack環境にデプロイ中..."
	@cd infrastructure/environments/local && terraform apply -auto-approve
	@echo "✅ デプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd infrastructure/environments/local && terraform output

# LocalStack環境を破棄
destroy-local: ## LocalStack環境を破棄
	@echo "🗑️  LocalStack環境を破棄中..."
	@cd infrastructure/environments/local && terraform destroy -auto-approve
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



# ローカル環境のクリーンアップ
clean: ## ローカル環境をクリーンアップ
	@echo "🧹 ローカル環境をクリーンアップ中..."
	docker compose -f docker-compose.yml down -v
	@rm -f infrastructure/modules/lambda/lambda.zip
	@cd infrastructure/environments/local && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup terraform.tfvars
	@echo "✅ クリーンアップが完了しました"

# 開発環境の完全セットアップ
dev-setup: setup-local deploy-local test-api ## 開発環境を完全にセットアップ
	@echo "🎉 開発環境のセットアップが完了しました！"
	@echo ""
	@echo "📋 利用可能な情報:"
	@cd infrastructure/environments/local && \
	echo "API エンドポイント: $$(terraform output -raw api_endpoint_url 2>/dev/null || echo 'N/A')" && \
	echo "API キー: $$(terraform output -raw api_key_value 2>/dev/null || echo 'N/A')"
	@echo ""
	@echo "📋 次のステップ:"
	@echo "• テスト実行: make test"
	@echo "• 環境停止: make stop"

# 開発環境停止
stop: ## 開発環境を停止
	@echo "開発環境を停止中..."
	@if [ ! -f .env.local ]; then \
		echo "WARNING: .env.localファイルが見つかりません。make setup を最初に実行してください。"; \
		echo "Docker Composeサービスを直接停止します..."; \
		docker compose -f $(DOCKER_COMPOSE_FILE) down 2>/dev/null || true; \
	else \
		export $$(cat .env.local | grep -v '^#' | xargs) && \
		docker compose -f $(DOCKER_COMPOSE_FILE) down; \
	fi
	@echo "開発環境が停止しました"

# 実際のLambda関数のテスト実行
test-lambda-local: ## Lambda関数をローカルでテスト
	@echo "🧪 Lambda関数をローカルでテスト中..."
	@cd lambda && ruby -r './src/lambda_function.rb' -e 'puts lambda_handler(event: {"body": "{\"transcript\":\"テスト会議です\"}"}, context: OpenStruct.new(aws_request_id: "test-123"))'

# 総合テスト
test: test-api test-lambda-local ## 全てのテストを実行

# AWS本番環境用のコマンド
deploy-production: ## 本番環境にデプロイ
	@echo "🚀 本番環境にデプロイ中..."
	@echo "⚠️  本番環境のデプロイは infrastructure/environments/production/ で設定してください"
	@echo "📖 詳細は docs/architecture.md を参照してください"
