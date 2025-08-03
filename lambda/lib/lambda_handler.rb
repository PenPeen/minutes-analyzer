require_relative 'secrets_manager'
require_relative 'gemini_client'
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

      success_response(summary)

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

  def error_response(status_code, error, details = nil)
    body = { error: error }
    body[:details] = details if details
    {
      statusCode: status_code,
      body: JSON.generate(body)
    }
  end

  def success_response(summary)
    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate({
        message: "Analysis complete.",
        summary: summary,
        integrations: {
          slack: ENV['SLACK_INTEGRATION'] == 'true' ? 'enabled' : 'disabled',
          notion: ENV['NOTION_INTEGRATION'] == 'true' ? 'enabled' : 'disabled'
        }
      })
    }
  end
end
