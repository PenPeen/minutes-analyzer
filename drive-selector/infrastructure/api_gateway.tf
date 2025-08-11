# API Gateway REST API
resource "aws_api_gateway_rest_api" "slack_bot" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "API Gateway for Slack Bot Drive Selector"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# /slack リソース
resource "aws_api_gateway_resource" "slack" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_rest_api.slack_bot.root_resource_id
  path_part   = "slack"
}

# /slack/commands リソース
resource "aws_api_gateway_resource" "commands" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.slack.id
  path_part   = "commands"
}

# /slack/interactions リソース
resource "aws_api_gateway_resource" "interactions" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.slack.id
  path_part   = "interactions"
}

# /slack/commands POST メソッド
resource "aws_api_gateway_method" "commands_post" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.commands.id
  http_method   = "POST"
  authorization = "NONE"
}

# /slack/interactions POST メソッド
resource "aws_api_gateway_method" "interactions_post" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.interactions.id
  http_method   = "POST"
  authorization = "NONE"
}

# /slack/commands Lambda統合
resource "aws_api_gateway_integration" "commands_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.commands.id
  http_method = aws_api_gateway_method.commands_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn

  depends_on = [aws_api_gateway_method.commands_post]
}

# /slack/interactions Lambda統合
resource "aws_api_gateway_integration" "interactions_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.interactions.id
  http_method = aws_api_gateway_method.interactions_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn

  depends_on = [aws_api_gateway_method.interactions_post]
}

# /slack/commands メソッドレスポンス
resource "aws_api_gateway_method_response" "commands_200" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.commands.id
  http_method = aws_api_gateway_method.commands_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  depends_on = [aws_api_gateway_integration.commands_lambda]
}

# /slack/interactions メソッドレスポンス
resource "aws_api_gateway_method_response" "interactions_200" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.interactions.id
  http_method = aws_api_gateway_method.interactions_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  depends_on = [aws_api_gateway_integration.interactions_lambda]
}

# /slack/commands 統合レスポンス
resource "aws_api_gateway_integration_response" "commands_200" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.commands.id
  http_method = aws_api_gateway_method.commands_post.http_method
  status_code = aws_api_gateway_method_response.commands_200.status_code

  depends_on = [
    aws_api_gateway_integration.commands_lambda,
    aws_api_gateway_method_response.commands_200
  ]
}

# /slack/interactions 統合レスポンス
resource "aws_api_gateway_integration_response" "interactions_200" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.interactions.id
  http_method = aws_api_gateway_method.interactions_post.http_method
  status_code = aws_api_gateway_method_response.interactions_200.status_code

  depends_on = [
    aws_api_gateway_integration.interactions_lambda,
    aws_api_gateway_method_response.interactions_200
  ]
}

# API Gatewayデプロイメント
resource "aws_api_gateway_deployment" "slack_bot" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.slack.id,
      aws_api_gateway_resource.commands.id,
      aws_api_gateway_resource.interactions.id,
      aws_api_gateway_method.commands_post.id,
      aws_api_gateway_method.interactions_post.id,
      aws_api_gateway_integration.commands_lambda.id,
      aws_api_gateway_integration.interactions_lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.commands_lambda,
    aws_api_gateway_integration.interactions_lambda,
    aws_api_gateway_integration_response.commands_200,
    aws_api_gateway_integration_response.interactions_200
  ]
}

# API Gatewayステージ
resource "aws_api_gateway_stage" "slack_bot" {
  deployment_id = aws_api_gateway_deployment.slack_bot.id
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  stage_name    = var.environment

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.project_name}-api-stage-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/${var.project_name}-${var.environment}"
  retention_in_days = var.environment == "production" ? 30 : 7

  tags = {
    Name        = "${var.project_name}-api-logs-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway account settings (required for CloudWatch logging)
resource "aws_api_gateway_account" "slack_bot" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

# IAM role for API Gateway CloudWatch logging
resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${var.project_name}-api-gateway-cloudwatch-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-api-cloudwatch-role-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Attach CloudWatch Logs policy to the role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# API Gatewayのメソッド設定（Slackのタイムアウトに対応）
resource "aws_api_gateway_method_settings" "slack_bot" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  stage_name  = aws_api_gateway_stage.slack_bot.stage_name
  method_path = "*/*"

  settings = {
    throttling_rate_limit  = 10000
    throttling_burst_limit = 5000
    logging_level          = var.environment == "production" ? "ERROR" : "INFO"
    data_trace_enabled     = var.environment != "production"
    metrics_enabled        = true
  }
}

# Output: API Gateway URL
output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = aws_api_gateway_stage.slack_bot.invoke_url
}

# Output: Slack command endpoint
output "slack_command_endpoint" {
  description = "Slack slash command endpoint URL"
  value       = "${aws_api_gateway_stage.slack_bot.invoke_url}/slack/commands"
}

# Output: Slack interactions endpoint
output "slack_interactions_endpoint" {
  description = "Slack interactions endpoint URL"
  value       = "${aws_api_gateway_stage.slack_bot.invoke_url}/slack/interactions"
}