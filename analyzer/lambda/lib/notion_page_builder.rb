require 'time'

class NotionPageBuilder
  MAX_ACTION_DISPLAY = 5
  MAX_SUGGESTION_DISPLAY = 3
  
  # 雰囲気タイプの日本語マッピング
  ATMOSPHERE_TYPE_MAPPING = {
    'positive' => 'ポジティブ',
    'negative' => 'ネガティブ',
    'neutral' => 'ニュートラル'
  }.freeze
  
  def initialize(task_database_id, logger)
    @task_database_id = task_database_id
    @logger = logger
  end
  
  def build_meeting_page(analysis_result, database_id)
    {
      parent: { database_id: database_id },
      properties: build_properties(analysis_result),
      children: build_content(analysis_result)
    }
  end
  
  def build_properties(analysis_result)
    analysis_result ||= {}
    meeting_summary = analysis_result['meeting_summary'] || {}
    
    # 日付を取得（なければ現在日付を使用）
    date_str = meeting_summary['date'] || Time.now.strftime('%Y-%m-%d')
    # タイトルを取得
    title = meeting_summary['title'] || 'Untitled Meeting'
    # 日付付きタイトルを生成
    title_with_date = "#{date_str} #{title}"
    
    {
      'タイトル' => {
        'title' => [
          {
            'text' => {
              'content' => title_with_date
            }
          }
        ]
      },
      '日付' => build_date_property(meeting_summary['date']),
      '参加者' => build_participants_property(meeting_summary['participants']),
      'スコア' => build_health_score_property(analysis_result),
      '会議雰囲気' => build_atmosphere_property(analysis_result),
      '雰囲気詳細' => build_atmosphere_comment_property(analysis_result)
    }
  end
  
  def build_content(analysis_result)
    sections = []
    
    # 最初にheading_1を追加
    sections << {
      'object' => 'block',
      'type' => 'heading_1',
      'heading_1' => {
        'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => '議事録サマリー' } }]
      }
    }
    
    sections << build_summary_section(analysis_result)
    sections << build_decisions_section(analysis_result)
    sections << build_actions_section(analysis_result)
    sections << build_atmosphere_section(analysis_result)
    sections << build_improvements_section(analysis_result)
    
    sections.flatten.compact
  end
  
  def build_task_content(action)
    blocks = []
    
    # タスクの背景・文脈情報セクション
    if action['task_context'] && !action['task_context'].empty?
      blocks << {
        'object' => 'block',
        'type' => 'heading_3',
        'heading_3' => {
          'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => '📌 背景・文脈' } }]
        }
      }
      blocks << {
        'object' => 'block',
        'type' => 'paragraph',
        'paragraph' => {
          'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => action['task_context'] } }]
        }
      }
    end
    
    # 実行手順セクション
    if action['suggested_steps'] && action['suggested_steps'].is_a?(Array) && !action['suggested_steps'].empty?
      blocks << {
        'object' => 'block',
        'type' => 'heading_3',
        'heading_3' => {
          'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => '📝 実行手順' } }]
        }
      }
      
      action['suggested_steps'].each_with_index do |step, index|
        blocks << {
          'object' => 'block',
          'type' => 'numbered_list_item',
          'numbered_list_item' => {
            'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => step } }]
          }
        }
      end
    end
    
    # タスク詳細セクション（常に表示）
    blocks << {
      'object' => 'block',
      'type' => 'heading_3',
      'heading_3' => {
        'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => '📋 タスク詳細' } }]
      }
    }
    
    # 優先度
    priority_emoji = get_priority_emoji(action['priority'])
    blocks << {
      'object' => 'block',
      'type' => 'paragraph',
      'paragraph' => {
        'rich_text' => [
          { 'type' => 'text', 'text' => { 'content' => "優先度: #{priority_emoji} #{action['priority'] || 'low'}" } }
        ]
      }
    }
    
    # 期限
    if action['deadline_formatted']
      blocks << {
        'object' => 'block',
        'type' => 'paragraph',
        'paragraph' => {
          'rich_text' => [
            { 'type' => 'text', 'text' => { 'content' => "期限: #{action['deadline_formatted']}" } }
          ]
        }
      }
    end
    
    blocks
  end
  
  def set_task_database_id(task_database_id)
    @task_database_id = task_database_id
  end
  
  private
  
  def has_task_database?
    @task_database_id && !@task_database_id.to_s.empty?
  end
  
  def _old_has_task_database?
    @task_database_id && !@task_database_id.empty?
  end
  
  def build_date_property(date)
    return { 'date' => nil } unless date
    
    begin
      parsed_date = Date.parse(date.to_s)
      { 'date' => { 'start' => parsed_date.to_s } }
    rescue
      { 'date' => nil }
    end
  end
  
  
  def build_participants_property(participants)
    return { 'multi_select' => [] } unless participants.is_a?(Array)
    
    {
      'multi_select' => participants.first(10).map { |p| { 'name' => p } }
    }
  end
  
  def build_health_score_property(analysis_result)
    health_assessment = analysis_result['health_assessment'] || {}
    score = health_assessment['overall_score'] || 0
    { 'number' => score }
  end

  def build_atmosphere_property(analysis_result)
    atmosphere = analysis_result['atmosphere'] || {}
    overall_tone = atmosphere['overall_tone']
    
    return { 'select' => nil } unless overall_tone
    
    # 日本語の選択肢名に変換
    tone_name = ATMOSPHERE_TYPE_MAPPING[overall_tone] || 'その他'
    
    { 'select' => { 'name' => tone_name } }
  end

  def build_atmosphere_comment_property(analysis_result)
    atmosphere = analysis_result['atmosphere'] || {}
    comment = atmosphere['comment']
    
    return { 'rich_text' => [] } unless comment && !comment.empty?
    
    {
      'rich_text' => [
        {
          'text' => {
            'content' => comment
          }
        }
      ]
    }
  end
  
  def build_summary_section(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    
    [
      create_heading('📝 会議概要'),
      create_paragraph("日時: #{meeting_summary['date'] || 'N/A'}"),
      create_paragraph("参加者: #{format_participants(meeting_summary['participants'])}")
    ]
  end
  
  def build_decisions_section(analysis_result)
    decisions = analysis_result['decisions'] || []
    return [] if decisions.empty?
    
    blocks = [create_heading('📌 決定事項')]
    
    # 優先度順にソート
    sorted_decisions = sort_decisions(decisions)
    sorted_decisions.each do |decision|
      blocks << create_bulleted_item(decision['content'])
    end
    
    blocks
  end
  
  def build_actions_section(analysis_result)
    actions = analysis_result['actions'] || []
    return [] if actions.empty?
    
    blocks = [create_heading('✅ アクション項目')]
    
    # タスクデータベースが設定されている場合はリンクを表示
    if has_task_database?
      total = actions.size
      high = actions.count { |a| a['priority'].to_s.downcase == 'high' }
      
      # タスクデータベースへのリンクを生成
      compact_task_db_id = @task_database_id.to_s.gsub('-', '')
      tasks_url = ENV['NOTION_TASKS_VIEW_URL'] || "https://www.notion.so/#{compact_task_db_id}"
      
      blocks << {
        'object' => 'block',
        'type' => 'callout',
        'callout' => {
          'rich_text' => [
            { 'type' => 'text', 'text' => { 'content' => "📊 タスク: #{total}件（高優先度: #{high}件）\n" } },
            { 'type' => 'text', 'text' => { 'content' => '→ タスク管理データベースで詳細確認', 'link' => { 'url' => tasks_url } } }
          ],
          'icon' => { 'emoji' => '📋' },
          'color' => 'blue_background'
        }
      }
    else
      # タスクデータベースが設定されていない場合は直接表示
      sorted_actions = sort_actions(actions)
      sorted_actions.first(MAX_ACTION_DISPLAY).each do |action|
        blocks << create_action_item(action)
      end
      
      if actions.size > MAX_ACTION_DISPLAY
        blocks << create_paragraph("...他#{actions.size - MAX_ACTION_DISPLAY}件")
      end
    end
    
    blocks
  end
  
  
  def build_atmosphere_section(analysis_result)
    atmosphere = analysis_result['atmosphere'] || {}
    return [] unless atmosphere['overall_tone']
    
    tone_japanese = get_tone_japanese(atmosphere['overall_tone'])
    
    blocks = [create_heading('🌡️ 会議の雰囲気')]
    blocks << create_paragraph(tone_japanese)
    
    # Geminiが生成したコメントを表示
    comment = atmosphere['comment']
    if comment && !comment.empty?
      blocks << create_paragraph(comment)
    end
    
    blocks
  end
  
  def build_improvements_section(analysis_result)
    suggestions = analysis_result['improvement_suggestions'] || []
    return [] if suggestions.empty?
    
    blocks = [create_heading('💡 改善提案')]
    
    suggestions.first(MAX_SUGGESTION_DISPLAY).each do |suggestion|
      blocks << create_bulleted_item("#{suggestion['suggestion']} (#{suggestion['category']})")
    end
    
    blocks
  end
  
  def format_participants(participants)
    return 'N/A' unless participants.is_a?(Array) && participants.any?
    participants.join(', ')
  end
  
  def sort_actions(actions)
    actions.sort_by do |action|
      priority_order = { 'high' => 0, 'medium' => 1, 'low' => 2 }
      [
        priority_order[action['priority']] || 3,
        action['deadline'] || 'zzzz'
      ]
    end
  end

  def sort_decisions(decisions)
    priority_order = { 'high' => 0, 'medium' => 1, 'low' => 2 }
    decisions.sort_by do |decision|
      priority_order[decision['priority']] || 3
    end
  end

  def get_priority_emoji(priority)
    case priority&.downcase
    when 'high' then '🔴'
    when 'medium' then '🟡'
    else '⚪'
    end
  end
  
  def create_action_item(action)
    priority_emoji = get_priority_emoji(action['priority'])
    assignee = if action['assignee_email']
                "#{action['assignee']} (#{action['assignee_email']})"
              else
                action['assignee'] || '未定'
              end
    
    content = "#{priority_emoji} #{action['task']} - #{assignee}"
    content += " (#{action['deadline_formatted']})" if action['deadline_formatted']
    
    create_bulleted_item(content)
  end
  
  def create_heading(text)
    {
      'object' => 'block',
      'type' => 'heading_2',
      'heading_2' => {
        'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => text } }]
      }
    }
  end
  
  def create_paragraph(text)
    {
      'object' => 'block',
      'type' => 'paragraph',
      'paragraph' => {
        'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => text } }]
      }
    }
  end
  
  def create_bulleted_item(text)
    {
      'object' => 'block',
      'type' => 'bulleted_list_item',
      'bulleted_list_item' => {
        'rich_text' => [{ 'type' => 'text', 'text' => { 'content' => text } }]
      }
    }
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
end