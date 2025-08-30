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

  def send_notification(analysis_result, notion_url = nil)
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
    main_message = @message_builder.build_main_message(analysis_result, notion_url)
    
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

  def send_error_notification(error_message, context = {})
    unless @bot_token && !@bot_token.empty? && @channel_id && !@channel_id.empty?
      @logger.warn("Slack configuration missing, skipping error notification")
      return { success: false, error: 'Slack configuration missing' }
    end

    begin
      error_text = "🚨 *エラーが発生しました*\n\n"
      error_text += "```#{error_message}```\n"
      error_text += "*発生時刻:* #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n"
      
      if context[:user_id]
        error_text += "*ユーザー:* <@#{context[:user_id]}>\n"
      end
      
      if context[:file_id]
        error_text += "*ファイルID:* #{context[:file_id]}\n"
      end

      error_blocks = [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: error_text.strip
          }
        }
      ]
      
      message_payload = {
        text: "エラーが発生しました",
        blocks: error_blocks
      }
      
      @api_client.post_message(@channel_id, message_payload)
    rescue => e
      @logger.error("Failed to send error notification: #{e.message}")
      { success: false, error: e.message }
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

end