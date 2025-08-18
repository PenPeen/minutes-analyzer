terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "minutes-analyzer-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# KMS Key for encryption
resource "aws_kms_key" "main" {
  description = "KMS key for ${var.project_name}-${var.environment} encryption"
  
  enable_key_rotation = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key for Lambda"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_execution_role.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${var.environment}"
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-kms-key-${var.environment}"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}


# Secrets Manager for Application Secrets
resource "aws_secretsmanager_secret" "app_secrets" {
  name = "${var.project_name}-secrets-${var.environment}"

  recovery_window_in_days = 7
  kms_key_id              = aws_kms_key.main.arn

  tags = var.common_tags
}

# Lambda function
resource "aws_lambda_function" "minutes_analyzer" {
  filename         = var.lambda_zip_path
  function_name    = "${var.project_name}-${var.environment}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "ruby3.3"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  source_code_hash = filebase64sha256(var.lambda_zip_path)


  environment {
    variables = {
      ENVIRONMENT                 = var.environment
      APP_SECRETS_NAME            = aws_secretsmanager_secret.app_secrets.name
      PROMPTS_BUCKET_NAME         = aws_s3_bucket.prompts.id
      LOG_LEVEL                   = var.log_level
      AI_MODEL                    = var.ai_model
      GOOGLE_CALENDAR_ENABLED     = var.google_calendar_enabled
      USER_MAPPING_ENABLED        = var.user_mapping_enabled
      CACHE_TTL                   = var.cache_ttl
    }
  }

  tags = var.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# S3 Bucket for prompts
resource "aws_s3_bucket" "prompts" {
  bucket = "${var.project_name}-prompts-${var.environment}"
  
  force_destroy = true  # Allow deletion even when bucket contains objects

  tags = var.common_tags
}

resource "aws_s3_bucket_versioning" "prompts" {
  bucket = aws_s3_bucket.prompts.id

  versioning_configuration {
    status = "Disabled"  # Versioning disabled to simplify bucket deletion
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "prompts" {
  bucket = aws_s3_bucket.prompts.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "prompts" {
  bucket = aws_s3_bucket.prompts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch Log Group with KMS encryption
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = var.common_tags
}

# Note: WAF configuration will be added when API Gateway is implemented
# WAF is not applicable for direct Lambda invocation via IAM roles

# Lambda Permission - drive-selector-productionからのみアクセス許可
resource "aws_lambda_permission" "allow_drive_selector_invoke" {
  statement_id  = "AllowInvokeFromDriveSelector"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.minutes_analyzer.function_name
  principal     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/drive-selector-lambda-role-production"
}

# IAM Role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# IAM Role Policy Attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}


# IAM Policy for Secrets Manager
# IAM Role Policy for S3 Prompts Bucket
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.project_name}-lambda-s3-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.prompts.arn,
          "${aws_s3_bucket.prompts.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_secrets_policy" {
  name = "${var.project_name}-lambda-secrets-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "secretsmanager:GetSecretValue",
        Resource = aws_secretsmanager_secret.app_secrets.arn
      }
    ]
  })
}

# IAM Role Policy for KMS
resource "aws_iam_role_policy" "lambda_kms_policy" {
  name = "${var.project_name}-lambda-kms-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}


# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.minutes_analyzer.function_name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.project_name}-lambda-throttles-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors lambda throttles"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.minutes_analyzer.function_name
  }

  tags = var.common_tags
}
