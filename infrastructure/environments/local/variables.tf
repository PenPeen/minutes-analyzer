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
  default     = "../../modules/lambda/lambda.zip"
}

variable "lambda_timeout" {
  description = "Lambda function timeout"
  type        = number
  default     = 900
}

variable "lambda_memory_size" {
  description = "Lambda function memory size"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 14
}

variable "gemini_api_key_secret_name" {
  description = "The name of the secret in AWS Secrets Manager"
  type        = string
  default     = "minutes-analyzer/gemini-api-key"
}

variable "gemini_api_key" {
  description = "The value of the Gemini API key (for local/dev only)"
  type        = string
  sensitive   = true
  default     = "dummy-gemini-api-key"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_bot_token" {
  description = "Slack Bot User OAuth Token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "google_service_account_json_path" {
  description = "Path to Google service account JSON file"
  type        = string
  default     = ""
}

variable "google_calendar_enabled" {
  description = "Enable Google Calendar integration"
  type        = bool
  default     = false
}

variable "user_mapping_enabled" {
  description = "Enable user mapping for Slack and Notion"
  type        = bool
  default     = false
}

variable "cache_ttl" {
  description = "Cache TTL in seconds"
  type        = number
  default     = 600
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
    Environment = "local"
    ManagedBy   = "terraform"
  }
}


variable "notion_api_key" {
  description = "Notion API key for integration"
  type        = string
  sensitive   = true
  default     = ""
}

variable "notion_database_id" {
  description = "Notion database ID for meeting minutes"
  type        = string
  default     = ""
}

variable "notion_task_database_id" {
  description = "Notion database ID for tasks"
  type        = string
  default     = ""
}

