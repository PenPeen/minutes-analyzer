require 'aws-sdk-s3'
require 'json'

class S3Client
  def initialize(logger, environment = ENV.fetch('ENVIRONMENT', 'production'))
    @logger = logger
    @environment = environment
    @bucket_name = ENV.fetch('S3_PROMPTS_BUCKET', "minutes-analyzer-prompts-#{@environment}")
    @s3_client = create_s3_client
  end

  def get_prompt
    key = 'prompts/meeting_analysis_prompt.txt'
    
    @logger.info("Fetching prompt from S3: #{@bucket_name}/#{key}")
    
    begin
      response = @s3_client.get_object(bucket: @bucket_name, key: key)
      prompt = response.body.read.force_encoding('UTF-8')
      @logger.info("Successfully retrieved prompt (#{prompt.bytesize} bytes)")
      prompt
    rescue Aws::S3::Errors::ServiceError => e
      @logger.error("Failed to fetch prompt from S3: #{e.message}")
      raise "Unable to retrieve prompt from S3: #{e.message}"
    end
  end

  def get_verification_prompt
    key = 'prompts/meeting_verification_prompt.txt'
    
    @logger.info("Fetching verification prompt from S3: #{@bucket_name}/#{key}")
    
    begin
      response = @s3_client.get_object(bucket: @bucket_name, key: key)
      prompt = response.body.read.force_encoding('UTF-8')
      @logger.info("Successfully retrieved verification prompt (#{prompt.bytesize} bytes)")
      prompt
    rescue Aws::S3::Errors::ServiceError => e
      @logger.error("Failed to fetch verification prompt from S3: #{e.message}")
      raise "Unable to retrieve verification prompt from S3: #{e.message}"
    end
  end

  def get_output_schema
    key = 'schemas/output_schema.json'
    
    @logger.info("Fetching output schema from S3: #{@bucket_name}/#{key}")
    
    begin
      response = @s3_client.get_object(bucket: @bucket_name, key: key)
      schema_json = response.body.read.force_encoding('UTF-8')
      schema = JSON.parse(schema_json)
      @logger.info("Successfully retrieved output schema")
      schema
    rescue Aws::S3::Errors::ServiceError => e
      @logger.error("Failed to fetch output schema from S3: #{e.message}")
      raise "Unable to retrieve output schema from S3: #{e.message}"
    rescue JSON::ParserError => e
      @logger.error("Invalid JSON in output schema: #{e.message}")
      raise "Invalid output schema format: #{e.message}"
    end
  end

  private

  def create_s3_client
    options = {
      region: ENV.fetch('AWS_REGION', 'ap-northeast-1'),
      logger: @logger,
      log_level: :debug
    }

    Aws::S3::Client.new(options)
  end
end