require 'time'

class NotionPageBuilder
  MAX_DECISION_DISPLAY = 5
  MAX_ACTION_DISPLAY = 5
  MAX_SUGGESTION_DISPLAY = 3
  
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
      '所要時間' => build_duration_property(meeting_summary['duration_minutes']),
      '参加者' => build_participants_property(meeting_summary['participants']),
      'スコア' => build_health_score_property(analysis_result)
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
    sections << build_health_assessment_section(analysis_result)
    sections << build_participation_section(analysis_result)
    sections << build_atmosphere_section(analysis_result)
    sections << build_improvements_section(analysis_result)
    sections << build_linked_database_section if has_task_database?
    
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
    priority_emoji = case action['priority']
                    when 'high' then '🔴'
                    when 'medium' then '🟡'
                    else '⚪'
                    end
    
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
  
  def build_linked_database_section
    return [] unless has_task_database?
    
    [
      {
        type: 'heading_2',
        heading_2: {
          rich_text: [
            {
              type: 'text',
              text: { content: '📝 関連タスク' }
            }
          ]
        }
      },
      {
        type: 'linked_database',
        linked_database: {
          database_id: @task_database_id
        }
      }
    ]
  end
  
  # 元のメソッドを削除
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
  
  def build_duration_property(duration)
    { 'number' => duration.to_i }
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
  
  def build_summary_section(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    
    [
      create_heading('📝 会議概要'),
      create_paragraph("日時: #{meeting_summary['date'] || 'N/A'}"),
      create_paragraph("所要時間: #{meeting_summary['duration_minutes'] || 0}分"),
      create_paragraph("参加者: #{format_participants(meeting_summary['participants'])}")
    ]
  end
  
  def build_decisions_section(analysis_result)
    decisions = analysis_result['decisions'] || []
    return [] if decisions.empty?
    
    blocks = [create_heading('📌 決定事項')]
    
    decisions.first(MAX_DECISION_DISPLAY).each do |decision|
      blocks << create_bulleted_item(decision['content'])
    end
    
    if decisions.size > MAX_DECISION_DISPLAY
      blocks << create_paragraph("...他#{decisions.size - MAX_DECISION_DISPLAY}件")
    end
    
    blocks
  end
  
  def build_actions_section(analysis_result)
    actions = analysis_result['actions'] || []
    return [] if actions.empty?
    
    blocks = [create_heading('✅ アクション項目')]
    
    sorted_actions = sort_actions(actions)
    sorted_actions.first(MAX_ACTION_DISPLAY).each do |action|
      blocks << create_action_item(action)
    end
    
    if actions.size > MAX_ACTION_DISPLAY
      blocks << create_paragraph("...他#{actions.size - MAX_ACTION_DISPLAY}件")
    end
    
    blocks
  end
  
  def build_health_assessment_section(analysis_result)
    health = analysis_result['health_assessment'] || {}
    return [] unless health['overall_score']
    
    blocks = [create_heading('📊 会議の健全性評価')]
    blocks << create_paragraph("健全性スコア: #{health['overall_score']}/100")
    
    if health['contradictions']&.any?
      blocks << create_paragraph('矛盾点:')
      health['contradictions'].each { |c| blocks << create_bulleted_item(c) }
    end
    
    if health['unresolved_issues']&.any?
      blocks << create_paragraph('未解決課題:')
      health['unresolved_issues'].each { |u| blocks << create_bulleted_item(u) }
    end
    
    blocks
  end
  
  def build_participation_section(analysis_result)
    participation = analysis_result['participation_analysis'] || {}
    return [] unless participation['speaker_stats']
    
    blocks = [create_heading('👥 参加度分析')]
    blocks << create_paragraph("バランススコア: #{participation['balance_score'] || 0}/100")
    blocks << create_paragraph('発言統計:')
    
    speaker_stats = participation['speaker_stats']
    if speaker_stats
      if speaker_stats.is_a?(Array)
        # 配列形式の場合
        speaker_stats.each do |speaker|
          next unless speaker.is_a?(Hash)
          name = speaker['name'] || 'Unknown'
          count = speaker['speaking_count'] || 0
          ratio = speaker['speaking_ratio'] || '0%'
          blocks << create_bulleted_item("#{name}: #{count}回 (#{ratio})")
        end
      elsif speaker_stats.is_a?(Hash)
        # ハッシュ形式の場合
        speaker_stats.each do |name, stats|
          if stats.is_a?(Hash)
            count = stats['speaking_count'] || 0
            ratio = stats['speaking_ratio'] || '0%'
            blocks << create_bulleted_item("#{name}: #{count}回 (#{ratio})")
          end
        end
      end
    end
    
    blocks
  end
  
  def build_atmosphere_section(analysis_result)
    atmosphere = analysis_result['atmosphere'] || {}
    return [] unless atmosphere['overall_tone']
    
    tone_emoji = case atmosphere['overall_tone']
                 when 'positive' then '😊'
                 when 'negative' then '😔'
                 else '😐'
                 end
    
    [
      create_heading('😊 会議の雰囲気'),
      create_paragraph("#{tone_emoji} #{atmosphere['overall_tone']}")
    ]
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
  
  def build_linked_database_section
    return [] unless has_task_database?
    
    [
      create_heading('🔗 関連タスク'),
      {
        'object' => 'block',
        'type' => 'child_database',
        'child_database' => { 'title' => 'タスク一覧' }
      }
    ]
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
  
  def create_action_item(action)
    priority_emoji = case action['priority']
                    when 'high' then '🔴'
                    when 'medium' then '🟡'
                    else '⚪'
                    end
    
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
end