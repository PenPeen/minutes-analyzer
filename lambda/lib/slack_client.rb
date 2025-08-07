require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'date'

# Slack通知を送信するクライアントクラス
# Gemini APIから返された議事録分析結果をSlackのBlock Kit形式で整形して送信する
class SlackClient
  def initialize(webhook_url, logger)
    @webhook_url = webhook_url
    @logger = logger
  end

  # 議事録分析結果をSlackに送信する
  # @param analysis_result [Hash] Gemini APIから返された分析結果
  # @return [Hash] 送信結果（success, response_code, error）
  def send_notification(analysis_result)
    return { success: false, message: 'Webhook URL not configured' } unless @webhook_url && !@webhook_url.empty?

    begin
      uri = URI.parse(@webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30
      http.open_timeout = 30

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request.body = build_slack_message(analysis_result).to_json

      @logger.info("Sending notification to Slack")
      response = http.request(request)

      if response.code == '200'
        @logger.info("Successfully sent notification to Slack")
        { success: true, response_code: response.code }
      else
        @logger.error("Failed to send notification to Slack: #{response.code} - #{response.body}")
        { success: false, response_code: response.code, error: response.body }
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      @logger.error("Slack notification timeout: #{e.message}")
      { success: false, error: "Request timeout: #{e.message}" }
    rescue URI::InvalidURIError => e
      @logger.error("Invalid Slack webhook URL: #{e.message}")
      { success: false, error: "Invalid webhook URL format" }
    rescue JSON::GeneratorError => e
      @logger.error("Failed to generate JSON for Slack message: #{e.message}")
      { success: false, error: "Message formatting error" }
    rescue StandardError => e
      @logger.error("Unexpected error sending Slack notification: #{e.class.name} - #{e.message}")
      { success: false, error: e.message }
    end
  end

  private

  # Slack Block Kit形式のメッセージを構築する
  # @param analysis_result [Hash] 議事録分析結果
  # @return [Hash] Slack API用のメッセージ構造
  def build_slack_message(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    decisions = analysis_result['decisions'] || []
    actions = analysis_result['actions'] || []
    actions_summary = analysis_result['actions_summary'] || {}
    health_assessment = analysis_result['health_assessment'] || {}
    
    {
      blocks: build_message_blocks(meeting_summary, decisions, actions, actions_summary, health_assessment),
      text: build_fallback_text(meeting_summary)
    }
  end

  # メッセージのブロック要素を構築する
  # @return [Array<Hash>] Slack Block Kitのブロック配列
  def build_message_blocks(meeting_summary, decisions, actions, actions_summary, health_assessment)
    blocks = []

    blocks << build_header_block(meeting_summary)
    blocks << build_meeting_info_section(meeting_summary)
    blocks.concat(build_summary_section(decisions, actions))
    blocks << { type: "divider" }
    blocks.concat(build_decisions_section(decisions))
    blocks.concat(build_actions_section(actions, actions_summary))
    # 健全性スコアの表示を削除

    blocks.compact
  end

  # ヘッダーブロックを構築
  def build_header_block(meeting_summary)
    {
      type: "header",
      text: {
        type: "plain_text",
        text: "📝 #{meeting_summary['title'] || '議事録分析完了'}",
        emoji: true
      }
    }
  end

  # 会議情報セクションを構築
  def build_meeting_info_section(meeting_summary)
    {
      type: "section",
      fields: build_meeting_info_fields(meeting_summary)
    }
  end

  # サマリーカウントセクションを構築
  def build_summary_section(decisions, actions)
    return [] unless decisions.any? || actions.any?

    [{
      type: "section",
      fields: [
        {
          type: "mrkdwn",
          text: "*🎯 決定事項:* #{decisions.length}件"
        },
        {
          type: "mrkdwn",
          text: "*📋 アクション:* #{actions.length}件"
        }
      ]
    }]
  end

  # 決定事項セクションを構築
  def build_decisions_section(decisions)
    return [] unless decisions.any?

    [{
      type: "section",
      text: {
        type: "mrkdwn",
        text: "*🎯 主な決定事項*\n#{format_decisions(decisions)}"
      }
    }]
  end

  # アクションセクションを構築
  def build_actions_section(actions, actions_summary)
    return [] unless actions.any?

    sections = []
    
    sections << {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "*📋 アクション一覧*\n#{format_actions(actions)}"
      }
    }

    # 期日未設定の警告
    if actions_summary['without_deadline'] && actions_summary['without_deadline'] > 0
      sections << build_deadline_warning_block(actions_summary['without_deadline'])
    end

    sections
  end

  # 期日未設定の警告ブロックを構築
  def build_deadline_warning_block(count)
    {
      type: "context",
      elements: [
        {
          type: "mrkdwn",
          text: "⚠️ *#{count}件のアクションに期日が設定されていません*"
        }
      ]
    }
  end

  # 健全性スコアセクションを構築（削除済み - Slack通知には表示しない）
  # def build_health_score_section(health_assessment)
  #   # Slack通知には健全性スコアを表示しない仕様に変更
  # end

  def build_meeting_info_fields(meeting_summary)
    fields = []
    
    if meeting_summary['date']
      fields << {
        type: "mrkdwn",
        text: "*📅 日付:* #{meeting_summary['date']}"
      }
    end

    if meeting_summary['duration_minutes']
      fields << {
        type: "mrkdwn",
        text: "*⏱️ 所要時間:* #{meeting_summary['duration_minutes']}分"
      }
    end

    if meeting_summary['participants'] && meeting_summary['participants'].any?
      participants = meeting_summary['participants']
      if participants.length <= 3
        participants_text = participants.join(', ')
      else
        participants_text = participants.take(3).join(', ') + "…他#{participants.length - 3}名"
      end
      fields << {
        type: "mrkdwn",
        text: "*👥 参加者:* #{participants_text}"
      }
    end

    fields
  end

  def format_decisions(decisions)
    displayed_decisions = decisions.take(3).map.with_index do |decision, index|
      "#{index + 1}. #{decision['content']}"
    end.join("\n")
    
    if decisions.length > 3
      displayed_decisions + "\n…他#{decisions.length - 3}件"
    else
      displayed_decisions
    end
  end

  def format_actions(actions)
    # アクションを優先度（高→低）、期日（早い→遅い・期日なしは最後）でソート
    sorted_actions = sort_actions(actions)
    
    # 最大3件まで表示
    displayed_actions = sorted_actions.take(3).map.with_index do |action, index|
      deadline = action['deadline_formatted'] || '期日未定'
      priority_emoji = case action['priority']
                      when 'high' then '🔴'
                      when 'medium' then '🟡'
                      else '⚪'
                      end
      "#{index + 1}. #{priority_emoji} #{action['task']} - #{action['assignee']}（#{deadline}）"
    end.join("\n")
    
    if actions.length > 3
      displayed_actions + "\n…他#{actions.length - 3}件"
    else
      displayed_actions
    end
  end
  
  # アクションを優先度と期日でソート
  def sort_actions(actions)
    actions.sort do |a, b|
      # 優先度の比較（high: 3, medium: 2, low: 1）
      priority_weight = { 'high' => 3, 'medium' => 2, 'low' => 1 }
      priority_a = priority_weight[a['priority']] || 0
      priority_b = priority_weight[b['priority']] || 0
      
      if priority_a != priority_b
        priority_b <=> priority_a  # 優先度が高い方が先
      else
        # 同じ優先度の場合は期日で比較
        deadline_a = parse_deadline(a['deadline'])
        deadline_b = parse_deadline(b['deadline'])
        
        if deadline_a.nil? && deadline_b.nil?
          0  # 両方期日なしなら同じ
        elsif deadline_a.nil?
          1  # aが期日なしならbが先
        elsif deadline_b.nil?
          -1  # bが期日なしならaが先
        else
          deadline_a <=> deadline_b  # 期日が早い方が先
        end
      end
    end
  end
  
  # 期日文字列を比較可能な形式に変換
  def parse_deadline(deadline)
    return nil if deadline.nil? || deadline == '期日未定'
    
    # YYYY/MM/DD形式を想定
    if deadline =~ /(\d{4})\/(\d{2})\/(\d{2})/
      Date.new($1.to_i, $2.to_i, $3.to_i)
    else
      nil
    end
  rescue ArgumentError
    nil
  end

  def build_fallback_text(meeting_summary)
    "📝 #{meeting_summary['title'] || '議事録'}の分析が完了しました"
  end
end