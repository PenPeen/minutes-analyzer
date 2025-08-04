MAKEFLAGS += --silent
.PHONY: help setup start build-lambda deploy-local destroy-local clean check-localstack-ready stop test test-lambda

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

# LocalStack AWS設定
AWS_ENDPOINT_FLAG = --endpoint-url=$(LOCALSTACK_ENDPOINT)
AWS_LOCAL_CREDENTIALS = AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test

# 初期セットアップ（OSS公開用）
setup: ## 初期セットアップを実行
	@if [ -f .env.local ]; then \
		echo "📋 .env.localは既に存在するため、スキップします"; \
	else \
		./scripts/setup.sh; \
	fi

# 開発環境起動（ビルド・デプロイ含む）
start: ## 開発環境を起動・デプロイ
	@echo "🚀 開発環境を起動中..."
	@if [ ! -f .env.local ]; then \
		echo "❌ .env.localが見つかりません。make setup を最初に実行してください。"; \
		exit 1; \
	fi
	@export $$(cat .env.local | grep -v '^#' | xargs) && \
	cd infrastructure && docker compose up -d
	@$(MAKE) wait-for-localstack
	@$(MAKE) generate-tfvars
	@$(MAKE) build-lambda
	@$(MAKE) deploy-local
	@echo "✅ 開発環境の起動が完了しました"

# terraform.tfvarsの生成
generate-tfvars: ## terraform.tfvarsを.env.localから生成
	@echo "📝 terraform.tfvarsを生成中..."
	@if [ -f .env.local ]; then \
		( \
			echo "# .env.localから自動生成されるTerraform変数ファイル"; \
			echo "gemini_api_key=\"$$(grep GEMINI_API_KEY .env.local | cut -d '=' -f2-)\""; \
			echo "slack_webhook_url=\"$$(grep SLACK_WEBHOOK_URL .env.local | cut -d '=' -f2-)\""; \
			echo "notion_api_key=\"$$(grep NOTION_API_KEY .env.local | cut -d '=' -f2-)\""; \
			echo "notion_database_id=\"$$(grep NOTION_DATABASE_ID .env.local | cut -d '=' -f2-)\""; \
			echo "notion_task_database_id=\"$$(grep NOTION_TASK_DATABASE_ID .env.local | cut -d '=' -f2-)\""; \
		) > infrastructure/environments/local/terraform.tfvars; \
		echo "✅ terraform.tfvarsを生成しました"; \
	else \
		echo "❌ .env.localが見つかりません。make setup を最初に実行してください。"; \
		exit 1; \
	fi

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
	@if [ -f infrastructure/environments/local/terraform.tfvars ]; then \
		cd infrastructure/environments/local && terraform apply -var-file="terraform.tfvars" -auto-approve; \
	else \
		cd infrastructure/environments/local && terraform apply -auto-approve; \
	fi
	@echo "✅ デプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd infrastructure/environments/local && terraform output
	@$(MAKE) upload-prompts-local

# プロンプトをS3にアップロード
upload-prompts-local: ## プロンプトファイルをLocalStackのS3にアップロード
	@echo "📤 プロンプトファイルをS3にアップロード中..."
	@$(AWS_LOCAL_CREDENTIALS) ./scripts/upload_prompts_to_s3.sh local
	@echo "✅ プロンプトのアップロードが完了しました"

# LocalStack環境を破棄
destroy-local: ## LocalStack環境を破棄
	@echo "🗑️  LocalStack環境を破棄中..."
	@cd infrastructure/environments/local && terraform destroy -auto-approve
	@echo "✅ 環境の破棄が完了しました"

# テスト実行
test: test-lambda

test-lambda:
	@echo "🧪 Lambda関数のテストを実行中..."
	@docker compose run --rm --entrypoint="" ruby-lambda-builder sh -c "cd /app && bundle install --quiet && bundle exec rspec spec/ --format documentation"
	@echo "✅ テストが完了しました"

# 簡単なヘルスチェック
health-check: ## APIヘルスチェック
	@echo "❤️  APIヘルスチェック中..."
	@API_URL=$$(cd infrastructure/environments/local && terraform output -raw api_gateway_url); \
	curl -s "$$API_URL/health" -w "\nHTTP Status: %{http_code}\n" || echo "ヘルスチェックに失敗しました"

# ローカル環境のクリーンアップ
clean:
	@echo "🧹 ローカル環境をクリーンアップ中..."
	@$(MAKE) clean-docker
	@$(MAKE) clean-build-artifacts
	@$(MAKE) clean-terraform
	@$(MAKE) clean-config
	@echo "✅ 完全クリーンアップが完了しました"

clean-docker:
	@echo "🐳 Docker環境をクリーンアップ中..."
	@docker compose -f docker-compose.yml down -v --rmi local
	@docker system prune -f

clean-build-artifacts:
	@echo "🗂️  ビルド成果物を削除中..."
	@rm -f infrastructure/modules/lambda/lambda.zip
	@rm -f lambda/Gemfile.lock
	@rm -rf logs/ tmp/

clean-terraform:
	@echo "🏗️  Terraform状態を削除中..."
	@cd infrastructure/environments/local && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup terraform.tfvars .env.tfvars

clean-config:
	@echo "⚙️  設定ファイルを削除中..."
	@rm -f .env.local .env.production

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
