# SQS Dead Letter Queue for failed Lambda invocations

# Dead Letter Queue
resource "aws_sqs_queue" "lambda_dlq" {
  name                       = "${var.project_name}-dlq-${var.environment}"
  message_retention_seconds  = 1209600  # 14 days
  visibility_timeout_seconds = 300
  
  tags = var.common_tags
}

# DLQ Policy
resource "aws_sqs_queue_policy" "lambda_dlq_policy" {
  queue_url = aws_sqs_queue.lambda_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.lambda_dlq.arn
      }
    ]
  })
}

# Main processing queue (optional - for async processing)
resource "aws_sqs_queue" "processing_queue" {
  name                       = "${var.project_name}-queue-${var.environment}"
  visibility_timeout_seconds = var.lambda_timeout + 30  # Lambda timeout + buffer
  message_retention_seconds  = 86400  # 1 day
  max_message_size          = 262144  # 256 KB
  receive_wait_time_seconds = 10      # Long polling
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.lambda_dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = var.common_tags
}

# Lambda permissions for DLQ
resource "aws_iam_role_policy" "lambda_dlq_policy" {
  name = "${var.project_name}-lambda-dlq-policy-${var.environment}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.lambda_dlq.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.processing_queue.arn
      }
    ]
  })
}

# Lambda Dead Letter Queue configuration
resource "aws_lambda_function_event_invoke_config" "dlq_config" {
  function_name = aws_lambda_function.minutes_analyzer.function_name

  destination_config {
    on_failure {
      destination = aws_sqs_queue.lambda_dlq.arn
    }
  }
  
  maximum_retry_attempts = 2
}

# CloudWatch Alarm for DLQ messages
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project_name}-dlq-messages-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when messages are in the DLQ"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.lambda_dlq.name
  }

  tags = var.common_tags
}