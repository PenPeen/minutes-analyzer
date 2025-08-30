require_relative 'secrets_manager'
require_relative 'gemini_client'
require_relative 'google_drive_client'
require_relative 'request_validator'
require_relative 'integration_service'
require_relative 'response_builder'
require_relative 's3_client'
require 'logger'
require 'json'

class LambdaHandler
  def initialize(logger: nil, secrets_manager: nil, gemini_client: nil, s3_client: nil)
    @logger = logger || Logger.new($stdout)
    @logger.level = ENV.fetch('LOG_LEVEL', 'INFO').upcase
    @secrets_manager = secrets_manager || SecretsManager.new(@logger)
    @gemini_client = gemini_client
    
    @environment = ENV.fetch('ENVIRONMENT', 'local')
    @validator = RequestValidator.new(@logger)
    @integration_service = IntegrationService.new(@logger)
    @s3_client = s3_client || S3Client.new(@logger, @environment)
  end

  def handle(event:, context:)
    request_id = extract_request_id(context)
    @logger.info("Lambda function started. Request ID: #{request_id}")

    begin
      # リクエスト検証と解析
      parsed_body = @validator.validate_and_parse(event)
      file_id = parsed_body['file_id']
      file_name = parsed_body['file_name'] || 'Unknown'
      user_id = parsed_body['slack_user_id']
      user_email = parsed_body['slack_user_email']
      input_type = parsed_body['input_type']
      google_doc_url = parsed_body['google_doc_url']
      
      @logger.info("Received file_id: #{file_id}, file_name: #{file_name}")
      @logger.info("Input type: #{input_type}")
      @logger.info("Google Doc URL: #{google_doc_url}") if google_doc_url
      @logger.info("Executor user_id: #{user_id}, user_email: #{user_email}") if user_id
      
      # シークレット取得と検証
      secrets = @secrets_manager.get_secrets
      validate_secrets(secrets)
      
      # Google Driveからファイル取得
      drive_result = fetch_file_content(file_id, secrets)
      input_text = drive_result[:content]
      file_metadata = drive_result[:metadata]
      
      # Gemini APIで分析
      analysis_result = analyze_with_gemini(input_text, secrets)
      
      # オリジナルファイル名を追加（タイトル整形用）
      analysis_result['original_file_name'] = file_metadata[:name] || file_name
      
      # ファイルメタデータを追加（Notion連携用）
      analysis_result['file_metadata'] = file_metadata
      
      # URL入力の場合は追加の情報を含める
      if input_type == 'url' && google_doc_url
        analysis_result['source_url'] = google_doc_url
        analysis_result['input_type'] = 'url'
      end
      
      # 外部サービス連携（実行者情報を追加）
      executor_info = { user_id: user_id, user_email: user_email }
      integration_results = @integration_service.process_integrations(analysis_result, secrets, {}, executor_info)
      
      # レスポンス生成
      ResponseBuilder.success_response(analysis_result, integration_results, {})
      
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
    slack_notification_service = create_slack_notification_service(secrets)
    drive_client = GoogleDriveClient.new(google_credentials, @logger, slack_notification_service)
    drive_client.get_file_content(file_id)  # {content: ..., metadata: ...} を返す
  end

  def create_slack_notification_service(secrets)
    bot_token = secrets['SLACK_BOT_TOKEN']
    channel_id = secrets['SLACK_CHANNEL_ID']
    
    return nil unless bot_token && channel_id
    
    require_relative 'slack_notification_service'
    SlackNotificationService.new(bot_token, channel_id, @logger)
  rescue => e
    @logger.warn("Failed to create Slack notification service: #{e.message}")
    nil
  end
  
  def analyze_with_gemini(input_text, secrets)
    api_key = secrets['GEMINI_API_KEY']
    gemini_client = @gemini_client || GeminiClient.new(api_key, @logger, nil, @environment)
    
    # 1回目：標準分析
    @logger.info("Starting first Gemini API analysis call (standard analysis)...")
    standard_result = gemini_client.analyze_meeting(input_text)
    @logger.info("Successfully received standard analysis from Gemini API.")

    # 2回目：検証・精査分析
    @logger.info("Starting second Gemini API analysis call (verification analysis)...")
    verification_prompt = build_verification_prompt(input_text, standard_result)
    verified_result = gemini_client.analyze_meeting(verification_prompt)
    @logger.info("Successfully received verification analysis from Gemini API.")

    @logger.info("Completed 2-phase Gemini analysis for improved accuracy.")
    verified_result
  end

  def build_verification_prompt(original_transcript, initial_analysis)
    @logger.info("Building verification prompt from standard analysis result...")
    
    begin
      verification_prompt_template = @s3_client.get_verification_prompt
      
      verification_data = {
        "original_transcript" => original_transcript,
        "initial_analysis" => initial_analysis
      }
      
      # テンプレートの末尾に検証データを JSON 形式で追加
      "#{verification_prompt_template}\n\n# 検証対象データ\n```json\n#{JSON.pretty_generate(verification_data)}\n```"
      
    rescue StandardError => e
      @logger.error("Failed to build verification prompt: #{e.message}")
      raise "Unable to build verification prompt: #{e.message}"
    end
  end
end
