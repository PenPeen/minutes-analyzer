.PHONY: help setup test deploy clean

# 色定義
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# 環境変数
ENVIRONMENT ?= development
AWS_REGION ?= ap-northeast-1

help: ## ヘルプを表示
	@echo "$(BLUE)Drive Selector - Make Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

setup: ## 初期セットアップ
	@echo "$(YELLOW)Setting up development environment...$(NC)"
	cd lambda && bundle install
	@echo "$(GREEN)✓ Setup completed$(NC)"

test: ## テスト実行
	@echo "$(YELLOW)Running tests...$(NC)"
	cd lambda && bundle exec rspec
	@echo "$(GREEN)✓ Tests completed$(NC)"

test-integration: ## 統合テスト実行
	@echo "$(YELLOW)Running integration tests...$(NC)"
	cd lambda && bundle exec rspec spec/integration/
	@echo "$(GREEN)✓ Integration tests completed$(NC)"

test-coverage: ## カバレッジ付きテスト実行
	@echo "$(YELLOW)Running tests with coverage...$(NC)"
	cd lambda && bundle exec rspec --format documentation
	@echo "$(GREEN)✓ Coverage report generated: lambda/coverage/index.html$(NC)"

lint: ## コードのLint実行
	@echo "$(YELLOW)Running RuboCop...$(NC)"
	cd lambda && bundle exec rubocop
	@echo "$(GREEN)✓ Lint completed$(NC)"

build: ## Lambda関数のビルド
	@echo "$(YELLOW)Building Lambda deployment package...$(NC)"
	cd lambda && \
		rm -rf vendor && \
		bundle config set --local deployment true && \
		bundle install && \
		zip -r ../lambda.zip . -x "*.git*" -x "spec/*" -x "coverage/*" -x ".rspec"
	@echo "$(GREEN)✓ Build completed: lambda.zip$(NC)"

deploy-dev: build ## 開発環境へデプロイ
	@echo "$(YELLOW)Deploying to development environment...$(NC)"
	cd infrastructure && \
		terraform init && \
		terraform workspace select development || terraform workspace new development && \
		terraform apply -var="environment=development" -auto-approve
	@echo "$(GREEN)✓ Deployment completed$(NC)"

deploy-staging: build ## ステージング環境へデプロイ
	@echo "$(YELLOW)Deploying to staging environment...$(NC)"
	cd infrastructure && \
		terraform init && \
		terraform workspace select staging || terraform workspace new staging && \
		terraform apply -var="environment=staging"
	@echo "$(GREEN)✓ Deployment completed$(NC)"

deploy-production: build ## 本番環境へデプロイ
	@echo "$(RED)WARNING: Deploying to PRODUCTION!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && \
		[ "$$confirm" = "yes" ] || exit 1
	cd infrastructure && \
		terraform init && \
		terraform workspace select production || terraform workspace new production && \
		terraform apply -var="environment=production"
	@echo "$(GREEN)✓ Production deployment completed$(NC)"

test-e2e: ## E2Eテスト実行
	@echo "$(YELLOW)Running E2E tests...$(NC)"
	@if [ -z "$(API_GATEWAY_URL)" ]; then \
		echo "$(RED)Error: API_GATEWAY_URL is not set$(NC)"; \
		echo "Run: export API_GATEWAY_URL=https://xxx.execute-api.region.amazonaws.com/stage"; \
		exit 1; \
	fi
	./test/e2e_test.sh
	@echo "$(GREEN)✓ E2E tests completed$(NC)"

logs: ## CloudWatchログを表示
	@echo "$(YELLOW)Tailing CloudWatch logs...$(NC)"
	aws logs tail /aws/lambda/drive-selector-controller-$(ENVIRONMENT) --follow

clean: ## クリーンアップ
	@echo "$(YELLOW)Cleaning up...$(NC)"
	rm -f lambda.zip
	rm -rf lambda/vendor
	rm -rf lambda/coverage
	rm -f lambda/.bundle/config
	@echo "$(GREEN)✓ Cleanup completed$(NC)"

destroy-dev: ## 開発環境を削除
	@echo "$(RED)WARNING: Destroying development environment!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm && \
		[ "$$confirm" = "yes" ] || exit 1
	cd infrastructure && \
		terraform workspace select development && \
		terraform destroy -var="environment=development" -auto-approve
	@echo "$(GREEN)✓ Development environment destroyed$(NC)"

# シークレット管理
update-secrets: ## シークレットを更新
	@echo "$(YELLOW)Updating secrets for $(ENVIRONMENT)...$(NC)"
	./scripts/update_secrets.sh $(ENVIRONMENT) --all

show-secrets: ## シークレットを表示（マスク済み）
	@echo "$(YELLOW)Showing secrets for $(ENVIRONMENT)...$(NC)"
	./scripts/update_secrets.sh $(ENVIRONMENT) --show

# API Gateway管理  
test-api: ## API Gatewayのテスト
	@echo "$(YELLOW)Testing API Gateway endpoints...$(NC)"
	./scripts/test_api_gateway.sh

get-endpoints: ## API Gatewayエンドポイントを取得
	@echo "$(YELLOW)Getting API Gateway endpoints...$(NC)"
	@cd infrastructure && \
		terraform output -json | jq -r '.slack_command_endpoint.value' && \
		terraform output -json | jq -r '.slack_interactions_endpoint.value'

# ローカル開発
run-local: ## ローカルでLambda関数を実行（要SAM CLI）
	@echo "$(YELLOW)Starting local Lambda...$(NC)"
	sam local start-api --template infrastructure/sam-template.yaml

# ドキュメント
docs: ## ドキュメントを開く
	@echo "$(YELLOW)Opening documentation...$(NC)"
	open README.md

# 統計情報
stats: ## コード統計を表示
	@echo "$(BLUE)Code Statistics:$(NC)"
	@echo "Ruby files:"
	@find lambda -name "*.rb" | wc -l
	@echo "Lines of code:"
	@find lambda -name "*.rb" -exec cat {} \; | wc -l
	@echo "Test files:"
	@find lambda/spec -name "*_spec.rb" | wc -l

# 依存関係の更新
update-deps: ## Gemの更新
	@echo "$(YELLOW)Updating dependencies...$(NC)"
	cd lambda && bundle update
	@echo "$(GREEN)✓ Dependencies updated$(NC)"

# セキュリティチェック
security-check: ## セキュリティ脆弱性チェック
	@echo "$(YELLOW)Checking for security vulnerabilities...$(NC)"
	cd lambda && bundle audit check
	@echo "$(GREEN)✓ Security check completed$(NC)"

.DEFAULT_GOAL := help