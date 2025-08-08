require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'date'

class NotionClient
  NOTION_API_BASE_URL = 'https://api.notion.com/v1'
  NOTION_VERSION = ENV['NOTION_API_VERSION'] || '2022-06-28'

  def initialize(api_key, database_id, task_database_id, logger)
    @api_key = api_key
    @database_id = database_id
    @task_database_id = task_database_id
    @logger = logger
  end

  def create_meeting_page(analysis_result)
    @logger.info("Creating Notion page for meeting minutes")
    @logger.info("Analysis result class: #{analysis_result.class}")
    @logger.info("Analysis result keys: #{analysis_result.keys if analysis_result.respond_to?(:keys)}")
    
    uri = URI("#{NOTION_API_BASE_URL}/pages")
    
    # 議事録ページのプロパティを構築
    properties = build_meeting_properties(analysis_result)
    
    # ページコンテンツを構築
    children = build_page_content(analysis_result)
    
    request_body = {
      parent: { database_id: @database_id },
      properties: properties,
      children: children
    }
    
    response = make_notion_request(uri, request_body)
    
    if response[:success]
      page_id = response[:data]['id']
      @logger.info("Successfully created Notion page: #{page_id}")
      
      # アクション項目をタスクDBに連携
      task_results = nil
      actions = analysis_result['actions'] || []
      if actions.any? && @task_database_id && !@task_database_id.empty?
        task_results = create_tasks_from_actions(actions, page_id)
      end
      
      result = { success: true, page_id: page_id, url: response[:data]['url'] }
      
      # タスク作成結果を含める
      if task_results
        failed_tasks = task_results.select { |t| !t[:success] }
        if !failed_tasks.empty?
          result[:task_creation_failures] = failed_tasks
        end
      end
      
      result
    else
      @logger.error("Failed to create Notion page: #{response[:error]}")
      { success: false, error: response[:error] }
    end
  end

  private

  def build_meeting_properties(analysis_result)
    meeting_summary = analysis_result['meeting_summary'] || {}
    decisions = analysis_result['decisions'] || []
    actions = analysis_result['actions'] || []
    health_assessment = analysis_result['health_assessment'] || {}
    
    properties = {
      "タイトル" => {
        title: [
          {
            text: {
              content: meeting_summary['title'] || "議事録 #{Time.now.strftime('%Y-%m-%d %H:%M')}"
            }
          }
        ]
      },
      "日付" => {
        date: {
          start: meeting_summary['date'] || Time.now.strftime('%Y-%m-%d')
        }
      }
    }
    
    # 参加者の設定
    if meeting_summary['participants'] && meeting_summary['participants'].any?
      properties["参加者"] = {
        multi_select: meeting_summary['participants'].map { |p| { name: p } }
      }
    end
    
    # 決定事項の設定
    if decisions.any?
      properties["決定事項"] = {
        rich_text: [
          {
            text: {
              content: decisions.map { |d| "• #{d['content']}" }.join("\n")
            }
          }
        ]
      }
    end
    
    # アクション項目の設定
    if actions.any?
      properties["TODO"] = {
        rich_text: [
          {
            text: {
              content: actions.map { |a| "• #{a['task']} (#{a['assignee']})" }.join("\n")
            }
          }
        ]
      }
    end
    
    # 健全性スコアの設定
    if health_assessment['overall_score']
      properties["スコア"] = {
        number: health_assessment['overall_score']
      }
    end
    
    properties
  end

  def build_page_content(analysis_result)
    content = []
    
    # ヘッダー
    content << build_header
    
    # 各セクションを追加
    decisions = analysis_result['decisions'] || []
    actions = analysis_result['actions'] || []
    health_assessment = analysis_result['health_assessment'] || {}
    participation_analysis = analysis_result['participation_analysis'] || {}
    atmosphere = analysis_result['atmosphere'] || {}
    improvement_suggestions = analysis_result['improvement_suggestions'] || []
    
    content.concat(build_decisions_section(decisions)) if decisions.any?
    content.concat(build_actions_section(actions)) if actions.any?
    content.concat(build_health_section(health_assessment)) if health_assessment['overall_score']
    content.concat(build_participation_section(participation_analysis)) if participation_analysis['balance_score']
    content.concat(build_atmosphere_section(atmosphere)) if atmosphere['overall_tone']
    content.concat(build_improvements_section(improvement_suggestions)) if improvement_suggestions.any?
    
    content
  end

  def build_header
    {
      type: "heading_1",
      heading_1: {
        rich_text: [
          {
            type: "text",
            text: { content: "議事録サマリー" }
          }
        ]
      }
    }
  end

  def build_decisions_section(decisions)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "📌 決定事項" }
          }
        ]
      }
    }
    
    decisions.each do |decision|
      text = "#{decision['content']}"
      text += " (#{decision['decided_by']}により決定)" if decision['decided_by']
      text += " [#{decision['timestamp']}]" if decision['timestamp']
      
      section << {
        type: "bulleted_list_item",
        bulleted_list_item: {
          rich_text: [
            {
              type: "text",
              text: { content: text }
            }
          ]
        }
      }
    end
    
    section
  end

  def build_actions_section(actions)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "✅ アクション項目" }
          }
        ]
      }
    }
    
    actions.each do |action|
      priority_emoji = case action['priority']
                      when 'high' then '🔴'
                      when 'medium' then '🟡'
                      else '⚪'
                      end
      
      action_text = "#{priority_emoji} #{action['task']}"
      action_text += " (担当: #{action['assignee']})"
      action_text += " (期限: #{action['deadline_formatted']})"
      
      section << {
        type: "to_do",
        to_do: {
          rich_text: [
            {
              type: "text",
              text: { content: action_text }
            }
          ],
          checked: false
        }
      }
    end
    
    section
  end

  def build_health_section(health_assessment)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "📊 会議の健全性評価" }
          }
        ]
      }
    }
    
    content = "総合スコア: #{health_assessment['overall_score']}/100\n"
    
    if health_assessment['contradictions'] && health_assessment['contradictions'].any?
      content += "\n矛盾点:\n"
      health_assessment['contradictions'].each { |c| content += "• #{c}\n" }
    end
    
    if health_assessment['unresolved_issues'] && health_assessment['unresolved_issues'].any?
      content += "\n未解決課題:\n"
      health_assessment['unresolved_issues'].each { |u| content += "• #{u}\n" }
    end
    
    section << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: content }
          }
        ]
      }
    }
    
    section
  end

  def build_participation_section(participation_analysis)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "👥 参加度分析" }
          }
        ]
      }
    }
    
    content = "バランススコア: #{participation_analysis['balance_score']}/100\n\n"
    
    if participation_analysis['speaker_stats']
      content += "発言統計:\n"
      participation_analysis['speaker_stats'].each do |speaker|
        content += "• #{speaker['name']}: #{speaker['speaking_count']}回 (#{speaker['speaking_ratio']})\n"
      end
    end
    
    section << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: content }
          }
        ]
      }
    }
    
    section
  end

  def build_atmosphere_section(atmosphere)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "😊 会議の雰囲気" }
          }
        ]
      }
    }
    
    tone_emoji = case atmosphere['overall_tone']
                 when 'positive' then '😊'
                 when 'negative' then '😟'
                 else '😐'
                 end
    
    content = "全体的な雰囲気: #{tone_emoji} #{atmosphere['overall_tone']}\n\n"
    
    if atmosphere['evidence'] && atmosphere['evidence'].any?
      content += "根拠:\n"
      atmosphere['evidence'].each { |e| content += "• #{e}\n" }
    end
    
    section << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: content }
          }
        ]
      }
    }
    
    section
  end

  def build_improvements_section(improvement_suggestions)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "💡 改善提案" }
          }
        ]
      }
    }
    
    improvement_suggestions.each do |suggestion|
      category_emoji = case suggestion['category']
                      when 'participation' then '👥'
                      when 'time_management' then '⏱️'
                      when 'decision_making' then '🎯'
                      when 'facilitation' then '🎤'
                      else '💡'
                      end
      
      section << {
        type: "bulleted_list_item",
        bulleted_list_item: {
          rich_text: [
            {
              type: "text",
              text: { content: "#{category_emoji} #{suggestion['suggestion']} (期待効果: #{suggestion['expected_impact']})" }
            }
          ]
        }
      }
    end
    
    section
  end

  def create_tasks_from_actions(actions, meeting_page_id)
    @logger.info("Creating tasks in task database")
    
    task_results = []
    actions.each do |action|
      result = create_task(action, meeting_page_id)
      task_results << { task: action['task'], success: result[:success], error: result[:error] }
    end
    
    task_results
  end

  def create_task(action, meeting_page_id)
    uri = URI("#{NOTION_API_BASE_URL}/pages")
    
    properties = {
      "タスク名" => {
        title: [
          {
            text: {
              content: action['task']
            }
          }
        ]
      },
      "ステータス" => {
        select: {
          name: "未着手"
        }
      },
      "関連議事録" => {
        relation: [
          {
            id: meeting_page_id
          }
        ]
      }
    }
    
    # 優先度の設定
    if action['priority']
      priority_map = {
        'high' => '高',
        'medium' => '中',
        'low' => '低'
      }
      properties["優先度"] = {
        select: {
          name: priority_map[action['priority']] || '中'
        }
      }
    end
    
    # 担当者の設定（テキストフィールドとして設定）
    if action['assignee']
      properties["担当者"] = {
        rich_text: [
          {
            text: {
              content: action['assignee']
            }
          }
        ]
      }
    end
    
    # 期限の設定（deadlineをパースして日付形式に変換）
    if action['deadline']
      begin
        # 期限が文字列の場合、日付として解析を試みる
        deadline_date = Date.parse(action['deadline'].to_s)
        properties["期限"] = {
          date: {
            start: deadline_date.to_s
          }
        }
      rescue
        @logger.warn("Could not parse deadline: #{action['deadline']}")
      end
    end
    
    request_body = {
      parent: { database_id: @task_database_id },
      properties: properties
    }
    
    response = make_notion_request(uri, request_body)
    
    if response[:success]
      @logger.info("Successfully created task: #{action['task']}")
    else
      @logger.error("Failed to create task: #{response[:error]}")
    end
    
    response
  end

  def make_notion_request(uri, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Notion-Version'] = NOTION_VERSION
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body)
    
    # Security: Never log the request headers to prevent API key exposure
    @logger.debug("Making Notion API request to: #{uri}")
    
    begin
      response = http.request(request)
      
      if response.code.to_i >= 200 && response.code.to_i < 300
        { success: true, data: JSON.parse(response.body) }
      else
        error_details = JSON.parse(response.body) rescue response.body
        { success: false, error: "HTTP #{response.code}: #{error_details}" }
      end
    rescue StandardError => e
      @logger.error("Notion API request failed: #{e.message}")
      { success: false, error: e.message }
    end
  end
end