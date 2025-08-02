variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "local"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "minutes-analyzer"
}

variable "lambda_zip_path" {
  description = "Path to the Lambda deployment package"
  type        = string
  default     = "../../../infrastructure/modules/lambda/lambda.zip"
}

variable "lambda_timeout" {
  description = "Lambda function timeout"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda function memory size"
  type        = number
  default     = 128
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 14
}

variable "claude_api_key_secret_name" {
  description = "The name of the secret in AWS Secrets Manager"
  type        = string
  default     = "minutes-analyzer/claude-api-key"
}

variable "claude_api_key_value" {
  description = "The value of the Claude API key (for local/dev only)"
  type        = string
  sensitive   = true
  default     = "dummy-claude-api-key"
}

variable "slack_error_webhook_url" {
  description = "Slack webhook URL for error notifications"
  type        = string
  default     = ""
}

variable "slack_integration_enabled" {
  description = "Enable Slack integration"
  type        = string
  default     = "true"
}

variable "notion_integration_enabled" {
  description = "Enable Notion integration"
  type        = string
  default     = "true"
}

variable "log_level" {
  description = "Log level for the lambda function"
  type        = string
  default     = "INFO"
}

variable "ai_model" {
  description = "AI model to use"
  type        = string
  default     = "claude-3-5-haiku-20241022"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "minutes-analyzer"
    Environment = "local"
    ManagedBy   = "terraform"
  }
}
