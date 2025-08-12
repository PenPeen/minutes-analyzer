# API Gateway for Slack Bot Drive Selector
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

# /slack resource
resource "aws_api_gateway_resource" "slack" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_rest_api.slack_bot.root_resource_id
  path_part   = "slack"
}

# /slack/commands resource
resource "aws_api_gateway_resource" "commands" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.slack.id
  path_part   = "commands"
}

# /slack/interactions resource
resource "aws_api_gateway_resource" "interactions" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.slack.id
  path_part   = "interactions"
}

# /oauth resource
resource "aws_api_gateway_resource" "oauth" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_rest_api.slack_bot.root_resource_id
  path_part   = "oauth"
}

# /oauth/callback resource
resource "aws_api_gateway_resource" "oauth_callback" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_resource.oauth.id
  path_part   = "callback"
}

# /health resource
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  parent_id   = aws_api_gateway_rest_api.slack_bot.root_resource_id
  path_part   = "health"
}

# POST method for /slack/commands
resource "aws_api_gateway_method" "commands_post" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.commands.id
  http_method   = "POST"
  authorization = "NONE"
}

# POST method for /slack/interactions
resource "aws_api_gateway_method" "interactions_post" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.interactions.id
  http_method   = "POST"
  authorization = "NONE"
}

# GET method for /oauth/callback
resource "aws_api_gateway_method" "oauth_callback_get" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.oauth_callback.id
  http_method   = "GET"
  authorization = "NONE"
}

# GET method for /health
resource "aws_api_gateway_method" "health_get" {
  rest_api_id   = aws_api_gateway_rest_api.slack_bot.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

# Lambda integration for /slack/commands
resource "aws_api_gateway_integration" "commands_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.commands.id
  http_method = aws_api_gateway_method.commands_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}

# Lambda integration for /slack/interactions
resource "aws_api_gateway_integration" "interactions_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.interactions.id
  http_method = aws_api_gateway_method.interactions_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}

# Lambda integration for /oauth/callback
resource "aws_api_gateway_integration" "oauth_callback_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.oauth_callback.id
  http_method = aws_api_gateway_method.oauth_callback_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}

# Lambda integration for /health
resource "aws_api_gateway_integration" "health_lambda" {
  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.health_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.slack_bot_controller.invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.commands_lambda,
    aws_api_gateway_integration.interactions_lambda,
    aws_api_gateway_integration.oauth_callback_lambda,
    aws_api_gateway_integration.health_lambda
  ]

  rest_api_id = aws_api_gateway_rest_api.slack_bot.id
  stage_name  = var.environment

  # Force redeployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.commands.id,
      aws_api_gateway_resource.interactions.id,
      aws_api_gateway_resource.oauth_callback.id,
      aws_api_gateway_resource.health.id,
      aws_api_gateway_method.commands_post.id,
      aws_api_gateway_method.interactions_post.id,
      aws_api_gateway_method.oauth_callback_get.id,
      aws_api_gateway_method.health_get.id,
      aws_api_gateway_integration.commands_lambda.id,
      aws_api_gateway_integration.interactions_lambda.id,
      aws_api_gateway_integration.oauth_callback_lambda.id,
      aws_api_gateway_integration.health_lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Output the API Gateway URL
output "api_gateway_url" {
  description = "API Gateway base URL"
  value       = "${aws_api_gateway_rest_api.slack_bot.execution_arn}/${var.environment}"
}

output "api_gateway_invoke_url" {
  description = "API Gateway invoke URL" 
  value       = aws_api_gateway_deployment.main.invoke_url
}