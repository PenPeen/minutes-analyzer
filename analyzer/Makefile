MAKEFLAGS += --silent
.PHONY: help setup start build-lambda deploy-local destroy-local clean check-localstack-ready stop test test-lambda ensure-terraform-backend-bucket

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
TF_DIR = infrastructure/environments/local

# LocalStack AWS設定
AWS_ENDPOINT_FLAG = --endpoint-url=$(LOCALSTACK_ENDPOINT)
AWS_LOCAL_CREDENTIALS = AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test

# 初期セットアップ（OSS公開用）
setup: ## 初期セットアップを実行
	@if [ -f .env.local ]; then \
		echo "📋 .env.localは既に存在します（保護されています）"; \
		echo "🔧 その他のセットアップを継続します..."; \
	else \
		./scripts/setup.sh; \
	fi
	@echo "📦 依存関係をインストール中..."
	@if command -v bundle >/dev/null 2>&1; then \
		cd lambda && bundle install; \
	else \
		echo "⚠️  Bundlerがインストールされていません。Rubyの依存関係はスキップします"; \
	fi
	@echo "✅ セットアップが完了しました"

# 開発環境起動（ビルド・デプロイ含む）
start: ## 開発環境を起動・デプロイ
	@echo "🚀 開発環境を起動中..."
	@if [ ! -f .env.local ]; then \
		echo "❌ .env.localが見つかりません。make setup を最初に実行してください。"; \
		exit 1; \
	fi
	@echo "🐳 Dockerコンテナを起動中..."
	@export $$(cat .env.local | grep -v '^#' | grep -v 'GOOGLE_SERVICE_ACCOUNT_JSON' | xargs) && \
	cd infrastructure && docker compose up -d
	@$(MAKE) wait-for-localstack
	@echo "📝 設定ファイルを生成中..."
	@$(MAKE) generate-tfvars
	@echo "🔨 Lambda関数をビルド中..."
	@$(MAKE) build-lambda
	@echo "🚀 インフラストラクチャをデプロイ中..."
	@$(MAKE) tf-init
	@$(MAKE) tf-apply
	@echo "📤 プロンプトをアップロード中..."
	@$(MAKE) upload-prompts-local
	@echo "✅ 開発環境の起動が完了しました"
	@echo ""
	@echo "📋 デプロイ情報:"
	@cd $(TF_DIR) && terraform output 2>/dev/null || echo "デプロイ情報の取得に失敗しました"

# terraform.tfvarsの生成
# 
# Google Service Account JSONの処理について:
# 当初はBASE64エンコードを使用していたが、以下の理由でファイル生成方式に変更:
# 1. JSON内の改行文字（private_key内の\n）をTerraform変数として正しくエスケープするのが複雑
# 2. Terraformのtfvarsファイルは複数行文字列の処理に制限がある
# 3. JSONをtfvarsに埋め込むとエスケープ処理が多重になり、メンテナンスが困難
# 
# 現在の方式の利点:
# - JSONファイルをそのまま保存し、Terraformのfile()関数で読み込むため、エスケープ不要
# - .env.localには1行のJSONを保存し、環境変数として扱いやすい
# - google_service_account.jsonは.gitignoreに追加済みで、誤ったコミットを防止
#
generate-tfvars: ## terraform.tfvarsを.env.localから生成
	@echo "📝 terraform.tfvarsとGoogle認証情報を生成中..."
	@if [ -f .env.local ]; then \
		( \
			echo "# .env.localから自動生成されるTerraform変数ファイル"; \
			echo "gemini_api_key=\"$$(grep GEMINI_API_KEY .env.local | cut -d '=' -f2-)\""; \
			echo "slack_bot_token=\"$$(grep SLACK_BOT_TOKEN .env.local | cut -d '=' -f2-)\""; \
			echo "slack_channel_id=\"$$(grep SLACK_CHANNEL_ID .env.local | cut -d '=' -f2-)\""; \
			echo "notion_api_key=\"$$(grep NOTION_API_KEY .env.local | cut -d '=' -f2-)\""; \
			echo "notion_database_id=\"$$(grep NOTION_DATABASE_ID .env.local | cut -d '=' -f2-)\""; \
			echo "notion_task_database_id=\"$$(grep NOTION_TASK_DATABASE_ID .env.local | cut -d '=' -f2-)\""; \
		) > infrastructure/environments/local/terraform.tfvars; \
		if [ -n "$$(grep GOOGLE_SERVICE_ACCOUNT_JSON .env.local | cut -d '=' -f2-)" ]; then \
			grep GOOGLE_SERVICE_ACCOUNT_JSON .env.local | cut -d '=' -f2- > infrastructure/environments/local/google_service_account.json; \
			if ! grep -q "google_service_account_json_path" infrastructure/environments/local/terraform.tfvars; then \
				echo "google_service_account_json_path=\"google_service_account.json\"" >> infrastructure/environments/local/terraform.tfvars; \
			fi; \
			echo "✅ google_service_account.jsonを生成しました"; \
		fi; \
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
	@cd $(TF_DIR) && terraform plan
	@echo "✅ Terraformプランが完了しました"

# Terraform適用（プランなし）
tf-apply: ## Terraformを適用
	@echo "🚀 Terraformを適用中..."
	@if [ -f $(TF_DIR)/terraform.tfvars ]; then \
		cd $(TF_DIR) && terraform apply -var-file="terraform.tfvars" -auto-approve; \
	else \
		cd $(TF_DIR) && terraform apply -auto-approve; \
	fi
	@echo "✅ Terraformの適用が完了しました"

# LocalStack環境にデプロイ（プラン確認あり）
deploy-local: tf-plan tf-apply upload-prompts-local ## LocalStack環境にデプロイ
	@echo "✅ デプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd $(TF_DIR) && terraform output

# プロンプトをS3にアップロード
upload-prompts-local: ## プロンプトファイルをLocalStackのS3にアップロード
	@echo "📤 プロンプトファイルをS3にアップロード中..."
	@$(AWS_LOCAL_CREDENTIALS) ./scripts/upload_prompts_to_s3.sh local
	@echo "✅ プロンプトのアップロードが完了しました"

# LocalStack環境を破棄
destroy-local: ## LocalStack環境を破棄
	@echo "🗑️  LocalStack環境を破棄中..."
	@cd $(TF_DIR) && terraform destroy -auto-approve
	@echo "✅ 環境の破棄が完了しました"

# テスト実行
test: test-lambda

test-lambda:
	@echo "🧪 Lambda関数のテストを実行中..."
	@docker compose run --rm --entrypoint="" ruby-lambda-builder sh -c "cd /var/task && bundle config unset without && bundle install --quiet && bundle exec rspec spec/ --format documentation"
	@echo "✅ テストが完了しました"

# 簡単なヘルスチェック
health-check: ## APIヘルスチェック
	@echo "❤️  APIヘルスチェック中..."
	@API_URL=$$(cd infrastructure/environments/local && terraform output -raw api_gateway_url); \
	curl -s "$$API_URL/health" -w "\nHTTP Status: %{http_code}\n" || echo "ヘルスチェックに失敗しました"

# ローカル環境のクリーンアップ
clean: ## ローカル環境をクリーンアップ
	@echo "🧹 ローカル環境をクリーンアップ中..."
	@$(MAKE) clean-docker
	@$(MAKE) clean-build-artifacts
	@$(MAKE) clean-terraform
	@echo "✅ クリーンアップが完了しました"

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
	@cd $(TF_DIR) && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup terraform.tfvars google_service_account.json

clean-config:
	@echo "⚙️  設定ファイルを削除中..."
	@rm -f .env.local .env.production

# Lambda関数をビルド・デプロイする完全なタスク
build-and-deploy: build-lambda tf-init tf-apply upload-prompts-local ## Lambda関数をビルドしてデプロイ
	@echo "🎉 ビルドとデプロイが完了しました！"
	@echo "📋 デプロイ情報:"
	@cd $(TF_DIR) && terraform output 2>/dev/null || echo "デプロイ情報の取得に失敗しました"

# 開発環境の完全セットアップ
dev-setup: setup-local build-and-deploy ## 開発環境を完全にセットアップ
	@echo "🎉 開発環境のセットアップが完了しました！"
	@echo ""
	@echo "📋 利用可能な情報:"
	@cd $(TF_DIR) && \
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

# 本番環境用のterraform.tfvars生成
generate-production-tfvars: ## .env.productionからterraform.tfvarsを生成
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

ensure-terraform-backend-bucket: ## Terraform backend用S3バケットの存在確認・作成
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

# AWS本番環境用のコマンド
destroy-production: ## 本番環境のリソースを削除
	@echo "🗑️  本番環境のリソースを削除中..."
	@if [ ! -f .env.production ]; then \
		echo "⚠️  .env.productionが見つかりません。terraform.tfvarsが既に存在する場合はそれを使用します。"; \
	else \
		$(MAKE) generate-production-tfvars; \
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
	@$(MAKE) generate-production-tfvars
	@$(MAKE) ensure-terraform-backend-bucket
	@cd infrastructure/environments/production && \
		terraform init && \
		terraform plan && \
		echo "⚠️  Review the plan above. Press Enter to continue or Ctrl+C to cancel..." && \
		read && \
		terraform apply
	@echo "🔐 Secrets Managerにシークレットを設定中..."
	@./scripts/set-production-secrets.sh
	@echo "📤 プロンプトをS3にアップロード中..."
	@./scripts/upload_prompts_to_s3.sh production
	@echo "✅ 本番環境へのデプロイが完了しました"
	@echo "📋 デプロイ情報:"
	@cd infrastructure/environments/production && terraform output
