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

variable "gemini_api_key" {
  description = "Gemini API key"
  type        = string
  sensitive   = true
  default     = "dummy-key-for-local-development"  # ローカル開発用デフォルト値
}

variable "slack_error_webhook_url" {
  description = "Slack webhook URL for error notifications"
  type        = string
  default     = ""
}

variable "ai_model" {
  description = "AI model to use"
  type        = string
  default     = "gemini-1.5-flash"
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
