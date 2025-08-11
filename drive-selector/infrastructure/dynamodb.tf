# DynamoDB table for storing OAuth tokens
resource "aws_dynamodb_table" "oauth_tokens" {
  name           = "${var.project_name}-oauth-tokens-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  # 暗号化設定
  server_side_encryption {
    enabled = true
  }

  # TTL設定（オプション：90日後に自動削除）
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = var.environment == "production" ? true : false
  }

  tags = {
    Name        = "${var.project_name}-oauth-tokens-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# DynamoDB table for storing user preferences (optional)
resource "aws_dynamodb_table" "user_preferences" {
  name           = "${var.project_name}-user-preferences-${var.environment}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-user-preferences-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}