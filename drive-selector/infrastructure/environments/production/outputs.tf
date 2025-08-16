output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.slack_bot_controller.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.slack_bot_controller.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "secret_name" {
  description = "Secret name for application secrets"
  value       = aws_secretsmanager_secret.app_secrets.name
}

output "api_gateway_url" {
  description = "API Gateway URL for Slack bot"
  value       = "https://${aws_api_gateway_rest_api.slack_bot.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}"
}

output "api_gateway_commands_url" {
  description = "API Gateway URL for Slack commands"
  value       = "https://${aws_api_gateway_rest_api.slack_bot.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}/slack/commands"
}

output "api_gateway_interactions_url" {
  description = "API Gateway URL for Slack interactions"
  value       = "https://${aws_api_gateway_rest_api.slack_bot.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}/slack/interactions"
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "api_key_id" {
  description = "API Gateway API Key ID"
  value       = aws_api_gateway_api_key.slack_bot_key.id
}

output "api_key_value" {
  description = "API Gateway API Key Value"
  value       = aws_api_gateway_api_key.slack_bot_key.value
  sensitive   = true
}
