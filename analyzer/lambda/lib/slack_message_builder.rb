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

    blocks << build_mention_message(analysis_result)
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

  def build_mention_message(analysis_result)
    executor_info = analysis_result['executor_info']
    return nil unless executor_info && executor_info[:user_id]

    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "<@#{executor_info[:user_id]}>\n\n議事録の分析と、Notionへのタスク連携が完了しました。\nタスク内容をご確認の上、期限設定や担当アサインを実施してください！"
      }
    }
  end

  def create_fallback_text(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    title = meeting_summary['title'] || 'Meeting'
    "📝 #{title}の議事録レビューが完了しました！"
  end

  def build_header(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    original_title = meeting_summary['title'] || 'Meeting'
    
    # タイトル整形処理を追加
    formatted_title = format_meeting_title(original_title, analysis_result)

    {
      type: "header",
      text: {
        type: "plain_text",
        text: ":memo: #{formatted_title}",
        emoji: true
      }
    }
  end

  def build_summary_section(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}

    fields = [
      {
        type: "mrkdwn",
        text: "*:calendar: 日時:*\n#{meeting_summary['date'] || 'N/A'}"
      }
    ]

    # 参加者を制限して表示
    participants_text = build_participants_text(meeting_summary['participants'])
    if participants_text
      fields << {
        type: "mrkdwn",
        text: "*:busts_in_silhouette: 参加者:*\n#{participants_text}"
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

    text_lines = ["*:dart: 決定事項 (#{decisions.size}件)*", ""]

    decisions.first(MAX_DECISIONS).each_with_index do |decision, index|
      text_lines << "• #{decision['content']}"
    end

    if decisions.size > MAX_DECISIONS
      text_lines << "• ...他#{decisions.size - MAX_DECISIONS}件"
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
    text_lines = ["*:clipboard: アクション一覧 (#{actions.size}件)*", ""]

    # 優先度別にグループ化して表示
    grouped_actions = group_actions_by_priority(sorted_actions.first(MAX_ACTIONS))
    
    grouped_actions.each do |priority, priority_actions|
      next if priority_actions.empty?
      
      priority_label = get_priority_label(priority)
      text_lines << "*#{priority_label}*" unless grouped_actions.size == 1
      
      priority_actions.each do |action|
        action_text = build_detailed_action_text(action)
        text_lines << "• #{action_text}"
      end
      
      text_lines << "" unless priority == grouped_actions.keys.last # 最後のグループ以外は空行追加
    end

    if actions.size > MAX_ACTIONS
      text_lines << "• ...他#{actions.size - MAX_ACTIONS}件"
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

    tone_emoji = Constants::Tone::EMOJIS[atmosphere['overall_tone']] || Constants::Tone::EMOJIS['neutral']
    tone_text = get_tone_japanese(atmosphere['overall_tone'])

    text_lines = ["*🌡️ 会議の雰囲気*", ""]
    text_lines << "#{tone_emoji} #{tone_text}"

    # 根拠を最大3件まで表示
    evidence = atmosphere['evidence'] || []
    unless evidence.empty?
      text_lines << ""
      text_lines << "*発言例:*"
      evidence.first(3).each do |item|
        cleaned_item = item.gsub(/\s*[\(（]\d{1,2}:\d{2}(?::\d{2})?[\)）]\s*/, '')
        text_lines << "• \"#{cleaned_item}\""
      end
    end

    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: text_lines.join("\n")
      }
    }
  end

  def build_suggestions_section(analysis_result)
    suggestions = analysis_result['improvement_suggestions'] || []
    return nil if suggestions.empty?

    text_lines = ["*💡 改善提案*", ""]

    suggestions.each_with_index do |suggestion, index|
      text_lines << "#{index + 1}. #{suggestion['suggestion']}"
      if suggestion['expected_impact']
        text_lines << "   💫 _期待効果: #{suggestion['expected_impact']}_"
      end
      text_lines << "" unless index == suggestions.size - 1  # 最後の項目以外は空行追加
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
        Constants::Priority::LEVELS[action['priority']] || 3,
        action['deadline'] || 'zzzz'
      ]
    end
  end

  def build_action_text(action)
    priority_emoji = Constants::Priority::EMOJIS[action['priority']] || Constants::Priority::EMOJIS['low']

    assignee = action['slack_mention'] || action['assignee'] || '未定'
    deadline = action['deadline_formatted'] || '期日未定'

    "#{priority_emoji} #{action['task']} - #{assignee}（#{deadline}）"
  end

  # 詳細なアクション表示（2行形式）
  def build_detailed_action_text(action)
    assignee = action['slack_mention'] || action['assignee'] || '未定'
    deadline = action['deadline_formatted'] || '期日未定'

    task_line = action['task']
    detail_line = "  👤 #{assignee}  📅 #{deadline}"
    
    "#{task_line}\n#{detail_line}"
  end

  # 優先度別グループ化
  def group_actions_by_priority(actions)
    grouped = actions.group_by { |action| action['priority'] }
    
    # 優先度順でソート
    ordered_groups = {}
    ['high', 'medium', 'low'].each do |priority|
      ordered_groups[priority] = grouped[priority] || []
    end
    
    # 空のグループを除去
    ordered_groups.reject { |_, actions| actions.empty? }
  end

  # 優先度ラベル取得
  def get_priority_label(priority)
    emoji = Constants::Priority::EMOJIS[priority] || Constants::Priority::EMOJIS['low']
    case priority
    when 'high'
      "#{emoji} 高優先度"
    when 'medium'
      "#{emoji} 中優先度"
    when 'low'
      "#{emoji} 低優先度"
    else
      "#{emoji} その他"
    end
  end

  # 雰囲気の日本語変換
  def get_tone_japanese(tone)
    case tone
    when 'positive'
      'ポジティブ'
    when 'negative'
      'ネガティブ'  
    when 'neutral'
      'ニュートラル'
    else
      tone
    end
  end

  # 議事録タイトルを整形するメソッド
  def format_meeting_title(original_title, analysis_result)
    # オリジナルファイル名が利用可能な場合はそれを使用
    if analysis_result['original_file_name']
      file_name = analysis_result['original_file_name']
      return looks_like_filename?(file_name) ? shorten_filename_title(file_name) : file_name
    end
    
    # フォールバック: Geminiが生成したタイトルを使用
    return original_title unless looks_like_filename?(original_title)
    
    # ファイル名っぽい場合は短縮処理を実行
    return shorten_filename_title(original_title)
  end

  private

  # ファイル名らしい文字列かどうか判定
  def looks_like_filename?(title)
    # 日付パターンや拡張子を含む場合はファイル名と判定
    title.match?(/\d{4}\/\d{1,2}\/\d{1,2}|\d{4}-\d{1,2}-\d{1,2}|\.(txt|docx?|pdf)$|Gemini によるメモ/)
  end

  # ファイル名を短縮してタイトル化
  def shorten_filename_title(filename)
    # "Webチームリファインメント - 2025/08/01 15:00 JST - Gemini によるメモ"
    # → "Webチームリファインメント - 2025/08/01"
    
    # 不要な部分を削除
    cleaned = filename
      .gsub(/ - Gemini によるメモ$/, '')  # " - Gemini によるメモ" を削除
      .gsub(/ \d{1,2}:\d{2}.*$/, '')      # 時刻以降を削除
      .gsub(/\.txt$|\.docx?$|\.pdf$/, '') # 拡張子を削除
      .strip
    
    # 短縮後も長い場合は、最初の50文字程度に制限
    cleaned.length > 50 ? "#{cleaned[0,47]}..." : cleaned
  end
end
