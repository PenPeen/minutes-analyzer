# CloudWatch Alarms for monitoring

# Lambda関数のエラー率アラーム
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  alarm_name          = "${var.project_name}-error-rate-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors lambda error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.minutes_analyzer.function_name
  }

  tags = var.common_tags
}

# Lambda関数のタイムアウトアラーム
resource "aws_cloudwatch_metric_alarm" "lambda_timeout" {
  alarm_name          = "${var.project_name}-timeout-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Maximum"
  threshold           = (var.lambda_timeout * 1000) * 0.95  # 95% of timeout
  alarm_description   = "This metric monitors lambda execution time"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.minutes_analyzer.function_name
  }

  tags = var.common_tags
}

# API Rate Limit到達アラーム
resource "aws_cloudwatch_metric_alarm" "api_rate_limit" {
  alarm_name          = "${var.project_name}-api-rate-limit-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "APICallCount"
  namespace           = "MinutesAnalyzer"
  period              = "60"
  statistic           = "Sum"
  threshold           = "45"  # Slack API limit is 50/min
  alarm_description   = "This metric monitors API rate limit"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
    api_name    = "Slack"
  }

  tags = var.common_tags
}

# 処理成功率アラーム
resource "aws_cloudwatch_metric_alarm" "success_rate" {
  alarm_name          = "${var.project_name}-success-rate-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "SuccessRate"
  namespace           = "MinutesAnalyzer"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors processing success rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
  }

  tags = var.common_tags
}

# Lambda関数の同時実行数アラーム
resource "aws_cloudwatch_metric_alarm" "lambda_concurrent_executions" {
  alarm_name          = "${var.project_name}-concurrent-executions-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConcurrentExecutions"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "50"
  alarm_description   = "This metric monitors lambda concurrent executions"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.minutes_analyzer.function_name
  }

  tags = var.common_tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "minutes_analyzer" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum", label = "Invocations" }],
            [".", "Errors", { stat = "Sum", label = "Errors" }],
            [".", "Duration", { stat = "Average", label = "Avg Duration" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Lambda Function Metrics"
          period  = 300
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["MinutesAnalyzer", "TotalParticipants", { stat = "Sum" }],
            [".", "MappedSlackUsers", { stat = "Sum" }],
            [".", "MappedNotionUsers", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Participant Mapping Metrics"
          period  = 300
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["MinutesAnalyzer", "APICallCount", { stat = "Sum", dimensions = { api_name = "Slack" } }],
            [".", ".", { stat = "Sum", dimensions = { api_name = "Notion" } }],
            [".", ".", { stat = "Sum", dimensions = { api_name = "Calendar" } }]
          ]
          view    = "timeSeries"
          stacked = true
          region  = var.aws_region
          title   = "API Call Counts"
          period  = 60
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["MinutesAnalyzer", "SuccessRate", { stat = "Average" }]
          ]
          view    = "singleValue"
          region  = var.aws_region
          title   = "Overall Success Rate"
          period  = 3600
        }
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '/aws/lambda/${var.project_name}-${var.environment}' | fields @timestamp, @message | filter level = 'ERROR' | sort @timestamp desc | limit 20"
          region  = var.aws_region
          title   = "Recent Errors"
        }
      }
    ]
  })
}