terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # LocalStack用設定
  endpoints {
    lambda         = "http://localhost:4566"
    apigateway     = "http://localhost:4566"
    iam            = "http://localhost:4566"
    logs           = "http://localhost:4566"
    sts            = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
    s3             = "http://localhost:4566"
  }

  # LocalStack用の認証設定
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  # S3用の設定
  s3_use_path_style = true
}

# Secrets Manager for Application Secrets
resource "aws_secretsmanager_secret" "app_secrets" {
  name = "${var.project_name}-secrets-${var.environment}"
  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    GEMINI_API_KEY = var.gemini_api_key
    # Google Service Account JSONはファイルから読み込む
    # file()関数を使用することで、JSONの改行やエスケープを正しく処理
    # ファイルが存在しない場合は空文字列を設定（オプショナル対応）
    GOOGLE_SERVICE_ACCOUNT_JSON = var.google_service_account_json_path != "" ? (fileexists(var.google_service_account_json_path) ? file(var.google_service_account_json_path) : "") : ""
    SLACK_WEBHOOK_URL           = var.slack_webhook_url
    SLACK_BOT_TOKEN             = var.slack_bot_token
    NOTION_API_KEY              = var.notion_api_key
    NOTION_DATABASE_ID          = var.notion_database_id
    NOTION_TASK_DATABASE_ID     = var.notion_task_database_id
  })
}

# S3 Bucket for Prompts
resource "aws_s3_bucket" "prompts" {
  bucket = "${var.project_name}-prompts-${var.environment}"
  
  # LocalStackの場合、force_path_styleを使用
  force_destroy = true
  
  tags = var.common_tags
}

resource "aws_s3_bucket_versioning" "prompts" {
  bucket = aws_s3_bucket.prompts.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Policy - Allow access only from Lambda
resource "aws_s3_bucket_policy" "prompts" {
  bucket = aws_s3_bucket.prompts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyAllExceptLambda"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.prompts.arn,
          "${aws_s3_bucket.prompts.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = aws_iam_role.lambda_execution_role.arn
          }
        }
      }
    ]
  })
}

# Block public access
resource "aws_s3_bucket_public_access_block" "prompts" {
  bucket = aws_s3_bucket.prompts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lambda関数
resource "aws_lambda_function" "minutes_analyzer" {
  filename         = var.lambda_zip_path
  function_name    = "${var.project_name}-${var.environment}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "ruby3.2"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      ENVIRONMENT                 = var.environment
      APP_SECRETS_NAME            = aws_secretsmanager_secret.app_secrets.name
      LOG_LEVEL                   = var.log_level
      AWS_ENDPOINT_URL            = "http://host.docker.internal:4566"  # LocalStack endpoint
      PROMPTS_BUCKET_NAME         = aws_s3_bucket.prompts.id
      GOOGLE_CALENDAR_ENABLED     = var.google_calendar_enabled
      USER_MAPPING_ENABLED        = var.user_mapping_enabled
      CACHE_TTL                   = var.cache_ttl
    }
  }

  tags = var.common_tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.common_tags
}

# IAMロール
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# IAMロールポリシーアタッチメント
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Metrics権限
resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.project_name}-lambda-cloudwatch-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

# IAM Policy for Secrets Manager
resource "aws_iam_role_policy" "lambda_secrets_policy" {
  name = "${var.project_name}-lambda-secrets-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "secretsmanager:GetSecretValue",
        Resource = aws_secretsmanager_secret.app_secrets.arn
      }
    ]
  })
}

# IAM Policy for S3 Prompts Bucket
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.project_name}-lambda-s3-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.prompts.arn,
          "${aws_s3_bucket.prompts.arn}/*"
        ]
      }
    ]
  })
}

# API Gateway
resource "aws_api_gateway_rest_api" "minutes_analyzer_api" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "Minutes Analyzer API"

  tags = var.common_tags
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.minutes_analyzer_api.id
  parent_id   = aws_api_gateway_rest_api.minutes_analyzer_api.root_resource_id
  path_part   = "analyze"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.minutes_analyzer_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.minutes_analyzer_api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.minutes_analyzer.invoke_arn
}

resource "aws_api_gateway_deployment" "minutes_analyzer" {
  depends_on = [
    aws_api_gateway_integration.lambda,
  ]

  rest_api_id = aws_api_gateway_rest_api.minutes_analyzer_api.id
}

resource "aws_api_gateway_stage" "minutes_analyzer" {
  deployment_id = aws_api_gateway_deployment.minutes_analyzer.id
  rest_api_id   = aws_api_gateway_rest_api.minutes_analyzer_api.id
  stage_name    = var.environment

  tags = {
    Name        = "${var.project_name}-api-stage-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.minutes_analyzer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.minutes_analyzer_api.execution_arn}/*/*"
}

# API Key
resource "aws_api_gateway_api_key" "minutes_analyzer_key" {
  name = "${var.project_name}-api-key-${var.environment}"

  tags = var.common_tags
}

# Usage Plan
resource "aws_api_gateway_usage_plan" "minutes_analyzer_plan" {
  name         = "${var.project_name}-usage-plan-${var.environment}"
  description  = "Usage plan for Minutes Analyzer API"

  api_stages {
    api_id = aws_api_gateway_rest_api.minutes_analyzer_api.id
    stage  = aws_api_gateway_stage.minutes_analyzer.stage_name
  }

  quota_settings {
    limit  = 1000
    period = "DAY"
  }

  throttle_settings {
    rate_limit  = 20
    burst_limit = 5
  }

  tags = var.common_tags
}

resource "aws_api_gateway_usage_plan_key" "minutes_analyzer_plan_key" {
  key_id        = aws_api_gateway_api_key.minutes_analyzer_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.minutes_analyzer_plan.id
}
