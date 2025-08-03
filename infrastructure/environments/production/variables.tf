variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "minutes-analyzer"
}

variable "lambda_zip_path" {
  description = "Path to the Lambda deployment package"
  type        = string
  default     = "../../modules/lambda/lambda.zip"
}

variable "lambda_timeout" {
  description = "Lambda function timeout"
  type        = number
  default     = 900  # 15 minutes
}

variable "lambda_memory_size" {
  description = "Lambda function memory size"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 30
}

variable "gemini_api_key_secret_name" {
  description = "The name of the secret in AWS Secrets Manager"
  type        = string
  default     = "minutes-analyzer-gemini-api-key-production"
}

variable "slack_error_webhook_url" {
  description = "Slack webhook URL for error notifications"
  type        = string
  sensitive   = true
}

variable "slack_success_webhook_url" {
  description = "Slack webhook URL for success notifications"
  type        = string
  default     = ""
  sensitive   = true
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
  default     = "gemini-2.5-flash"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "minutes-analyzer"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
