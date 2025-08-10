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
  
  # 後方互換性のためのメソッド（削除予定）
  def build_blocks(analysis_result)
    blocks = []
    
    meeting_summary = analysis_result['meeting_summary'] || {}
    
    # Header
    blocks << {
      type: 'header',
      text: {
        type: 'plain_text',
        text: "📝 #{meeting_summary['title'] || 'Meeting'}",
        emoji: true
      }
    }
    
    # Summary
    fields = []
    fields << { type: 'mrkdwn', text: "*📅 日時:*\n#{meeting_summary['date'] || 'N/A'}" }
    fields << { type: 'mrkdwn', text: "*⏱ 所要時間:*\n#{meeting_summary['duration_minutes'] || 0}分" }
    
    if meeting_summary['participants'] && meeting_summary['participants'].any?
      participants_text = if meeting_summary['participants'].size > 3
        displayed = meeting_summary['participants'].first(3)
        "#{displayed.join(', ')} 他#{meeting_summary['participants'].size - 3}名"
      else
        meeting_summary['participants'].join(', ')
      end
      fields << { type: 'mrkdwn', text: "*👥 参加者:*\n#{participants_text}" }
    end
    
    blocks << { type: 'section', fields: fields }
    
    # Decisions
    decisions = analysis_result['decisions'] || []
    if decisions.any?
      text_lines = ["*🎯 決定事項 (#{decisions.size}件)*"]
      decisions.first(3).each_with_index do |decision, i|
        text_lines << "#{i + 1}. #{decision['content']}"
      end
      text_lines << "...他#{decisions.size - 3}件" if decisions.size > 3
      
      blocks << {
        type: 'section',
        text: { type: 'mrkdwn', text: text_lines.join("\n") }
      }
    end
    
    # Actions
    actions = analysis_result['actions'] || []
    if actions.any?
      sorted_actions = actions.sort_by do |a|
        priority_order = { 'high' => 0, 'medium' => 1, 'low' => 2 }
        [priority_order[a['priority']] || 3, a['deadline'] || 'zzzz']
      end
      
      text_lines = ["*📋 アクション一覧 (#{actions.size}件)*"]
      sorted_actions.first(3).each_with_index do |action, i|
        priority_emoji = { 'high' => '🔴', 'medium' => '🟡', 'low' => '⚪' }[action['priority']] || '⚪'
        assignee = action['slack_mention'] || action['assignee'] || '未定'
        deadline = action['deadline_formatted'] || '期日未定'
        text_lines << "#{i + 1}. #{priority_emoji} #{action['task']} - #{assignee}（#{deadline}）"
      end
      text_lines << "...他#{actions.size - 3}件" if actions.size > 3
      
      actions_without_deadline = actions.select { |a| a['deadline'].nil? }
      if actions_without_deadline.any?
        text_lines << ""
        text_lines << "⚠️ *#{actions_without_deadline.size}件のアクションに期日が設定されていません*"
      end
      
      blocks << {
        type: 'section',
        text: { type: 'mrkdwn', text: text_lines.join("\n") }
      }
    end
    
    blocks
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

  # 後方互換性のためのメソッド（削除予定）
  def send_thread_reply(analysis_result, thread_ts)
    if should_send_thread_reply?(analysis_result)
      thread_message = @message_builder.build_thread_message(analysis_result)
      @api_client.post_thread_reply(@channel_id, thread_ts, thread_message)
    end
  end
end