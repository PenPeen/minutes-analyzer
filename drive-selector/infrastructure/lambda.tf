# Lambda function for Slack Bot Controller
resource "aws_lambda_function" "slack_bot_controller" {
  function_name = "${var.project_name}-controller-${var.environment}"
  runtime       = "ruby3.2"
  handler       = "handler.lambda_handler"
  timeout       = 30
  memory_size   = 256

  # Lambda deployment package
  filename         = "${path.module}/../lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda.zip")

  role = aws_iam_role.lambda_execution_role.arn

  environment {
    variables = {
      ENVIRONMENT              = var.environment
      OAUTH_TOKENS_TABLE      = aws_dynamodb_table.oauth_tokens.name
      USER_PREFERENCES_TABLE  = aws_dynamodb_table.user_preferences.name
      SECRETS_MANAGER_SECRET_ID = aws_secretsmanager_secret.app_secrets.id
      PROCESS_LAMBDA_ARN      = var.process_lambda_arn
      GOOGLE_REDIRECT_URI     = var.environment == "production" ? "https://${var.api_gateway_domain}/oauth/callback" : "http://localhost:3000/oauth/callback"
    }
  }

  # VPC configuration (optional)
  # vpc_config {
  #   subnet_ids         = var.subnet_ids
  #   security_group_ids = var.security_group_ids
  # }

  tags = {
    Name        = "${var.project_name}-controller-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_bot_controller.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.slack_bot.execution_arn}/*/*"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.slack_bot_controller.function_name}"
  retention_in_days = var.environment == "production" ? 30 : 7

  tags = {
    Name        = "${var.project_name}-lambda-logs-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}