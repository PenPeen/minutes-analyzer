require 'json'
require 'net/http'
require 'uri'
require 'logger'

# Initialize logger
LOGGER = Logger.new($stdout)
LOGGER.level = ENV.fetch('LOG_LEVEL', 'INFO').upcase

# Constants
CLAUDE_API_URL = 'https://api.anthropic.com/v1/messages'.freeze
CLAUDE_MODEL = 'claude-3-5-haiku-20241022'.freeze

def lambda_handler(event:, context:)
  # In a real Lambda environment, context object is provided. For local testing, we can use a mock.
  request_id = context.respond_to?(:aws_request_id) ? context.aws_request_id : "local_test_#{Time.now.to_i}"
  LOGGER.info("Lambda function started. Request ID: #{request_id}")

  begin
    api_key = ENV['CLAUDE_API_KEY']
    unless api_key && !api_key.empty?
      LOGGER.error('CLAUDE_API_KEY is not set or is empty.')
      return {
        statusCode: 500,
        body: JSON.generate({ error: 'Server configuration error: API key is missing.' })
      }
    end

    body = event['body']
    unless body
        LOGGER.error("Request body is missing.")
        return { statusCode: 400, body: JSON.generate({error: "Request body is missing."}) }
    end

    input_text = JSON.parse(body)['text']
    LOGGER.info("Input text received: #{input_text.length} characters")

    claude_response = call_claude_api(api_key, input_text)
    summary = claude_response.dig("content", 0, "text")

    unless summary
        LOGGER.error("Failed to extract summary from Claude response: #{claude_response}")
        raise "Summary could not be generated from API response."
    end

    LOGGER.info("Successfully received summary from Claude API.")

    response = {
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

  rescue JSON::ParserError => e
    LOGGER.error("Invalid JSON in request body: #{e.message}")
    return {
      statusCode: 400,
      body: JSON.generate({ error: "Invalid JSON in request body: #{e.message}" })
    }
  rescue StandardError => e
    LOGGER.error("An unexpected error occurred: #{e.message}")
    LOGGER.error(e.backtrace.join("\n"))
    return {
      statusCode: 500,
      body: JSON.generate({
        error: "An unexpected error occurred.",
        details: e.message
      })
    }
  end

  LOGGER.info("Lambda function finished successfully. Request ID: #{request_id}")
  response
end

def call_claude_api(api_key, text)
  uri = URI.parse(CLAUDE_API_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri.request_uri)
  request['x-api-key'] = api_key
  request['anthropic-version'] = '2023-06-01'
  request['content-type'] = 'application/json'

  request.body = {
    model: CLAUDE_MODEL,
    max_tokens: 1024,
    messages: [
      { role: "user", content: "Please summarize the following meeting transcript:\n\n#{text}" }
    ]
  }.to_json

  LOGGER.info("Calling Claude API...")
  response = http.request(request)
  LOGGER.info("Claude API response status: #{response.code}")

  JSON.parse(response.body)
end

# Example of how to test this function locally
if __FILE__ == $0
  # Mock context object for local testing
  MockContext = Struct.new(:aws_request_id)
  mock_context = MockContext.new("local_test_#{Time.now.to_i}")

  mock_event = {
    'body' => JSON.generate({ text: 'Hello, this is a test transcript for summarization.' })
  }

  # --- Test Case 1: Success (with mocked API call) ---
  LOGGER.info("--- Running local test (Success with Mock) ---")
  # To prevent real API call with a dummy key, we can mock the API call itself for this local test
  # In a real test environment, you might use a library like WebMock.
  self.class.send(:define_method, :call_claude_api) do |api_key, text|
    LOGGER.info("--- MOCKING call_claude_api ---")
    { "content" => [{ "text" => "This is a mock summary." }] }
  end
  ENV['CLAUDE_API_KEY'] = 'dummy-key'
  ENV['SLACK_INTEGRATION'] = 'true'
  result = lambda_handler(event: mock_event, context: mock_context)
  LOGGER.info("Result:\n#{JSON.pretty_generate(result)}")
  LOGGER.info("---------------------------------------------")


  # --- Test Case 2: Missing API Key ---
  LOGGER.info("--- Running error test (Missing API key) ---")
  ENV['CLAUDE_API_KEY'] = nil
  result = lambda_handler(event: mock_event, context: mock_context)
  LOGGER.info("Result:\n#{JSON.pretty_generate(result)}")
  LOGGER.info("------------------------------------------")
end
