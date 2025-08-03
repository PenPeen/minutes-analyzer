require 'json'
require 'net/http'
require 'uri'
require 'logger'

# Initialize logger
LOGGER = Logger.new($stdout)
LOGGER.level = ENV.fetch('LOG_LEVEL', 'INFO').upcase

# Constants
GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'.freeze
GEMINI_MODEL = 'gemini-2.5-flash'.freeze

def lambda_handler(event:, context:)
  # In a real Lambda environment, context object is provided. For local testing, we can use a mock.
  request_id = context.respond_to?(:aws_request_id) ? context.aws_request_id : "local_test_#{Time.now.to_i}"
  LOGGER.info("Lambda function started. Request ID: #{request_id}")

  begin
    api_key = ENV['GEMINI_API_KEY']
    unless api_key && !api_key.empty?
      LOGGER.error('GEMINI_API_KEY is not set or is empty.')
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

    gemini_response = call_gemini_api(api_key, input_text)
    summary = gemini_response.dig("candidates", 0, "content", "parts", 0, "text")

    unless summary
        LOGGER.error("Failed to extract summary from Gemini response: #{gemini_response}")
        raise "Summary could not be generated from API response."
    end

    LOGGER.info("Successfully received summary from Gemini API.")

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

def call_gemini_api(api_key, text)
  uri = URI.parse("#{GEMINI_API_URL}?key=#{api_key}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri.request_uri)
  request['content-type'] = 'application/json'

  request.body = {
    contents: [
      {
        parts: [
          { text: "Please summarize the following meeting transcript:\n\n#{text}" }
        ]
      }
    ],
    generationConfig: {
      maxOutputTokens: 1024
    }
  }.to_json

  LOGGER.info("Calling Gemini API...")
  response = http.request(request)
  LOGGER.info("Gemini API response status: #{response.code}")

  unless response.is_a?(Net::HTTPSuccess)
    error_body = JSON.parse(response.body) rescue { error: { message: response.body } }
    error_message = error_body.dig("error", "message") || "Unknown API error"
    LOGGER.error("Gemini API request failed with status #{response.code}: #{error_message}")
    case response.code.to_i
    when 401, 403
      raise "Authentication failed with Gemini API. Please check your API key. Details: #{error_message}"
    else
      raise "Gemini API request failed. Status: #{response.code}, Details: #{error_message}"
    end
  end

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

  # Store the original API key to restore it after tests
  original_api_key = ENV['GEMINI_API_KEY']

  # --- Test Case 1: Success (with real API call if key is present) ---
  LOGGER.info("--- Running local test (Success Case) ---")
  if original_api_key && !original_api_key.empty?
    LOGGER.info("GEMINI_API_KEY is set. Calling the actual Gemini API.")
    ENV['SLACK_INTEGRATION'] = 'true'
    result = lambda_handler(event: mock_event, context: mock_context)
    LOGGER.info("Result:\n#{JSON.pretty_generate(result)}")
  else
    LOGGER.warn("GEMINI_API_KEY is not set. Skipping the success case test with a real API call.")
    LOGGER.warn("To run the full local test, please set the GEMINI_API_KEY environment variable.")
  end
  LOGGER.info("---------------------------------------------")


  # --- Test Case 2: Missing API Key ---
  LOGGER.info("--- Running error test (Missing API key) ---")
  ENV['GEMINI_API_KEY'] = nil # Temporarily unset the key for this test
  result = lambda_handler(event: mock_event, context: mock_context)
  LOGGER.info("Result:\n#{JSON.pretty_generate(result)}")
  LOGGER.info("------------------------------------------")

  # Restore the original API key if it existed
  ENV['GEMINI_API_KEY'] = original_api_key if original_api_key
end
