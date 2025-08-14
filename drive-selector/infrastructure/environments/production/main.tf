terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "drive-selector-terraform-state"
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
resource "aws_lambda_function" "slack_bot_controller" {
  filename         = var.lambda_zip_path
  function_name    = "${var.project_name}-${var.environment}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "ruby3.2"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      ENVIRONMENT               = var.environment
      APP_SECRETS_NAME          = aws_secretsmanager_secret.app_secrets.name
      SECRETS_MANAGER_SECRET_ID = aws_secretsmanager_secret.app_secrets.name
      LOG_LEVEL                 = "INFO"
      SLACK_CHANNEL_ID          = var.slack_channel_id
    }
  }

  tags = var.common_tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.slack_bot_controller.function_name}"
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

# IAM Policy for Lambda Invoke
resource "aws_iam_role_policy" "lambda_invoke_policy" {
  name = "${var.project_name}-lambda-invoke-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "lambda:InvokeFunction",
        Resource = "*"
      }
    ]
  })
}

# API Gateway
resource "aws_api_gateway_rest_api" "slack_bot" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "API Gateway for Slack Bot Drive Selector"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.common_tags
}

resource "aws_api_gateway_resource" "slack" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_rest_api.slack_bot.root_resource_id
  path_part   = "slack"
}

resource "aws_api_gateway_resource" "commands" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.slack.id
  path_part   = "commands"
}

resource "aws_api_gateway_resource" "interactions" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.slack.id
  path_part   = "interactions"
}

# OAuth callback resource
resource "aws_api_gateway_resource" "oauth" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_rest_api.slack_bot.root_resource_id
  path_part   = "oauth"
}

resource "aws_api_gateway_resource" "oauth_callback" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.oauth.id
  path_part   = "callback"
}

# Health check resource
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_rest_api.slack_bot.root_resource_id
  path_part   = "health"
}

resource "aws_api_gateway_method" "commands_post" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.commands.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "interactions_post" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.interactions.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "oauth_callback_get" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.oauth_callback.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "health_get" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "commands_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.commands.id
  http_method = aws_api_gateway_method.commands_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}

resource "aws_api_gateway_integration" "interactions_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.interactions.id
  http_method = aws_api_gateway_method.interactions_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}

resource "aws_api_gateway_integration" "oauth_callback_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.oauth_callback.id
  http_method = aws_api_gateway_method.oauth_callback_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}

resource "aws_api_gateway_integration" "health_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}

resource "aws_api_gateway_deployment" "slack_bot" {
  depends_on = [
    aws_api_gateway_integration.commands_lambda,
    aws_api_gateway_integration.interactions_lambda,
    aws_api_gateway_integration.oauth_callback_lambda,
    aws_api_gateway_integration.health_lambda,
  ]

  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  stage_name  = var.environment

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "api_gateway_commands" {
  statement_id  = "AllowExecutionFromAPIGatewayCommands"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_bot_controller.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.slack_bot.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_interactions" {
  statement_id  = "AllowExecutionFromAPIGatewayInteractions"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_bot_controller.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.slack_bot.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_oauth_callback" {
  statement_id  = "AllowExecutionFromAPIGatewayOAuthCallback"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_bot_controller.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.slack_bot.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_health" {
  statement_id  = "AllowExecutionFromAPIGatewayHealth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_bot_controller.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.slack_bot.execution_arn}/*/*"
}
