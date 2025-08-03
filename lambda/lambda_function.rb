require 'json'
require 'net/http'
require 'uri'
require 'logger'
require 'aws-sdk-secretsmanager'

# Initialize logger
LOGGER = Logger.new($stdout)
LOGGER.level = ENV.fetch('LOG_LEVEL', 'INFO').upcase

# Constants
GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'.freeze
GEMINI_MODEL = 'gemini-2.5-flash'.freeze

# Secrets cache to avoid repeated API calls
@secrets_cache = nil

def lambda_handler(event:, context:)
  request_id = context.respond_to?(:aws_request_id) ? context.aws_request_id : "local_test_#{Time.now.to_i}"
  LOGGER.info("Lambda function started. Request ID: #{request_id}")

  begin
    secrets = get_secrets
    api_key = secrets['GEMINI_API_KEY']
    
    unless api_key && !api_key.empty?
      LOGGER.error('GEMINI_API_KEY is not available in secrets.')
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

def get_secrets
  return @secrets_cache if @secrets_cache

  secret_name = ENV['APP_SECRETS_NAME']
  unless secret_name
    LOGGER.error('APP_SECRETS_NAME environment variable is not set')
    raise 'APP_SECRETS_NAME not configured'
  end

  begin
    # AWS Secrets Manager client configuration
    client_options = { region: ENV['AWS_REGION'] || 'ap-northeast-1' }
    
    # LocalStack support
    if ENV['AWS_ENDPOINT_URL']
      client_options[:endpoint] = ENV['AWS_ENDPOINT_URL']
    end
    
    client = Aws::SecretsManager::Client.new(client_options)
    response = client.get_secret_value(secret_id: secret_name)
    
    @secrets_cache = JSON.parse(response.secret_string)
    LOGGER.info("Successfully retrieved secrets from: #{secret_name}")
    @secrets_cache
  rescue Aws::SecretsManager::Errors::ResourceNotFoundException
    LOGGER.error("Secret '#{secret_name}' not found")
    raise "Secret not found: #{secret_name}"
  rescue Aws::SecretsManager::Errors::ServiceError => e
    LOGGER.error("AWS Secrets Manager error: #{e.message}")
    raise "Failed to retrieve secrets: #{e.message}"
  rescue JSON::ParserError => e
    LOGGER.error("Failed to parse secret JSON: #{e.message}")
    raise "Invalid secret format: #{e.message}"
  rescue StandardError => e
    LOGGER.error("Unexpected error retrieving secrets: #{e.message}")
    raise "Secret retrieval failed: #{e.message}"
  end
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