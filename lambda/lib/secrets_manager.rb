require 'aws-sdk-secretsmanager'
require 'json'

class SecretsManager
  def initialize(logger, client: nil)
    @logger = logger
    @client = client
    @secrets_cache = nil
  end

  def get_secrets
    return @secrets_cache if @secrets_cache

    secret_name = ENV['APP_SECRETS_NAME']
    unless secret_name
      @logger.error('APP_SECRETS_NAME environment variable is not set')
      raise 'APP_SECRETS_NAME not configured'
    end

    begin
      client = @client || build_client
      response = client.get_secret_value(secret_id: secret_name)
      
      @secrets_cache = JSON.parse(response.secret_string)
      @logger.info("Successfully retrieved secrets from: #{secret_name}")
      @secrets_cache
    rescue Aws::SecretsManager::Errors::ResourceNotFoundException
      @logger.error("Secret '#{secret_name}' not found")
      raise "Secret not found: #{secret_name}"
    rescue Aws::SecretsManager::Errors::ServiceError => e
      @logger.error("AWS Secrets Manager error: #{e.message}")
      raise "Failed to retrieve secrets: #{e.message}"
    rescue JSON::ParserError => e
      @logger.error("Failed to parse secret JSON: #{e.message}")
      raise "Invalid secret format: #{e.message}"
    rescue StandardError => e
      @logger.error("Unexpected error retrieving secrets: #{e.message}")
      raise "Secret retrieval failed: #{e.message}"
    end
  end

  private

  def build_client
    client_options = { region: ENV['AWS_REGION'] || 'ap-northeast-1' }
    client_options[:endpoint] = ENV['AWS_ENDPOINT_URL'] if ENV['AWS_ENDPOINT_URL']
    Aws::SecretsManager::Client.new(client_options)
  end
end
