output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.minutes_analyzer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.minutes_analyzer.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.minutes_analyzer_api.id}/${var.environment}/_user_request_"
}

output "api_endpoint_url" {
  description = "Full API endpoint URL"
  value       = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.minutes_analyzer_api.id}/${var.environment}/_user_request_/analyze"
}

output "api_key_id" {
  description = "API Gateway API Key ID"
  value       = aws_api_gateway_api_key.minutes_analyzer_key.id
}

output "api_key_value" {
  description = "API Gateway API Key Value"
  value       = aws_api_gateway_api_key.minutes_analyzer_key.value
  sensitive   = true
}

output "rest_api_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.minutes_analyzer_api.id
}
