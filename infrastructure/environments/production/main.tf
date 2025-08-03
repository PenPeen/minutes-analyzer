terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "minutes-analyzer-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Secrets Manager for Application Secrets
resource "aws_secretsmanager_secret" "app_secrets" {
  name = "${var.project_name}-secrets-${var.environment}"

  recovery_window_in_days = 7

  tags = var.common_tags
}

# Lambda function
resource "aws_lambda_function" "minutes_analyzer" {
  filename         = var.lambda_zip_path
  function_name    = "${var.project_name}-${var.environment}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "ruby3.3"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      ENVIRONMENT                 = var.environment
      APP_SECRETS_NAME            = aws_secretsmanager_secret.app_secrets.name
      SLACK_INTEGRATION           = var.slack_integration_enabled
      NOTION_INTEGRATION          = var.notion_integration_enabled
      LOG_LEVEL                   = var.log_level
      AI_MODEL                    = var.ai_model
    }
  }

  tags = var.common_tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.minutes_analyzer.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.common_tags
}

# IAM Role
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

# IAM Role Policy Attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
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

# API Gateway
resource "aws_api_gateway_rest_api" "minutes_analyzer_api" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "Minutes Analyzer API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

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
  api_key_required = true
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

  lifecycle {
    create_before_destroy = true
  }
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
    limit  = 10000
    period = "DAY"
  }

  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }

  tags = var.common_tags
}

resource "aws_api_gateway_usage_plan_key" "minutes_analyzer_plan_key" {
  key_id        = aws_api_gateway_api_key.minutes_analyzer_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.minutes_analyzer_plan.id
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.minutes_analyzer.function_name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.project_name}-lambda-throttles-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors lambda throttles"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.minutes_analyzer.function_name
  }

  tags = var.common_tags
}
