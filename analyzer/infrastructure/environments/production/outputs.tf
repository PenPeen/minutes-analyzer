output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.minutes_analyzer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.minutes_analyzer.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "secret_name" {
  description = "Secret name for application secrets"
  value       = aws_secretsmanager_secret.app_secrets.name
}
