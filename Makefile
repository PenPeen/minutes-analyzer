MAKEFLAGS += --silent
.PHONY: help setup start build-lambda deploy-local destroy-local clean check-localstack-ready stop

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
	@export $$(cat .env.local | grep -v '^#' | xargs) && \
	cd infrastructure && docker compose up -d
	@$(MAKE) wait-for-localstack
	@$(MAKE) build-lambda
	@$(MAKE) deploy-local
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
		printf "."; \
		sleep 3; \
		timeout=$$((timeout - 3)); \
	done; \
	echo "❌ LocalStackの起動がタイムアウトしました"; \
	exit 1

build-lambda: ## Lambda関数をビルド
	@echo "🔨 Lambda関数をビルド中..."
	@mkdir -p infrastructure/modules/lambda
	@docker compose run --rm ruby-lambda-builder
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
deploy-local: tf-plan ## LocalStack環境にデプロイ
	@echo "🚀 LocalStack環境にデプロイ中..."
	@if [ -f infrastructure/environments/local/.env.tfvars ]; then \
		cd infrastructure/environments/local && terraform apply -var-file=".env.tfvars" -auto-approve; \
	else \
		cd infrastructure/environments/local && terraform apply -auto-approve; \
	fi
	@echo "✅ デプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd infrastructure/environments/local && terraform output

# LocalStack環境を破棄
destroy-local: ## LocalStack環境を破棄
	@echo "🗑️  LocalStack環境を破棄中..."
	@cd infrastructure/environments/local && terraform destroy -auto-approve
	@echo "✅ 環境の破棄が完了しました"



# 簡単なヘルスチェック
health-check: ## APIヘルスチェック
	@echo "❤️  APIヘルスチェック中..."
	@API_URL=$$(cd infrastructure/environments/local && terraform output -raw api_gateway_url); \
	curl -s "$$API_URL/health" -w "\nHTTP Status: %{http_code}\n" || echo "ヘルスチェックに失敗しました"



# ローカル環境のクリーンアップ
clean:
	@echo "🧹 ローカル環境をクリーンアップ中..."
	docker compose -f docker-compose.yml down -v
	@rm -f infrastructure/modules/lambda/lambda.zip
	@cd infrastructure/environments/local && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup terraform.tfvars
	@echo "✅ クリーンアップが完了しました"

# Lambda関数をビルド・デプロイする完全なタスク
build-and-deploy: build-lambda deploy-local ## Lambda関数をビルドしてデプロイ
	@echo "🎉 ビルドとデプロイが完了しました！"

# 開発環境の完全セットアップ
dev-setup: setup-local build-and-deploy ## 開発環境を完全にセットアップ
	@echo "🎉 開発環境のセットアップが完了しました！"
	@echo ""
	@echo "📋 利用可能な情報:"
	@cd infrastructure/environments/local && \
	echo "API エンドポイント: $$(terraform output -raw api_endpoint_url 2>/dev/null || echo 'N/A')" && \
	echo "API キー: $$(terraform output -raw api_key_value 2>/dev/null || echo 'N/A')"
	@echo ""
	@echo "📋 次のステップ:"
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



# AWS本番環境用のコマンド
deploy-production: ## 本番環境にデプロイ
	@echo "🚀 本番環境にデプロイ中..."
	@if [ ! -f infrastructure/environments/production/terraform.tfvars ]; then \
		echo "❌ Error: Please create terraform.tfvars from terraform.tfvars.sample"; \
		echo "  cp infrastructure/environments/production/terraform.tfvars.sample infrastructure/environments/production/terraform.tfvars"; \
		echo "  Then edit the file with your production values"; \
		exit 1; \
	fi
	@if [ ! -f infrastructure/environments/production/.env.tfvars ]; then \
		echo "❌ Error: Please create .env.tfvars from .env.tfvars.sample"; \
		echo "  cp infrastructure/environments/production/.env.tfvars.sample infrastructure/environments/production/.env.tfvars"; \
		echo "  Then edit the file with your sensitive values (Slack webhook URL, etc.)"; \
		exit 1; \
	fi
	@cd infrastructure/environments/production && \
		terraform init && \
		terraform plan -var-file=".env.tfvars" && \
		echo "⚠️  Review the plan above. Press Enter to continue or Ctrl+C to cancel..." && \
		read && \
		terraform apply -var-file=".env.tfvars"
	@echo "✅ 本番環境へのデプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd infrastructure/environments/production && terraform output
