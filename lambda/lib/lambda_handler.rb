require_relative 'secrets_manager'
require_relative 'gemini_client'
require_relative 'slack_client'
require_relative 'notion_client'
require_relative 'google_drive_client'
require_relative 'meeting_transcript_processor'
require 'json'
require 'logger'
require 'timeout'

class LambdaHandler
  def initialize(logger: nil, secrets_manager: nil, gemini_client: nil, meeting_processor: nil)
    @logger = logger || Logger.new($stdout)
    @logger.level = ENV.fetch('LOG_LEVEL', 'INFO').upcase
    @secrets_manager = secrets_manager || SecretsManager.new(@logger)
    @gemini_client = gemini_client
    @meeting_processor = meeting_processor
    @environment = ENV.fetch('ENVIRONMENT', 'local')
    
    # ユーザーマッピング機能の設定を読み込み
    @google_calendar_enabled = ENV.fetch('GOOGLE_CALENDAR_ENABLED', 'false').downcase == 'true'
    @user_mapping_enabled = ENV.fetch('USER_MAPPING_ENABLED', 'false').downcase == 'true'
    
    @logger.info("Google Calendar integration: #{@google_calendar_enabled ? 'enabled' : 'disabled'}")
    @logger.info("User mapping: #{@user_mapping_enabled ? 'enabled' : 'disabled'}")
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

      parsed_body = JSON.parse(body)
      
      # Extract file_id from request
      file_id = parsed_body['file_id']
      unless file_id
        @logger.error("file_id is missing in request body")
        return error_response(400, "Request must include 'file_id' field")
      end
      
      file_name = parsed_body['file_name'] || 'Unknown'
      @logger.info("Received file_id: #{file_id}, file_name: #{file_name}")
      
      # Get Google service account credentials from secrets
      google_credentials = secrets['GOOGLE_SERVICE_ACCOUNT_JSON']
      unless google_credentials && !google_credentials.empty?
        @logger.error('GOOGLE_SERVICE_ACCOUNT_JSON is not available in secrets.')
        return error_response(500, 'Server configuration error: Google credentials missing.')
      end
      
      # Fetch file content from Google Drive
      require_relative 'google_drive_client' unless defined?(GoogleDriveClient)
      drive_client = GoogleDriveClient.new(google_credentials, @logger)
      input_text = drive_client.get_file_content(file_id)

      gemini_client = @gemini_client || GeminiClient.new(api_key, @logger, nil, @environment)
      analysis_result = gemini_client.analyze_meeting(input_text)

      @logger.info("Successfully received analysis from Gemini API.")

      # ユーザーマッピング処理（オプション）
      user_mappings = {}
      if @google_calendar_enabled && @user_mapping_enabled
        user_mappings = process_user_mapping(file_id, secrets)
        
        # Gemini分析結果のアクション項目に担当者を自動設定
        if user_mappings[:status] == 'completed' && user_mappings[:user_mappings]
          analysis_result = enrich_actions_with_assignees(analysis_result, user_mappings)
        end
      end

      # 外部サービス連携処理
      integration_results = process_integrations(analysis_result, secrets, user_mappings)

      # レスポンスにユーザーマッピング結果を含める
      response = success_response(analysis_result, integration_results[:slack], integration_results[:notion])
      if user_mappings && !user_mappings.empty?
        response_body = JSON.parse(response[:body])
        response_body[:user_mappings] = user_mappings
        response[:body] = JSON.generate(response_body)
      end
      
      response

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

  def process_user_mapping(file_id, secrets)
    @logger.info("Starting user mapping for file_id: #{file_id}")
    
    begin
      # MeetingTranscriptProcessorのインスタンスを作成
      if @meeting_processor.nil?
        config = {
          google_calendar_enabled: @google_calendar_enabled,
          user_mapping_enabled: @user_mapping_enabled,
          google_service_account_json: secrets['GOOGLE_SERVICE_ACCOUNT_JSON'],
          slack_bot_token: secrets['SLACK_BOT_TOKEN'],
          notion_api_key: secrets['NOTION_API_KEY'],
          parallel_processing: true,
          max_threads: 10,
          api_timeout: 30  # 各APIのタイムアウト設定（秒）
        }
        
        @meeting_processor = MeetingTranscriptProcessor.new(config)
      end
      
      # ファイルIDから会議を特定し、参加者をマッピング
      result = nil
      Timeout.timeout(60) do  # 全体のタイムアウトを60秒に設定
        result = @meeting_processor.process_transcript(file_id)
      end
      
      if result[:status] == 'completed'
        @logger.info("User mapping completed successfully")
        @logger.info("Found #{result[:participants]&.length || 0} participants")
        
        # 統計情報をログに出力
        stats = @meeting_processor.get_statistics
        @logger.info("User mapping statistics: #{stats.to_json}")
        
        # 部分的な成功も許容（一部のユーザーがマッピングできなくても継続）
        if result[:user_mappings]
          successful_mappings = count_successful_mappings(result[:user_mappings])
          @logger.info("Successfully mapped #{successful_mappings[:slack]} Slack users and #{successful_mappings[:notion]} Notion users")
          
          # マッピングできなかったユーザーの詳細をログに記録
          log_unmapped_users(result)
        end
      elsif result[:status] == 'partial'
        @logger.warn("User mapping partially completed: #{result[:warnings]&.join(', ')}")
        # 部分的な成功でも処理を継続
      else
        @logger.warn("User mapping failed: #{result[:errors]&.join(', ')}")
      end
      
      result
    rescue Timeout::Error => e
      @logger.error("User mapping timeout after 60 seconds")
      {
        status: 'partial',
        error: 'Timeout during user mapping',
        file_id: file_id,
        warnings: ['Some user mappings may be incomplete due to timeout']
      }
    rescue StandardError => e
      # Calendar API接続エラーなどの場合もフォールバック
      @logger.error("Error in user mapping process: #{e.message}")
      @logger.error(e.backtrace.first(5).join("\n"))
      
      # エラーでも基本的な情報は返す
      {
        status: 'partial',
        error: e.message,
        file_id: file_id,
        warnings: ['User mapping unavailable, continuing without it'],
        user_mappings: { slack: {}, notion: {} }
      }
    end
  end
  
  def count_successful_mappings(user_mappings)
    slack_count = user_mappings[:slack]&.select { |_, v| v && !v[:error] }&.size || 0
    notion_count = user_mappings[:notion]&.select { |_, v| v && !v[:error] }&.size || 0
    
    { slack: slack_count, notion: notion_count }
  end
  
  def log_unmapped_users(result)
    unmapped = []
    
    result[:participants]&.each do |email|
      slack_mapped = result[:user_mappings][:slack]&.key?(email)
      notion_mapped = result[:user_mappings][:notion]&.key?(email)
      
      unless slack_mapped && notion_mapped
        unmapped_services = []
        unmapped_services << 'Slack' unless slack_mapped
        unmapped_services << 'Notion' unless notion_mapped
        unmapped << "#{email} (#{unmapped_services.join(', ')})"
      end
    end
    
    if unmapped.any?
      @logger.info("Unmapped users: #{unmapped.join('; ')}")
    end
  end

  def enrich_actions_with_assignees(analysis_result, user_mappings)
    return analysis_result unless analysis_result.is_a?(Hash) && analysis_result['actions'].is_a?(Array)
    
    @logger.info("Enriching actions with user mapping data")
    
    # アクション項目に担当者情報を追加
    analysis_result['actions'].each do |action|
      next unless action['assignee']
      
      # 担当者名からメールアドレスを推測（参加者リストから照合）
      assignee_email = find_email_for_assignee(action['assignee'], user_mappings[:participants])
      
      if assignee_email
        # Notionユーザー情報を追加
        if user_mappings[:user_mappings][:notion] && user_mappings[:user_mappings][:notion][assignee_email]
          notion_user = user_mappings[:user_mappings][:notion][assignee_email]
          action['notion_user_id'] = notion_user[:id] if notion_user[:id]
          action['assignee_email'] = assignee_email
          @logger.debug("Added Notion user ID for #{action['assignee']}: #{notion_user[:id]}")
        end
        
        # Slackメンション情報を追加
        if user_mappings[:user_mappings][:slack] && user_mappings[:user_mappings][:slack][assignee_email]
          slack_user = user_mappings[:user_mappings][:slack][assignee_email]
          action['slack_user_id'] = slack_user[:id] if slack_user[:id]
          action['slack_mention'] = "<@#{slack_user[:id]}>" if slack_user[:id]
          @logger.debug("Added Slack mention for #{action['assignee']}: <@#{slack_user[:id]}>")
        end
      end
    end
    
    analysis_result
  end

  def find_email_for_assignee(assignee_name, participants)
    return nil unless assignee_name && participants
    
    # 完全一致を試みる
    participant = participants.find { |p| p&.downcase == assignee_name.downcase }
    return participant if participant
    
    # 部分一致を試みる（名前の一部が含まれる場合）
    participants.find do |p|
      next unless p
      p.downcase.include?(assignee_name.downcase) || assignee_name.downcase.include?(p.split('@').first.downcase)
    end
  end

  def process_integrations(analysis_result, secrets, user_mappings = {})
    results = {
      slack: nil,
      notion: nil
    }

    # Notion連携処理（ユーザーマッピング情報を活用）
    begin
      notion_api_key = secrets['NOTION_API_KEY']
      notion_database_id = secrets['NOTION_DATABASE_ID']
      notion_task_database_id = secrets['NOTION_TASK_DATABASE_ID']
      
      if notion_api_key && !notion_api_key.empty? && notion_database_id && !notion_database_id.empty?
        @logger.info("Creating meeting page in Notion with user mapping")
        notion_client = NotionClient.new(notion_api_key, notion_database_id, notion_task_database_id, @logger)
        
        # アクション項目の担当者が自動設定されている場合、Notionにも反映
        results[:notion] = notion_client.create_meeting_page(analysis_result)
      else
        @logger.warn("Notion API key or database ID is not configured")
      end
    rescue StandardError => e
      @logger.error("Notion integration failed: #{e.message}")
      results[:notion] = { success: false, error: e.message }
    end

    # Slack通知処理（メンション機能付き）
    begin
      # Bot TokenとChannel IDを使用
      slack_bot_token = secrets['SLACK_BOT_TOKEN']
      slack_channel_id = secrets['SLACK_CHANNEL_ID']
      
      if slack_bot_token && !slack_bot_token.empty? && slack_channel_id && !slack_channel_id.empty?
        @logger.info("Sending Slack notification via Web API with mentions")
        slack_client = SlackClient.new(slack_bot_token, slack_channel_id, @logger)
        
        # メンション情報を含むアクション項目を送信
        enhanced_result = analysis_result.dup
        if user_mappings[:user_mappings] && user_mappings[:user_mappings][:slack_mentions]
          enhanced_result['slack_mentions'] = user_mappings[:user_mappings][:slack_mentions]
        end
        
        results[:slack] = slack_client.send_notification(enhanced_result)
      else
        @logger.warn("Slack bot token or channel ID is not configured")
      end
    rescue StandardError => e
      @logger.error("Slack integration failed: #{e.message}")
      results[:slack] = { success: false, error: e.message }
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

  def success_response(analysis_result, slack_result = nil, notion_result = nil)
    response_body = {
      message: "Analysis complete.",
      analysis: analysis_result,
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
