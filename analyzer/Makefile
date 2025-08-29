MAKEFLAGS += --silent
.PHONY: help setup build-lambda test test-lambda terraform-fmt-production terraform-validate-production deploy-production destroy-production clean-production

# デフォルトターゲット
help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# 環境変数
AWS_REGION = ap-northeast-1
PROJECT_NAME = minutes-analyzer

# 初期セットアップ
setup: ## 初期セットアップを実行
	@echo "📦 依存関係をインストール中..."
	@if command -v bundle >/dev/null 2>&1; then \
		cd lambda && rm -rf .bundle/config && BUNDLE_PATH=vendor/bundle BUNDLE_DEPLOYMENT=false bundle install; \
	else \
		echo "⚠️  Bundlerがインストールされていません。Rubyの依存関係はスキップします"; \
	fi
	@echo "✅ セットアップが完了しました"

build-lambda: ## Lambda関数をビルド
	@echo "🔨 Lambda関数をビルド中..."
	@mkdir -p infrastructure/modules/lambda
	@docker compose run --rm --env BUNDLE_DEPLOYMENT=true ruby-lambda-builder
	@echo "✅ Lambda関数のビルドが完了しました"

# テスト実行
test: test-lambda ## テスト実行

test-lambda: ## Lambda関数のテストを実行
	@echo "🧪 Lambda関数のテストを実行中..."
	@docker compose run --rm --entrypoint="" ruby-lambda-builder sh -c "cd /var/task && bundle config unset without && bundle install --quiet && bundle exec rspec spec/ --format documentation"
	@echo "✅ テストが完了しました"

# クリーンアップ
clean: ## ビルド成果物をクリーンアップ
	@echo "🧹 ビルド成果物をクリーンアップ中..."
	@$(MAKE) clean-docker
	@$(MAKE) clean-build-artifacts
	@echo "✅ クリーンアップが完了しました"

clean-docker:
	@echo "🐳 Docker環境をクリーンアップ中..."
	@docker compose down -v --rmi local || true
	@docker system prune -f

clean-build-artifacts:
	@echo "🗂️  ビルド成果物を削除中..."
	@rm -f infrastructure/modules/lambda/lambda.zip
	@rm -f lambda/Gemfile.lock
	@rm -rf logs/ tmp/

# 本番環境用のterraform.tfvars生成
generate-tfvars-production: ## 本番環境用terraform.tfvarsを.env.productionから生成
	@echo "📝 本番環境用terraform.tfvarsを生成中..."
	@if [ -f .env.production ]; then \
		( \
			echo "# .env.productionから自動生成されるTerraform変数ファイル"; \
			echo "# 基本設定"; \
			echo "aws_region = \"ap-northeast-1\""; \
			echo "environment = \"production\""; \
			echo "project_name = \"minutes-analyzer\""; \
			echo ""; \
			echo "# Lambda設定"; \
			echo "lambda_timeout = 900"; \
			echo "lambda_memory_size = 512"; \
			echo "log_retention_days = 30"; \
			echo "log_level = \"INFO\""; \
			echo "ai_model = \"gemini-2.5-flash\""; \
			echo ""; \
			echo "# API Keys (from .env.production)"; \
			echo "gemini_api_key=\"$$(grep GEMINI_API_KEY .env.production | cut -d '=' -f2-)\""; \
			echo "slack_bot_token=\"$$(grep SLACK_BOT_TOKEN .env.production | cut -d '=' -f2-)\""; \
			echo "slack_channel_id=\"$$(grep SLACK_CHANNEL_ID .env.production | cut -d '=' -f2-)\""; \
			echo "notion_api_key=\"$$(grep NOTION_API_KEY .env.production | cut -d '=' -f2-)\""; \
			echo "notion_database_id=\"$$(grep NOTION_DATABASE_ID .env.production | cut -d '=' -f2-)\""; \
			echo "notion_task_database_id=\"$$(grep NOTION_TASK_DATABASE_ID .env.production | cut -d '=' -f2-)\""; \
		) > infrastructure/environments/production/terraform.tfvars; \
		if [ -n "$$(grep GOOGLE_SERVICE_ACCOUNT_JSON .env.production | cut -d '=' -f2-)" ]; then \
			grep GOOGLE_SERVICE_ACCOUNT_JSON .env.production | cut -d '=' -f2- > infrastructure/environments/production/google_service_account.json; \
			if ! grep -q "google_service_account_json_path" infrastructure/environments/production/terraform.tfvars; then \
				echo "google_service_account_json_path=\"google_service_account.json\"" >> infrastructure/environments/production/terraform.tfvars; \
			fi; \
			echo "✅ google_service_account.jsonを生成しました"; \
		fi; \
		echo "✅ terraform.tfvarsを生成しました"; \
	else \
		echo "❌ .env.productionが見つかりません。"; \
		echo "  cp .env.local .env.production でコピーして、本番用の値に編集してください。"; \
		exit 1; \
	fi

ensure-terraform-backend-bucket-production: ## 本番環境用Terraform backend S3バケットの存在確認・作成
	@echo "🪣 Terraform backend用S3バケットを確認中..."
	@BUCKET_NAME="minutes-analyzer-terraform-state"; \
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

# 本番環境用Terraform初期化
tf-init-production: ensure-terraform-backend-bucket-production ## 本番環境用Terraformを初期化
	@echo "本番環境用Terraform初期化中..."
	@if [ ! -f infrastructure/environments/production/.terraform.lock.hcl ]; then \
		cd infrastructure/environments/production && terraform init; \
	else \
		echo "本番環境用Terraformは既に初期化されています"; \
	fi
	@echo "本番環境用Terraformの初期化が完了しました"

# 本番環境用Terraformプラン
tf-plan-production: tf-init-production generate-tfvars-production build-lambda ## 本番環境用Terraformプランを実行
	@echo "📋 本番環境用Terraformプランを実行中..."
	@cd infrastructure/environments/production && terraform plan -var-file="terraform.tfvars"
	@echo "✅ 本番環境用Terraformプランが完了しました"

# 本番環境用Terraform適用
tf-apply-production: ## 本番環境用Terraformを適用
	@echo "🚀 本番環境用Terraformを適用中..."
	@if [ -f infrastructure/environments/production/terraform.tfvars ]; then \
		cd infrastructure/environments/production && terraform apply -var-file="terraform.tfvars" -auto-approve; \
	else \
		cd infrastructure/environments/production && terraform apply -auto-approve; \
	fi
	@echo "✅ 本番環境用Terraformの適用が完了しました"

upload-prompts-production: ## 本番環境のS3にプロンプトファイルをアップロード
	@echo "📤 本番環境用プロンプトファイルをS3にアップロード中..."
	@./scripts/upload_prompts_to_s3.sh production
	@echo "✅ 本番環境用プロンプトのアップロードが完了しました"

# AWS本番環境用のコマンド
destroy-production: ## 本番環境のリソースを削除
	@echo "🗑️  本番環境のリソースを削除中..."
	@if [ ! -f .env.production ]; then \
		echo "⚠️  .env.productionが見つかりません。terraform.tfvarsが既に存在する場合はそれを使用します。"; \
	else \
		$(MAKE) generate-tfvars-production; \
	fi
	@echo "🗑️  Terraformでリソースを削除中..."
	@cd infrastructure/environments/production && \
		terraform destroy -auto-approve 2>/dev/null || true
	@echo "🗑️  残存リソースを強制削除中..."
	@echo "  - S3バケットのバージョニングされたオブジェクトを削除..."
	@aws s3api list-object-versions --bucket minutes-analyzer-prompts-production --output json 2>/dev/null | \
		jq -r '.Versions[]?.Key, .DeleteMarkers[]?.Key' 2>/dev/null | \
		sort -u | \
		while read -r key; do \
			[ -z "$$key" ] && continue; \
			aws s3api list-object-versions --bucket minutes-analyzer-prompts-production --prefix "$$key" --output json 2>/dev/null | \
			jq -r '.Versions[]? | "--key \"" + .Key + "\" --version-id " + .VersionId' | \
			while read -r args; do \
				[ -z "$$args" ] && continue; \
				echo "    削除中: $$key"; \
				eval "aws s3api delete-object --bucket minutes-analyzer-prompts-production $$args" 2>/dev/null || true; \
			done; \
			aws s3api list-object-versions --bucket minutes-analyzer-prompts-production --prefix "$$key" --output json 2>/dev/null | \
			jq -r '.DeleteMarkers[]? | "--key \"" + .Key + "\" --version-id " + .VersionId' | \
			while read -r args; do \
				[ -z "$$args" ] && continue; \
				eval "aws s3api delete-object --bucket minutes-analyzer-prompts-production $$args" 2>/dev/null || true; \
			done; \
		done || true
	@echo "  - S3バケットの通常オブジェクトを削除..."
	@aws s3 rm s3://minutes-analyzer-prompts-production --recursive || true
	@echo "  - S3バケット本体を削除..."
	@aws s3 rb s3://minutes-analyzer-prompts-production --force || true
	@echo "  - Secrets Managerを削除..."
	@aws secretsmanager delete-secret --secret-id minutes-analyzer-secrets-production --force-delete-without-recovery 2>/dev/null || true
	@echo "  - Lambda関数を削除..."
	@aws lambda delete-function --function-name minutes-analyzer-production 2>/dev/null || true
	@echo "  - CloudWatch Logsを削除..."
	@aws logs delete-log-group --log-group-name /aws/lambda/minutes-analyzer-production 2>/dev/null || true
	@echo "🧹 Terraform状態ファイルをクリーンアップ中..."
	@cd infrastructure/environments/production && \
		rm -rf .terraform terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
	@echo "✅ 本番環境が完全に削除されました"

clean-production: ## 本番環境の設定ファイルをクリーンアップ
	@echo "🧹 本番環境の設定ファイルをクリーンアップ中..."
	@cd infrastructure/environments/production && \
		rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
	@rm -f infrastructure/environments/production/terraform.tfvars
	@rm -f infrastructure/environments/production/google_service_account.json
	@echo "✅ クリーンアップが完了しました"

deploy-production: ## 本番環境にデプロイ
	@echo "🚀 本番環境にデプロイ中..."
	@if [ ! -f .env.production ]; then \
		echo "❌ .env.productionが見つかりません。"; \
		echo "  cp .env.local .env.production でコピーして、本番用の値に編集してください。"; \
		exit 1; \
	fi
	@echo "🔨 Lambda関数をビルド中..."
	@$(MAKE) build-lambda
	@$(MAKE) generate-tfvars-production
	@$(MAKE) ensure-terraform-backend-bucket-production
	@cd infrastructure/environments/production && \
		terraform init && \
		terraform plan && \
		echo "⚠️  Review the plan above. Press Enter to continue or Ctrl+C to cancel..." && \
		read && \
		terraform apply
	@echo "🔐 Secrets Managerにシークレットを設定中..."
	@./scripts/set-production-secrets.sh
	@$(MAKE) upload-prompts-production
	@echo "✅ 本番環境へのデプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd infrastructure/environments/production && terraform output

upload-prompts-production: ## 本番環境のS3にプロンプトファイルをアップロード
	@echo "📤 本番環境用プロンプトファイルをS3にアップロード中..."
	@./scripts/upload_prompts_to_s3.sh production
	@echo "✅ 本番環境用プロンプトのアップロードが完了しました"

# terraform検証コマンド（本番環境用）
terraform-fmt-production: ## 本番環境のTerraformファイルをフォーマット
	@echo "🔧 本番環境のTerraformファイルをフォーマット中..."
	@if [ ! -f infrastructure/environments/production/.terraform.lock.hcl ]; then \
		echo "Terraformが初期化されていません。初期化を実行します..."; \
		$(MAKE) ensure-terraform-backend-bucket-production; \
		cd infrastructure/environments/production && terraform init; \
	fi
	@cd infrastructure/environments/production && terraform fmt -recursive
	@echo "✅ 本番環境のTerraformフォーマットが完了しました"

terraform-validate-production: ## 本番環境のTerraformファイルを検証
	@echo "🔍 本番環境のTerraformファイルを検証中..."
	@if [ ! -f infrastructure/environments/production/.terraform.lock.hcl ]; then \
		echo "Terraformが初期化されていません。初期化を実行します..."; \
		$(MAKE) ensure-terraform-backend-bucket-production; \
		cd infrastructure/environments/production && terraform init; \
	fi
	@cd infrastructure/environments/production && terraform validate
	@echo "✅ 本番環境のTerraform検証が完了しました"