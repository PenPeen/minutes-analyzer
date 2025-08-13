# Project configuration
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "drive-selector"
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

# AWS configuration
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

# API Gateway configuration
variable "api_gateway_domain" {
  description = "Custom domain for API Gateway (required for production)"
  type        = string
  default     = null
}

# Lambda configuration
variable "process_lambda_arn" {
  description = "ARN of the existing minutes analyzer Lambda function"
  type        = string
}

# Secrets configuration
variable "slack_signing_secret" {
  description = "Slack signing secret"
  type        = string
  sensitive   = true
  default     = "placeholder"
}

variable "slack_bot_token" {
  description = "Slack bot token"
  type        = string
  sensitive   = true
  default     = "placeholder"
}

variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
  sensitive   = true
  default     = "placeholder"
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
  default     = "placeholder"
}