# API Gateway outputs
output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_api_gateway_rest_api.slack_bot.id
}

output "api_gateway_arn" {
  description = "API Gateway ARN"
  value       = aws_api_gateway_rest_api.slack_bot.arn
}

output "api_gateway_execution_arn" {
  description = "API Gateway execution ARN"
  value       = aws_api_gateway_rest_api.slack_bot.execution_arn
}

# Lambda outputs
output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.slack_bot_controller.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.slack_bot_controller.arn
}

# DynamoDB outputs
output "oauth_tokens_table_name" {
  description = "OAuth tokens DynamoDB table name"
  value       = aws_dynamodb_table.oauth_tokens.name
}

output "user_preferences_table_name" {
  description = "User preferences DynamoDB table name"
  value       = aws_dynamodb_table.user_preferences.name
}

# Secrets Manager outputs
output "secrets_manager_secret_id" {
  description = "Secrets Manager secret ID"
  value       = aws_secretsmanager_secret.app_secrets.id
}

output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.app_secrets.arn
}