# Legacy SlackClient implementation for backward compatibility with tests
# This file should be removed once tests are updated

require 'net/http'
require 'uri'
require 'json'

class SlackClientLegacy
  def initialize(bot_token, channel_id, logger)
    @bot_token = bot_token
    @channel_id = channel_id
    @logger = logger
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

    blocks = build_blocks(analysis_result)
    text = create_fallback_text(analysis_result)

    uri = URI('https://slack.com/api/chat.postMessage')

    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@bot_token}"
      request['Content-Type'] = 'application/json; charset=utf-8'
      
      payload = {
        channel: @channel_id,
        text: text,
        blocks: blocks
      }
      
      request.body = JSON.generate(payload)

      response = http.request(request)
      response_body = JSON.parse(response.body)

      if response.code == '200' && response_body['ok']
        @logger.info("Successfully sent Slack notification")
        
        # Send thread reply if needed
        if should_send_thread_reply?(analysis_result)
          thread_ts = response_body['ts']
          send_thread_reply(analysis_result, thread_ts)
        end
        
        { success: true, timestamp: response_body['ts'] }
      else
        error = response_body['error'] || 'Unknown error'
        @logger.error("Failed to send Slack notification: #{error}")
        { success: false, error: error }
      end
    rescue => e
      @logger.error("Error sending Slack notification: #{e.message}")
      { success: false, error: e.message }
    end
  end

  private

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

  def send_thread_reply(analysis_result, thread_ts)
    blocks = []
    
    atmosphere = analysis_result['atmosphere']
    if atmosphere && atmosphere['overall_tone']
      tone_emoji = { 'positive' => '😊', 'negative' => '😔' }[atmosphere['overall_tone']] || '😐'
      blocks << {
        type: 'section',
        text: { type: 'mrkdwn', text: "*🌡️ 会議の雰囲気*\n#{tone_emoji} #{atmosphere['overall_tone']}" }
      }
    end
    
    suggestions = analysis_result['improvement_suggestions']
    if suggestions && suggestions.any?
      text_lines = ["*💡 改善提案*"]
      suggestions.each_with_index do |s, i|
        text_lines << "#{i + 1}. #{s['suggestion']}"
        text_lines << "   → 期待効果: #{s['expected_impact']}" if s['expected_impact']
      end
      blocks << {
        type: 'section',
        text: { type: 'mrkdwn', text: text_lines.join("\n") }
      }
    end
    
    return if blocks.empty?
    
    uri = URI('https://slack.com/api/chat.postMessage')
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@bot_token}"
    request['Content-Type'] = 'application/json; charset=utf-8'
    
    payload = {
      channel: @channel_id,
      thread_ts: thread_ts,
      text: '会議の詳細分析',
      blocks: blocks
    }
    
    request.body = JSON.generate(payload)
    http.request(request)
  end
end