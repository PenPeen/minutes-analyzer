require_relative 'slack_api_client'
require_relative 'slack_message_builder'

class SlackNotificationService
  def initialize(bot_token, channel_id, logger)
    @bot_token = bot_token
    @channel_id = channel_id
    @logger = logger
    @api_client = SlackApiClient.new(bot_token, logger)
    @message_builder = SlackMessageBuilder.new(logger)
  end

  def send_notification(analysis_result)
    unless @bot_token && !@bot_token.empty?
      @logger.error("Slack bot token is not configured")
      return { success: false, error: 'Slack bot token is not configured' }
    end

    unless @channel_id && !@channel_id.empty?
      @logger.error("Slack channel ID is not configured")
      return { success: false, error: 'Slack channel ID is not configured' }
    end

    @logger.info("Sending Slack notification to channel: #{@channel_id}")

    # メッセージを構築
    main_message = @message_builder.build_main_message(analysis_result)
    
    # メインメッセージを送信
    result = @api_client.post_message(@channel_id, main_message)
    
    if result[:success]
      @logger.info("Successfully sent Slack notification")
      thread_ts = result[:data]['ts']
      
      # スレッド返信が必要な場合は送信
      if should_send_thread_reply?(analysis_result)
        thread_message = @message_builder.build_thread_message(analysis_result)
        @api_client.post_thread_reply(@channel_id, thread_ts, thread_message)
      end
      
      { success: true, timestamp: thread_ts }
    else
      @logger.error("Failed to send Slack notification: #{result[:error]}")
      result
    end
  end

  private

  def should_send_thread_reply?(analysis_result)
    atmosphere = analysis_result['atmosphere']
    suggestions = analysis_result['improvement_suggestions']
    (atmosphere && atmosphere['overall_tone']) || (suggestions && suggestions.any?)
  end
  

  def create_fallback_text(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    "📝 #{meeting_summary['title'] || 'Meeting'}の議事録レビューが完了しました！"
  end

  def should_send_thread_reply?(analysis_result)
    atmosphere = analysis_result['atmosphere']
    suggestions = analysis_result['improvement_suggestions']
    (atmosphere && atmosphere['overall_tone']) || (suggestions && suggestions.any?)
  end
end