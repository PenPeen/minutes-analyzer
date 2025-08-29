require_relative 'slack_notification_service'
require_relative 'notion_integration_service'

class IntegrationService
  def initialize(logger)
    @logger = logger
  end
  
  def process_integrations(analysis_result, secrets, user_mappings = {}, executor_info = nil)
    # 1. Notion連携を先に実行
    notion_result = process_notion_integration(analysis_result, secrets)
    
    # 2. NotionのURLを取得（成功時のみ）
    notion_url = if notion_result && (notion_result['success'] || notion_result[:success])
                   notion_result['url'] || notion_result[:url]
                 else
                   nil
                 end
    
    # 3. Slack連携（NotionURLを含む）
    slack_result = process_slack_integration(analysis_result, secrets, user_mappings, executor_info, notion_url)
    
    {
      notion: notion_result,
      slack: slack_result
    }
  end
  
  private
  
  def process_slack_integration(analysis_result, secrets, user_mappings, executor_info = nil, notion_url = nil)
    slack_bot_token = secrets['SLACK_BOT_TOKEN']
    slack_channel_id = secrets['SLACK_CHANNEL_ID']
    
    return nil unless slack_configured?(slack_bot_token, slack_channel_id)
    
    @logger.info("Sending Slack notification via Web API with mentions")
    slack_service = SlackNotificationService.new(slack_bot_token, slack_channel_id, @logger)
    
    result_with_mentions = enrich_with_slack_mentions(analysis_result, user_mappings)
    
    # 実行者情報を追加
    if executor_info
      result_with_mentions['executor_info'] = executor_info
    end
    
    slack_service.send_notification(result_with_mentions, notion_url)
  rescue StandardError => e
    handle_integration_error('Slack', e)
  end
  
  def process_notion_integration(analysis_result, secrets)
    notion_api_key = secrets['NOTION_API_KEY']
    notion_database_id = secrets['NOTION_DATABASE_ID']
    notion_task_database_id = secrets['NOTION_TASK_DATABASE_ID']
    
    return nil unless notion_configured?(notion_api_key, notion_database_id)
    
    @logger.info("Creating meeting page in Notion with user mapping")
    notion_service = NotionIntegrationService.new(notion_api_key, notion_database_id, notion_task_database_id, @logger)
    notion_service.create_meeting_page(analysis_result)
  rescue StandardError => e
    handle_integration_error('Notion', e)
  end
  
  def slack_configured?(token, channel_id)
    if token && !token.empty? && channel_id && !channel_id.empty?
      true
    else
      @logger.warn("Slack bot token or channel ID is not configured")
      false
    end
  end
  
  def notion_configured?(api_key, database_id)
    if api_key && !api_key.empty? && database_id && !database_id.empty?
      true
    else
      @logger.warn("Notion API key or database ID is not configured")
      false
    end
  end
  
  def enrich_with_slack_mentions(analysis_result, user_mappings)
    result_with_mentions = analysis_result.dup
    slack_mentions = user_mappings.dig(:user_mappings, :slack_mentions)
    result_with_mentions['slack_mentions'] = slack_mentions
    result_with_mentions
  end
  
  def handle_integration_error(service, error)
    @logger.error("#{service} integration failed: #{error.message}")
    { success: false, error: error.message }
  end
end