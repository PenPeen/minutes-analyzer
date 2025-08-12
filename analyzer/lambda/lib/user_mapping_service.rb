require 'timeout'
require_relative 'meeting_transcript_processor'

class UserMappingService
  MAPPING_TIMEOUT = 60
  
  def initialize(logger, config)
    @logger = logger
    @config = config
    @processor = nil
  end
  
  def process_mapping(file_id, secrets)
    return {} unless @config.user_mapping_enabled?
    
    @logger.info("Starting user mapping for file_id: #{file_id}")
    
    begin
      processor = get_or_create_processor(secrets)
      result = execute_with_timeout(processor, file_id)
      log_mapping_result(result)
      result
    rescue Timeout::Error
      handle_timeout_error(file_id)
    rescue StandardError => e
      handle_general_error(file_id, e)
    end
  end
  
  def enrich_actions_with_assignees(analysis_result, user_mappings)
    return analysis_result unless valid_for_enrichment?(analysis_result, user_mappings)
    
    @logger.info("Enriching actions with user mapping data")
    
    analysis_result['actions'].each do |action|
      assignee = action['assignee']
      next if assignee.nil? || assignee.empty?
      
      assignee_email = find_email_for_assignee(action['assignee'], user_mappings[:participants])
      next unless assignee_email
      
      enrich_action_with_users(action, assignee_email, user_mappings)
    end
    
    analysis_result
  end
  
  private
  
  def get_or_create_processor(secrets)
    @processor ||= MeetingTranscriptProcessor.new(build_processor_config(secrets))
  end
  
  def build_processor_config(secrets)
    {
      google_calendar_enabled: @config.google_calendar_enabled,
      user_mapping_enabled: @config.user_mapping_enabled,
      google_service_account_json: secrets['GOOGLE_SERVICE_ACCOUNT_JSON'],
      slack_bot_token: secrets['SLACK_BOT_TOKEN'],
      notion_api_key: secrets['NOTION_API_KEY'],
      parallel_processing: true,
      max_threads: 10,
      api_timeout: 30
    }
  end
  
  def execute_with_timeout(processor, file_id)
    result = nil
    Timeout.timeout(MAPPING_TIMEOUT) do
      result = processor.process_transcript(file_id)
    end
    result
  end
  
  def log_mapping_result(result)
    case result[:status]
    when 'completed'
      log_successful_mapping(result)
    when 'partial'
      @logger.warn("User mapping partially completed: #{result[:warnings]&.join(', ')}")
    else
      @logger.warn("User mapping failed: #{result[:errors]&.join(', ')}")
    end
  end
  
  def log_successful_mapping(result)
    @logger.info("User mapping completed successfully")
    @logger.info("Found #{result[:participants]&.length || 0} participants")
    
    if result[:user_mappings]
      stats = @processor.get_statistics if @processor.respond_to?(:get_statistics)
      @logger.info("User mapping statistics: #{stats.to_json}") if stats
      
      successful_mappings = count_successful_mappings(result[:user_mappings])
      @logger.info("Successfully mapped #{successful_mappings[:slack]} Slack users and #{successful_mappings[:notion]} Notion users")
      
      log_unmapped_users(result)
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
    
    @logger.info("Unmapped users: #{unmapped.join('; ')}") if unmapped.any?
  end
  
  def handle_timeout_error(file_id)
    @logger.error("User mapping timeout after #{MAPPING_TIMEOUT} seconds")
    build_partial_result(file_id, 'Timeout during user mapping', 
                        ['Some user mappings may be incomplete due to timeout'])
  end
  
  def handle_general_error(file_id, error)
    @logger.error("Error in user mapping process: #{error.message}")
    @logger.error(error.backtrace.first(5).join("\n")) if error.backtrace
    
    build_partial_result(file_id, error.message, 
                        ['User mapping unavailable, continuing without it'])
  end
  
  def build_partial_result(file_id, error_message, warnings)
    {
      status: 'partial',
      error: error_message,
      file_id: file_id,
      warnings: warnings,
      user_mappings: { slack: {}, notion: {} }
    }
  end
  
  def valid_for_enrichment?(analysis_result, user_mappings)
    return false unless analysis_result.is_a?(Hash) && analysis_result['actions'].is_a?(Array)
    return false unless user_mappings[:status] == 'completed' && user_mappings[:user_mappings]
    true
  end
  
  def find_email_for_assignee(assignee_name, participants)
    return nil unless assignee_name && participants
    
    # 完全一致を試みる
    participant = participants.find { |p| p&.downcase == assignee_name.downcase }
    return participant if participant
    
    # 部分一致を試みる
    participants.find do |p|
      next unless p
      p.downcase.include?(assignee_name.downcase) || 
        assignee_name.downcase.include?(p.split('@').first.downcase)
    end
  end
  
  def enrich_action_with_users(action, email, user_mappings)
    enrich_action_with_notion_user(action, email, user_mappings)
    enrich_action_with_slack_user(action, email, user_mappings)
  end
  
  def enrich_action_with_notion_user(action, email, user_mappings)
    notion_users = user_mappings.dig(:user_mappings, :notion)
    return unless notion_users
    
    notion_user = notion_users[email]
    return unless notion_user && notion_user[:id]
    
    action['notion_user_id'] = notion_user[:id]
    action['assignee_email'] = email
    @logger.debug("Added Notion user ID for #{action['assignee']}: #{notion_user[:id]}")
  end
  
  def enrich_action_with_slack_user(action, email, user_mappings)
    slack_users = user_mappings.dig(:user_mappings, :slack)
    return unless slack_users
    
    slack_user = slack_users[email]
    return unless slack_user && slack_user[:id]
    
    action['slack_user_id'] = slack_user[:id]
    action['slack_mention'] = "<@#{slack_user[:id]}>"
    @logger.debug("Added Slack mention for #{action['assignee']}: <@#{slack_user[:id]}>")
  end
end