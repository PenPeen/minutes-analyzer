require_relative 'constants'

class SlackMessageBuilder
  include Constants::Display
  include Constants::Priority
  include Constants::Tone
  
  def initialize(logger)
    @logger = logger
  end
  
  def build_main_message(analysis_result)
    blocks = []
    
    blocks << build_header(analysis_result)
    blocks << build_summary_section(analysis_result)
    blocks << build_decisions_section(analysis_result)
    blocks << build_actions_section(analysis_result)
    
    {
      text: create_fallback_text(analysis_result),
      blocks: blocks.compact.flatten
    }
  end
  
  def build_thread_message(analysis_result)
    blocks = []
    
    blocks << build_atmosphere_section(analysis_result)
    blocks << build_suggestions_section(analysis_result)
    
    {
      text: "会議の詳細分析",
      blocks: blocks.compact.flatten
    }
  end
  
  private
  
  def create_fallback_text(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    title = meeting_summary['title'] || 'Meeting'
    "📝 #{title}の議事録レビューが完了しました！"
  end
  
  def build_header(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    title = meeting_summary['title'] || 'Meeting'
    
    {
      type: "header",
      text: {
        type: "plain_text",
        text: "📝 #{title}",
        emoji: true
      }
    }
  end
  
  def build_summary_section(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    
    fields = [
      {
        type: "mrkdwn",
        text: "*📅 日時:*\n#{meeting_summary['date'] || 'N/A'}"
      },
      {
        type: "mrkdwn",
        text: "*⏱ 所要時間:*\n#{meeting_summary['duration_minutes'] || 0}分"
      }
    ]
    
    # 参加者を制限して表示
    participants_text = build_participants_text(meeting_summary['participants'])
    if participants_text
      fields << {
        type: "mrkdwn",
        text: "*👥 参加者:*\n#{participants_text}"
      }
    end
    
    {
      type: "section",
      fields: fields
    }
  end
  
  def build_decisions_section(analysis_result)
    decisions = analysis_result['decisions'] || []
    return nil if decisions.empty?
    
    text_lines = ["*🎯 決定事項 (#{decisions.size}件)*"]
    
    decisions.first(MAX_DECISIONS).each_with_index do |decision, index|
      text_lines << "#{index + 1}. #{decision['content']}"
    end
    
    if decisions.size > MAX_DECISIONS
      text_lines << "...他#{decisions.size - MAX_DECISIONS}件"
    end
    
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: text_lines.join("\n")
      }
    }
  end
  
  def build_actions_section(analysis_result)
    actions = analysis_result['actions'] || []
    return nil if actions.empty?
    
    sorted_actions = sort_actions(actions)
    text_lines = ["*📋 アクション一覧 (#{actions.size}件)*"]
    
    sorted_actions.first(MAX_ACTIONS).each_with_index do |action, index|
      action_text = build_action_text(action)
      text_lines << "#{index + 1}. #{action_text}"
    end
    
    if actions.size > MAX_ACTIONS
      text_lines << "...他#{actions.size - MAX_ACTIONS}件"
    end
    
    # 期日なしアクションの警告
    actions_without_deadline = actions.select { |a| a['deadline'].nil? }
    if actions_without_deadline.any?
      text_lines << ""
      text_lines << "⚠️ *#{actions_without_deadline.size}件のアクションに期日が設定されていません*"
    end
    
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: text_lines.join("\n")
      }
    }
  end
  
  def build_atmosphere_section(analysis_result)
    atmosphere = analysis_result['atmosphere'] || {}
    return nil unless atmosphere['overall_tone']
    
    tone_emoji = EMOJIS[atmosphere['overall_tone']] || EMOJIS['neutral']
    
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "*🌡️ 会議の雰囲気*\n#{tone_emoji} #{atmosphere['overall_tone']}"
      }
    }
  end
  
  def build_suggestions_section(analysis_result)
    suggestions = analysis_result['improvement_suggestions'] || []
    return nil if suggestions.empty?
    
    text_lines = ["*💡 改善提案*"]
    
    suggestions.each_with_index do |suggestion, index|
      text_lines << "#{index + 1}. #{suggestion['suggestion']}"
      text_lines << "   → 期待効果: #{suggestion['expected_impact']}" if suggestion['expected_impact']
    end
    
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: text_lines.join("\n")
      }
    }
  end
  
  def build_participants_text(participants)
    return nil unless participants.is_a?(Array) && participants.any?
    
    if participants.size <= MAX_PARTICIPANTS
      participants.join(", ")
    else
      displayed = participants.first(MAX_PARTICIPANTS)
      others_count = participants.size - MAX_PARTICIPANTS
      "#{displayed.join(', ')} 他#{others_count}名"
    end
  end
  
  def sort_actions(actions)
    actions.sort_by do |action|
      [
        LEVELS[action['priority']] || 3,
        action['deadline'] || 'zzzz'
      ]
    end
  end
  
  def build_action_text(action)
    priority_emoji = Priority::EMOJIS[action['priority']] || Priority::EMOJIS['low']
    
    assignee = action['slack_mention'] || action['assignee'] || '未定'
    deadline = action['deadline_formatted'] || '期日未定'
    
    "#{priority_emoji} #{action['task']} - #{assignee}（#{deadline}）"
  end
end