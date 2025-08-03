output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.minutes_analyzer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.minutes_analyzer.arn
}

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_deployment.minutes_analyzer.invoke_url}/analyze"
}

output "api_key_id" {
  description = "API Key ID"
  value       = aws_api_gateway_api_key.minutes_analyzer_key.id
}

output "api_key_value" {
  description = "API Key Value"
  value       = aws_api_gateway_api_key.minutes_analyzer_key.value
  sensitive   = true
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "secret_name" {
  description = "Secret name for Gemini API key"
  value       = aws_secretsmanager_secret.gemini_api_key.name
}