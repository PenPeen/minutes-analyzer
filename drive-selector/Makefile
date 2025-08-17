MAKEFLAGS += --silent
.PHONY: help setup build clean test deploy-production destroy-production clean-production build-lambda tf-init tf-plan tf-apply generate-production-tfvars ensure-terraform-backend-bucket health-check logs check-resources terraform-fmt-production terraform-validate-production

# デフォルトターゲット
help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# 環境変数
AWS_REGION = ap-northeast-1
PROJECT_NAME = drive-selector
ENVIRONMENT = production
TF_DIR = infrastructure/environments/production

# セットアップ
setup: ## 初期セットアップを実行
	@echo "📋 Drive Selector 初期セットアップ"
	@if [ -f .env.production ]; then \
		echo "📋 .env.productionは既に存在します（保護されています）"; \
		echo "🔧 その他のセットアップを継続します..."; \
	else \
		echo "⚠️  .env.productionファイルを作成してください"; \
		echo "    詳細は README.md を参照してください"; \
	fi
	@echo "📦 依存関係をインストール中..."
	@if command -v bundle >/dev/null 2>&1; then \
		cd lambda && bundle install; \
	else \
		echo "⚠️  Bundlerがインストールされていません。Rubyの依存関係はスキップします"; \
	fi
	@echo "✅ セットアップが完了しました"

# 本番環境用ビルド
build-production: ## 本番環境用Lambda関数をビルド
	@echo "🔨 本番環境用Lambda関数をビルド中..."
	@mkdir -p infrastructure/modules/lambda
	@docker compose run --rm ruby-lambda-builder
	@echo "✅ 本番環境用ビルドが完了しました"

build-lambda: ## Lambda関数をビルド　（内部使用）
	@echo "🔨 Lambda関数をビルド中..."
	@mkdir -p infrastructure/modules/lambda
	@docker compose run --rm ruby-lambda-builder
	@echo "✅ Lambda関数のビルドが完了しました"


test: ## テストを実行
	@echo "🧪 Lambda関数のテストを実行中..."
	@docker compose run --rm --entrypoint="" ruby-lambda-builder sh -c "cd /var/task && bundle config unset without && bundle install --quiet && bundle exec rspec spec/ --format documentation"
	@echo "✅ テストが完了しました"

# 本番環境用Terraform初期化
tf-init-production: ensure-terraform-backend-bucket-production ## 本番環境用Terraformを初期化
	@echo "本番環境用Terraform初期化中..."
	@if [ ! -f $(TF_DIR)/.terraform.lock.hcl ]; then \
		cd $(TF_DIR) && terraform init; \
	else \
		echo "本番環境用Terraformは既に初期化されています"; \
	fi
	@echo "本番環境用Terraformの初期化が完了しました"

# 本番環境用Terraformプラン
tf-plan-production: tf-init-production generate-tfvars-production build-production ## 本番環境用Terraformプランを実行
	@echo "📋 本番環境用Terraformプランを実行中..."
	@if [ -f $(TF_DIR)/terraform.tfvars ]; then \
		cd $(TF_DIR) && terraform plan -var-file="terraform.tfvars"; \
	else \
		cd $(TF_DIR) && terraform plan; \
	fi
	@echo "✅ 本番環境用Terraformプランが完了しました"

# 本番環境用Terraform適用
tf-apply-production: ## 本番環境用Terraformを適用
	@echo "🚀 本番環境用Terraformを適用中..."
	@if [ -f $(TF_DIR)/terraform.tfvars ]; then \
		cd $(TF_DIR) && terraform apply -var-file="terraform.tfvars" -auto-approve; \
	else \
		cd $(TF_DIR) && terraform apply -auto-approve; \
	fi
	@echo "✅ 本番環境用Terraformの適用が完了しました"

deploy-production: ## 本番環境にデプロイ
	@echo "🚀 本番環境にデプロイ中..."
	@echo "⚠️  注意: 手動でAWSリソースを作成しないでください。すべてTerraformで管理されます。"
	@if [ ! -f .env.production ]; then \
		echo "❌ .env.productionが見つかりません。"; \
		echo "  本番環境用の設定ファイルを作成してください。"; \
		exit 1; \
	fi
	@$(MAKE) generate-tfvars-production
	@$(MAKE) ensure-terraform-backend-bucket-production
	@$(MAKE) build-production
	@cd $(TF_DIR) && \
		terraform init && \
		terraform plan -var-file="terraform.tfvars" && \
		echo "⚠️  Review the plan above. Press Enter to continue or Ctrl+C to cancel..." && \
		read && \
		terraform apply -var-file="terraform.tfvars"
	@echo "🔐 Secrets Managerにシークレットを設定中..."
	@./scripts/set-production-secrets.sh
	@echo "✅ 本番環境へのデプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd $(TF_DIR) && terraform output

# 本番環境用のterraform.tfvars生成
generate-tfvars-production: ## 本番環境用terraform.tfvarsを.env.productionから生成
	@echo "📝 本番環境用terraform.tfvarsを生成中..."
	@if [ -f .env.production ]; then \
		( \
			echo "# .env.productionから自動生成されるTerraform変数ファイル"; \
			echo "# 基本設定"; \
			echo "aws_region = \"ap-northeast-1\""; \
			echo "environment = \"production\""; \
			echo "project_name = \"drive-selector\""; \
			echo ""; \
			echo "# Lambda設定"; \
			echo "lambda_timeout = 30"; \
			echo "lambda_memory_size = 256"; \
			echo ""; \
			echo "# Slack設定 (from .env.production)"; \
			echo "slack_signing_secret=\"$$(grep SLACK_SIGNING_SECRET .env.production | cut -d '=' -f2-)\""; \
			echo "slack_bot_token=\"$$(grep SLACK_BOT_TOKEN .env.production | cut -d '=' -f2-)\""; \
			echo "slack_channel_id=\"$$(grep SLACK_CHANNEL_ID .env.production | cut -d '=' -f2-)\""; \
			echo ""; \
			echo "# Google OAuth設定 (from .env.production)"; \
			echo "google_client_id=\"$$(grep GOOGLE_CLIENT_ID .env.production | cut -d '=' -f2-)\""; \
			echo "google_client_secret=\"$$(grep GOOGLE_CLIENT_SECRET .env.production | cut -d '=' -f2-)\""; \
			echo ""; \
			echo "# Lambda ARN設定"; \
			echo "process_lambda_arn=\"$$(grep PROCESS_LAMBDA_ARN .env.production | cut -d '=' -f2-)\""; \
		) > $(TF_DIR)/terraform.tfvars; \
		echo "✅ terraform.tfvarsを生成しました"; \
	else \
		echo "❌ .env.productionが見つかりません。"; \
		exit 1; \
	fi

ensure-terraform-backend-bucket-production: ## 本番環境用Terraform backend S3バケットの存在確認・作成
	@echo "🪣 Terraform backend用S3バケットを確認中..."
	@BUCKET_NAME="drive-selector-terraform-state"; \
	if aws s3api head-bucket --bucket "$$BUCKET_NAME" --region ap-northeast-1 >/dev/null 2>&1; then \
		echo "✅ S3バケット '$$BUCKET_NAME' は既に存在します"; \
	else \
		echo "🔨 S3バケット '$$BUCKET_NAME' を作成中..."; \
		aws s3api create-bucket \
			--bucket "$$BUCKET_NAME" \
			--region ap-northeast-1 \
			--create-bucket-configuration LocationConstraint=ap-northeast-1; \
		echo "🔐 S3バケットの暗号化を設定中..."; \
		aws s3api put-bucket-encryption \
			--bucket "$$BUCKET_NAME" \
			--server-side-encryption-configuration '{ \
				"Rules": [{ \
					"ApplyServerSideEncryptionByDefault": { \
						"SSEAlgorithm": "AES256" \
					}, \
					"BucketKeyEnabled": true \
				}] \
			}'; \
		echo "🚫 S3バケットのパブリックアクセスをブロック中..."; \
		aws s3api put-public-access-block \
			--bucket "$$BUCKET_NAME" \
			--public-access-block-configuration \
				"BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"; \
		echo "✅ S3バケット '$$BUCKET_NAME' を作成しました"; \
	fi

destroy-production: ## 本番環境のリソースを削除
	@echo "🗑️  本番環境のリソースを削除中..."
	@if [ ! -f .env.production ]; then \
		echo "⚠️  .env.productionが見つかりません。terraform.tfvarsが既に存在する場合はそれを使用します。"; \
	else \
		$(MAKE) generate-tfvars-production; \
	fi
	@echo "🗑️  Terraformでリソースを削除中..."
	@cd $(TF_DIR) && \
		terraform destroy -auto-approve 2>/dev/null || true
	@echo "✅ 本番環境が削除されました"

clean-production: ## 本番環境の設定ファイルをクリーンアップ
	@echo "🧹 本番環境の設定ファイルをクリーンアップ中..."
	@cd $(TF_DIR) && \
		rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
	@rm -f $(TF_DIR)/terraform.tfvars
	@echo "✅ クリーンアップが完了しました"

# ローカル環境のクリーンアップ
clean: ## ローカル環境をクリーンアップ
	@echo "🧹 ローカル環境をクリーンアップ中..."
	@$(MAKE) clean-build-artifacts
	@$(MAKE) clean-terraform
	@echo "✅ クリーンアップが完了しました"

clean-build-artifacts:
	@echo "🗂️  ビルド成果物を削除中..."
	@rm -f infrastructure/modules/lambda/lambda.zip
	@rm -f lambda/Gemfile.lock
	@rm -rf logs/ tmp/

clean-terraform:
	@echo "🏗️  Terraform状態を削除中..."
	@cd $(TF_DIR) && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup terraform.tfvars

# 簡単なヘルスチェック
health-check: ## APIヘルスチェック
	@echo "❤️  APIヘルスチェック中..."
	@API_URL=$$(cd $(TF_DIR) && terraform output -raw api_gateway_url 2>/dev/null); \
	if [ -n "$$API_URL" ]; then \
		curl -s "$$API_URL/health" -w "\nHTTP Status: %{http_code}\n" || echo "ヘルスチェックに失敗しました"; \
	else \
		echo "API URLが取得できませんでした。デプロイ情報を確認してください。"; \
	fi

# ログ確認
logs: ## Lambda関数のログを表示
	@echo "📜 Lambda関数のログを確認中..."
	@aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$(PROJECT_NAME)" --query 'logGroups[0].logGroupName' --output text | \
	xargs -I {} aws logs tail {} --follow

# リソース状態確認
check-resources: ## AWSリソースとTerraform状態の整合性をチェック
	@echo "🔍 リソース状態を確認中..."
	@echo "📋 現在のAPI Gateway一覧:"
	@aws apigateway get-rest-apis --query 'items[].[id,name,endpointConfiguration.types[0]]' --output table
	@echo ""
	@echo "📋 Terraform管理下のリソース:"
	@cd $(TF_DIR) && terraform state list | grep -E "(api_gateway|lambda)" || echo "Terraform状態が見つかりません"
	@echo ""
	@echo "⚠️  手動で作成されたリソースがある場合は、Terraformでimportするか削除してください。"

# terraform検証コマンド（本番環境用）
terraform-fmt-production: ## 本番環境のTerraformファイルをフォーマット
	@echo "🔧 本番環境のTerraformファイルをフォーマット中..."
	@if [ ! -f $(TF_DIR)/.terraform.lock.hcl ]; then \
		echo "Terraformが初期化されていません。初期化を実行します..."; \
		$(MAKE) ensure-terraform-backend-bucket-production; \
		cd $(TF_DIR) && terraform init; \
	fi
	@cd $(TF_DIR) && terraform fmt -recursive
	@echo "✅ 本番環境のTerraformフォーマットが完了しました"

terraform-validate-production: ## 本番環境のTerraformファイルを検証
	@echo "🔍 本番環境のTerraformファイルを検証中..."
	@if [ ! -f $(TF_DIR)/.terraform.lock.hcl ]; then \
		echo "Terraformが初期化されていません。初期化を実行します..."; \
		$(MAKE) ensure-terraform-backend-bucket-production; \
		cd $(TF_DIR) && terraform init; \
	fi
	@cd $(TF_DIR) && terraform validate
	@echo "✅ 本番環境のTerraform検証が完了しました"