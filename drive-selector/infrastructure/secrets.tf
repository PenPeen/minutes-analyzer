# Secrets Manager secret for application credentials
resource "aws_secretsmanager_secret" "app_secrets" {
  name = "${var.project_name}-secrets-${var.environment}"
  
  description = "Secrets for Drive Selector Slack Bot"
  
  # 削除保護（本番環境のみ）
  recovery_window_in_days = var.environment == "production" ? 30 : 0

  tags = {
    Name        = "${var.project_name}-secrets-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Secret version with placeholder values
# 実際の値は手動またはCIで設定
resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  
  secret_string = jsonencode({
    SLACK_SIGNING_SECRET = var.slack_signing_secret
    SLACK_BOT_TOKEN     = var.slack_bot_token
    GOOGLE_CLIENT_ID    = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
  })
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}