require_relative 'secrets_manager'
require_relative 'gemini_client'
require_relative 'google_drive_client'
require_relative 'request_validator'
require_relative 'environment_config'
require_relative 'user_mapping_service'
require_relative 'integration_service'
require_relative 'response_builder'
require 'logger'

class LambdaHandler
  def initialize(logger: nil, secrets_manager: nil, gemini_client: nil, meeting_processor: nil)
    @logger = logger || Logger.new($stdout)
    @logger.level = ENV.fetch('LOG_LEVEL', 'INFO').upcase
    @secrets_manager = secrets_manager || SecretsManager.new(@logger)
    @gemini_client = gemini_client
    
    @config = EnvironmentConfig.new(@logger)
    @environment = @config.environment
    @validator = RequestValidator.new(@logger)
    @user_mapping_service = UserMappingService.new(@logger, @config)
    @integration_service = IntegrationService.new(@logger)
    
    # 後方互換性のため（テスト用）
    if meeting_processor
      @user_mapping_service.instance_variable_set(:@processor, meeting_processor)
    end
  end

  def handle(event:, context:)
    request_id = extract_request_id(context)
    @logger.info("Lambda function started. Request ID: #{request_id}")

    begin
      # リクエスト検証と解析
      parsed_body = @validator.validate_and_parse(event)
      file_id = parsed_body['file_id']
      file_name = parsed_body['file_name'] || 'Unknown'
      @logger.info("Received file_id: #{file_id}, file_name: #{file_name}")
      
      # シークレット取得と検証
      secrets = @secrets_manager.get_secrets
      validate_secrets(secrets)
      
      # Google Driveからファイル取得
      input_text = fetch_file_content(file_id, secrets)
      
      # Gemini APIで分析
      analysis_result = analyze_with_gemini(input_text, secrets)
      
      # ユーザーマッピング処理
      user_mappings = @user_mapping_service.process_mapping(file_id, secrets)
      analysis_result = @user_mapping_service.enrich_actions_with_assignees(analysis_result, user_mappings)
      
      # 外部サービス連携
      integration_results = @integration_service.process_integrations(analysis_result, secrets, user_mappings)
      
      # レスポンス生成
      ResponseBuilder.success_response(analysis_result, integration_results, user_mappings)
      
    rescue RequestValidator::ValidationError => e
      ResponseBuilder.error_response(400, e.message)
    rescue StandardError => e
      @logger.error("An unexpected error occurred: #{e.message}")
      @logger.error(e.backtrace.join("\n")) if e.backtrace
      ResponseBuilder.error_response(500, e.message)
    ensure
      @logger.info("Lambda function finished. Request ID: #{request_id}")
    end
  end

  private
  
  def extract_request_id(context)
    context.respond_to?(:aws_request_id) ? context.aws_request_id : "local_test_#{Time.now.to_i}"
  end
  
  def validate_secrets(secrets)
    validate_api_key(secrets)
    validate_google_credentials(secrets)
  end
  
  def validate_api_key(secrets)
    api_key = secrets['GEMINI_API_KEY']
    unless api_key && !api_key.empty?
      @logger.error('GEMINI_API_KEY is not available in secrets.')
      raise "Server configuration error: API key is missing."
    end
  end
  
  def validate_google_credentials(secrets)
    google_credentials = secrets['GOOGLE_SERVICE_ACCOUNT_JSON']
    unless google_credentials && !google_credentials.empty?
      @logger.error('GOOGLE_SERVICE_ACCOUNT_JSON is not available in secrets.')
      raise "Server configuration error: Google credentials missing."
    end
  end
  
  def fetch_file_content(file_id, secrets)
    google_credentials = secrets['GOOGLE_SERVICE_ACCOUNT_JSON']
    drive_client = GoogleDriveClient.new(google_credentials, @logger)
    drive_client.get_file_content(file_id)
  end
  
  def analyze_with_gemini(input_text, secrets)
    api_key = secrets['GEMINI_API_KEY']
    gemini_client = @gemini_client || GeminiClient.new(api_key, @logger, nil, @environment)
    
    # 精度向上のためGemini Clientを2回実行
    @logger.info("Starting first Gemini API analysis call...")
    first_analysis_result = gemini_client.analyze_meeting(input_text)
    @logger.info("Successfully received first analysis from Gemini API.")

    @logger.info("Starting second Gemini API analysis call for improved accuracy...")
    final_analysis_result = gemini_client.analyze_meeting(input_text)
    @logger.info("Successfully received second analysis from Gemini API.")

    @logger.info("Completed double Gemini Client execution for improved accuracy.")
    final_analysis_result
  end
end
