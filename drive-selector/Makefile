MAKEFLAGS += --silent
.PHONY: help setup build clean test deploy tf-plan tf-apply destroy

# デフォルトターゲット
help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# 環境変数
AWS_REGION ?= ap-northeast-1
PROJECT_NAME = drive-selector
ENVIRONMENT = production
BUILD_DIR = build
LAMBDA_DIR = lambda
OUTPUT_FILE = lambda.zip
TF_DIR = infrastructure

# セットアップ
setup: ## 初期セットアップを実行
	@echo "📋 Slack Bot Drive Selector 初期セットアップ"
	@if [ -f .env.local ]; then \
		echo "📋 .env.localは既に存在します"; \
	else \
		echo "⚠️  .env.localファイルを作成してください"; \
		echo "    詳細は README.md を参照してください"; \
	fi
	@echo "📦 Ruby依存関係をインストール中..."
	@if command -v bundle >/dev/null 2>&1; then \
		cd $(LAMBDA_DIR) && bundle install; \
	else \
		echo "⚠️  Bundlerがインストールされていません。Rubyの依存関係はスキップします"; \
	fi
	@echo "✅ セットアップが完了しました"

# Lambda関数のビルド（共通）
build: ## Lambda関数のデプロイパッケージをビルド
	@echo "🔨 Lambda関数をビルド中..."
	@mkdir -p infrastructure/modules/lambda
	@docker compose run --rm ruby-lambda-builder
	@if [ -f infrastructure/modules/lambda/lambda.zip ]; then \
		cp infrastructure/modules/lambda/lambda.zip $(OUTPUT_FILE); \
		echo "✅ Lambda関数のビルドが完了しました"; \
		echo "📊 Package size: $$(du -h $(OUTPUT_FILE) | cut -f1)"; \
		SIZE_IN_MB=$$(du -m $(OUTPUT_FILE) | cut -f1); \
		if [ $$SIZE_IN_MB -gt 50 ]; then \
			echo "⚠️  Warning: Package size exceeds 50MB. Consider using Lambda Layers for dependencies."; \
		fi; \
	else \
		echo "❌ ビルドに失敗しました"; \
		exit 1; \
	fi

# テスト実行
test: ## テストを実行
	@echo "🧪 テストを実行中..."
	@cd $(LAMBDA_DIR) && \
		bundle config set --local path 'vendor/bundle' && \
		bundle install --quiet && \
		bundle exec rspec spec/ --format documentation
	@echo "✅ テストが完了しました"

# Terraformの初期化
tf-init: ## Terraformを初期化
	@echo "🏗️  Terraform初期化中..."
	@if [ ! -f $(TF_DIR)/.terraform.lock.hcl ]; then \
		cd $(TF_DIR) && terraform init; \
	else \
		echo "Terraformは既に初期化されています"; \
	fi
	@echo "✅ Terraformの初期化が完了しました"

# Terraformプランの実行
tf-plan: tf-init ## Terraformプランを実行
	@echo "📋 Terraformプランを実行中..."
	@if [ ! -f $(TF_DIR)/terraform.production.tfvars ]; then \
		echo "❌ terraform.production.tfvarsが見つかりません"; \
		echo "  infrastructure/terraform.production.tfvars を作成してください"; \
		exit 1; \
	fi
	@cd $(TF_DIR) && terraform plan -var-file=terraform.production.tfvars
	@echo "✅ Terraformプランが完了しました"

# Terraform適用
tf-apply: tf-init ## Terraformを適用
	@echo "🚀 Terraformを適用中..."
	@if [ ! -f $(TF_DIR)/terraform.production.tfvars ]; then \
		echo "❌ terraform.production.tfvarsが見つかりません"; \
		echo "  infrastructure/terraform.production.tfvars を作成してください"; \
		exit 1; \
	fi
	@cd $(TF_DIR) && terraform apply -var-file=terraform.production.tfvars
	@echo "✅ Terraformの適用が完了しました"

# デプロイ
deploy: build ## 本番環境にデプロイ
	@echo "🚀 本番環境にデプロイ中..."
	@if [ ! -f $(TF_DIR)/terraform.production.tfvars ]; then \
		echo "❌ terraform.production.tfvarsが見つかりません"; \
		echo "  infrastructure/terraform.production.tfvars を作成してください"; \
		exit 1; \
	fi
	@$(MAKE) tf-plan
	@echo "⚠️  上記のプランを確認してください。Enterキーで続行、Ctrl+Cでキャンセル..."
	@read
	@$(MAKE) tf-apply
	@echo "✅ 本番環境へのデプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd $(TF_DIR) && terraform output

# 環境破棄
destroy: ## 本番環境を破棄（要確認）
	@echo "⚠️  本番環境を破棄しようとしています！"
	@echo "本当に実行しますか？ 'yes' と入力してください:"
	@read confirm && [ "$$confirm" = "yes" ] || (echo "キャンセルしました" && exit 1)
	@echo "🗑️  本番環境を破棄中..."
	@cd $(TF_DIR) && terraform destroy -var-file=terraform.production.tfvars -auto-approve
	@echo "✅ 本番環境の破棄が完了しました"

# クリーンアップ
clean: clean-build clean-terraform ## 全てをクリーンアップ

clean-build: ## ビルド成果物をクリーンアップ
	@echo "🧹 ビルド成果物をクリーンアップ中..."
	@rm -rf $(BUILD_DIR)
	@rm -f $(OUTPUT_FILE)
	@rm -f $(LAMBDA_DIR)/Gemfile.lock
	@cd $(LAMBDA_DIR) && rm -rf vendor/ .bundle/

clean-terraform: ## Terraform状態をクリーンアップ
	@echo "🏗️  Terraform状態をクリーンアップ中..."
	@cd $(TF_DIR) && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup

# ヘルスチェック（本番・開発環境対応）
health-check: ## APIヘルスチェック
	@echo "❤️  APIヘルスチェック中..."
	@if [ -f $(TF_DIR)/terraform.tfstate ]; then \
		API_URL=$$(cd $(TF_DIR) && terraform output -raw api_gateway_url 2>/dev/null); \
		if [ -n "$$API_URL" ]; then \
			curl -s "$$API_URL/health" -w "\nHTTP Status: %{http_code}\n" || echo "ヘルスチェックに失敗しました"; \
		else \
			echo "API URLが取得できませんでした"; \
		fi; \
	else \
		echo "デプロイされていません。まず 'make deploy-local' または 'make deploy-production' を実行してください"; \
	fi

# ログ確認
logs: ## Lambda関数のログを表示
	@echo "📜 Lambda関数のログを確認中..."
	@aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$(PROJECT_NAME)" --query 'logGroups[0].logGroupName' --output text | \
	xargs -I {} aws logs tail {} --follow

# 開発サーバー（ローカルテスト用）
dev-server: ## 開発用サーバーを起動（ローカルテスト用）
	@echo "🚀 開発サーバーを起動中..."
	@cd $(LAMBDA_DIR) && \
		bundle install && \
		ruby -r './handler.rb' -e "puts 'Development server ready. Use for local testing.'"