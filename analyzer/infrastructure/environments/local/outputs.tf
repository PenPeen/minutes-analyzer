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
