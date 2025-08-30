require_relative 'constants'

class SlackMessageBuilder
  include Constants::Display
  include Constants::Priority
  include Constants::Tone

  def initialize(logger)
    @logger = logger
  end

  def build_main_message(analysis_result, notion_url = nil)
    blocks = []

    blocks << build_mention_message(analysis_result)
    blocks << build_header(analysis_result)
    blocks << build_summary_section(analysis_result)
    blocks << build_decisions_section(analysis_result)
    blocks << build_actions_section(analysis_result)
    
    # NotionページURLがある場合はボタンを追加
    blocks << build_notion_button(notion_url) if notion_url

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
        text: "<@#{executor_info[:user_id]}>\n\n議事録分析完了！Notionにタスクを追加しました。\n期限や担当者の調整をお願いします📋"
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

    sorted_decisions = sort_decisions(decisions)
    text_lines = ["*:dart: 決定事項 (#{decisions.size}件)*"]

    sorted_decisions.first(MAX_DECISIONS).each_with_index do |decision, index|
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
    text_lines = ["*:clipboard: アクション一覧 (#{actions.size}件)*"]

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

    tone_japanese = get_tone_japanese(atmosphere['overall_tone'])

    text_lines = ["*🌡️ 会議の雰囲気*"]
    text_lines << tone_japanese

    # Geminiが生成したコメントを表示
    comment = atmosphere['comment']
    if comment && !comment.empty?
      text_lines << ""
      text_lines << comment
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

    text_lines = ["*💡 改善提案*"]

    suggestions.each_with_index do |suggestion, index|
      text_lines << "#{index + 1}. #{suggestion['suggestion']}"
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

  def sort_decisions(decisions)
    decisions.sort_by do |decision|
      Constants::Priority::LEVELS[decision['priority']] || 3
    end
  end

  def build_action_text(action)
    priority_emoji = Constants::Priority::EMOJIS[action['priority']] || Constants::Priority::EMOJIS['low']

    assignee = action['assignee'] || '未定'
    deadline = action['deadline_formatted'] || '期日未定'

    "#{priority_emoji} #{action['task']} - #{assignee}（#{deadline}）"
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

  # 雰囲気の英語表現を日本語に変換
  def get_tone_japanese(tone)
    case tone
    when 'positive'
      '会議全体が活気にあふれ、前向きな意見が多く出ていました🥳'
    when 'negative'
      '少し雰囲気が重めで、意見交換が進みにくい場面もあったようです🤔'
    when 'neutral'
      '落ち着いた雰囲気で、冷静に話が進んでいた印象です🙂'
    else
      '会議の雰囲気を読み取ることができませんでした😅'
    end
  end

  # NotionページへのボタンをSlackブロックとして構築
  def build_notion_button(notion_url)
    {
      type: "actions",
      elements: [
        {
          type: "button",
          text: {
            type: "plain_text",
            text: "📋 Notionで詳細を見る",
            emoji: true
          },
          url: notion_url,
          style: "primary"
        }
      ]
    }
  end
end