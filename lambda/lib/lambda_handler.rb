require_relative 'secrets_manager'
require_relative 'gemini_client'
require_relative 'slack_client'
require_relative 'notion_client'
require 'json'
require 'logger'

class LambdaHandler
  def initialize(logger: nil, secrets_manager: nil, gemini_client: nil)
    @logger = logger || Logger.new($stdout)
    @logger.level = ENV.fetch('LOG_LEVEL', 'INFO').upcase
    @secrets_manager = secrets_manager || SecretsManager.new(@logger)
    @gemini_client = gemini_client
  end

  def handle(event:, context:)
    request_id = context.respond_to?(:aws_request_id) ? context.aws_request_id : "local_test_#{Time.now.to_i}"
    @logger.info("Lambda function started. Request ID: #{request_id}")

    begin
      secrets = @secrets_manager.get_secrets
      api_key = secrets['GEMINI_API_KEY']
      
      unless api_key && !api_key.empty?
        @logger.error('GEMINI_API_KEY is not available in secrets.')
        return error_response(500, 'Server configuration error: API key is missing.')
      end

      body = event['body']
      unless body
        @logger.error("Request body is missing.")
        return error_response(400, "Request body is missing.")
      end

      input_text = JSON.parse(body)['text']
      @logger.info("Input text received: #{input_text.length} characters")

      gemini_client = @gemini_client || GeminiClient.new(api_key, @logger)
      summary = gemini_client.summarize(input_text)

      @logger.info("Successfully received summary from Gemini API.")

      # 外部サービス連携処理
      integration_results = process_integrations(summary, secrets)

      success_response(summary, integration_results[:slack], integration_results[:notion])

    rescue JSON::ParserError => e
      @logger.error("Invalid JSON in request body: #{e.message}")
      error_response(400, "Invalid JSON in request body: #{e.message}")
    rescue StandardError => e
      @logger.error("An unexpected error occurred: #{e.message}")
      @logger.error(e.backtrace.join("\n"))
      error_response(500, "An unexpected error occurred.", e.message)
    ensure
      @logger.info("Lambda function finished. Request ID: #{request_id}")
    end
  end

  private

  def process_integrations(summary, secrets)
    results = {
      slack: nil,
      notion: nil
    }

    # Slack通知処理
    begin
      slack_webhook_url = secrets['SLACK_WEBHOOK_URL']
      if slack_webhook_url && !slack_webhook_url.empty?
        @logger.info("Sending Slack notification")
        slack_client = SlackClient.new(slack_webhook_url, @logger)
        results[:slack] = slack_client.send_notification(summary)
      else
        @logger.warn("Slack webhook URL is not configured")
      end
    rescue StandardError => e
      @logger.error("Slack integration failed: #{e.message}")
      results[:slack] = { success: false, error: e.message }
    end

    # Notion連携処理
    begin
      notion_api_key = secrets['NOTION_API_KEY']
      notion_database_id = secrets['NOTION_DATABASE_ID']
      notion_task_database_id = secrets['NOTION_TASK_DATABASE_ID']
      
      if notion_api_key && !notion_api_key.empty? && notion_database_id && !notion_database_id.empty?
        @logger.info("Creating meeting page in Notion")
        notion_client = NotionClient.new(notion_api_key, notion_database_id, notion_task_database_id, @logger)
        results[:notion] = notion_client.create_meeting_page(summary)
      else
        @logger.warn("Notion API key or database ID is not configured")
      end
    rescue StandardError => e
      @logger.error("Notion integration failed: #{e.message}")
      results[:notion] = { success: false, error: e.message }
    end

    results
  end

  def error_response(status_code, error, details = nil)
    body = { error: error }
    body[:details] = details if details
    {
      statusCode: status_code,
      body: JSON.generate(body)
    }
  end

  def success_response(summary, slack_result = nil, notion_result = nil)
    response_body = {
      message: "Analysis complete.",
      summary: summary,
      integrations: {
        slack: slack_result && slack_result[:success] ? 'sent' : 'not_sent',
        notion: notion_result && notion_result[:success] ? 'created' : 'not_created'
      }
    }

    # Add Slack notification result if available
    if slack_result
      response_body[:slack_notification] = slack_result
    end

    # Add Notion result if available
    if notion_result
      response_body[:notion_result] = notion_result
    end

    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate(response_body)
    }
  end
end
