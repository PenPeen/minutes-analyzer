require_relative 'slack_client'
require_relative 'notion_client'

class IntegrationService
  def initialize(logger)
    @logger = logger
  end
  
  def process_integrations(analysis_result, secrets, user_mappings = {})
    {
      slack: process_slack_integration(analysis_result, secrets, user_mappings),
      notion: process_notion_integration(analysis_result, secrets)
    }
  end
  
  private
  
  def process_slack_integration(analysis_result, secrets, user_mappings)
    slack_bot_token = secrets['SLACK_BOT_TOKEN']
    slack_channel_id = secrets['SLACK_CHANNEL_ID']
    
    return nil unless slack_configured?(slack_bot_token, slack_channel_id)
    
    @logger.info("Sending Slack notification via Web API with mentions")
    slack_client = SlackClient.new(slack_bot_token, slack_channel_id, @logger)
    
    result_with_mentions = enrich_with_slack_mentions(analysis_result, user_mappings)
    slack_client.send_notification(result_with_mentions)
  rescue StandardError => e
    handle_integration_error('Slack', e)
  end
  
  def process_notion_integration(analysis_result, secrets)
    notion_api_key = secrets['NOTION_API_KEY']
    notion_database_id = secrets['NOTION_DATABASE_ID']
    notion_task_database_id = secrets['NOTION_TASK_DATABASE_ID']
    
    return nil unless notion_configured?(notion_api_key, notion_database_id)
    
    @logger.info("Creating meeting page in Notion with user mapping")
    notion_client = NotionClient.new(notion_api_key, notion_database_id, notion_task_database_id, @logger)
    notion_client.create_meeting_page(analysis_result)
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
    result_with_mentions['slack_mentions'] = slack_mentions if slack_mentions
    result_with_mentions
  end
  
  def handle_integration_error(service, error)
    @logger.error("#{service} integration failed: #{error.message}")
    { success: false, error: error.message }
  end
end