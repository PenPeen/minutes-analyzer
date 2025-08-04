require 'net/http'
require 'uri'
require 'json'
require 'time'

class NotionClient
  NOTION_API_BASE_URL = 'https://api.notion.com/v1'
  NOTION_VERSION = ENV['NOTION_API_VERSION'] || '2022-06-28'

  def initialize(api_key, database_id, task_database_id, logger)
    @api_key = api_key
    @database_id = database_id
    @task_database_id = task_database_id
    @logger = logger
  end

  def create_meeting_page(summary)
    @logger.info("Creating Notion page for meeting minutes")
    
    uri = URI("#{NOTION_API_BASE_URL}/pages")
    
    # 議事録ページのプロパティを構築
    properties = build_meeting_properties(summary)
    
    # ページコンテンツを構築
    children = build_page_content(summary)
    
    request_body = {
      parent: { database_id: @database_id },
      properties: properties,
      children: children
    }
    
    response = make_notion_request(uri, request_body)
    
    if response[:success]
      page_id = response[:data]['id']
      @logger.info("Successfully created Notion page: #{page_id}")
      
      # TODO項目をタスクDBに連携
      task_results = nil
      if summary[:todos] && !summary[:todos].empty? && @task_database_id && !@task_database_id.empty?
        task_results = create_tasks_from_todos(summary[:todos], page_id)
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

  def build_meeting_properties(summary)
    properties = {
      "タイトル" => {
        title: [
          {
            text: {
              content: summary[:title] || "議事録 #{Time.now.strftime('%Y-%m-%d %H:%M')}"
            }
          }
        ]
      },
      "日付" => {
        date: {
          start: Time.now.iso8601
        }
      }
    }
    
    # 参加者の設定
    if summary[:participants] && !summary[:participants].empty?
      properties["参加者"] = {
        multi_select: summary[:participants].map { |p| { name: p } }
      }
    end
    
    # 決定事項の設定
    if summary[:decisions] && !summary[:decisions].empty?
      properties["決定事項"] = {
        rich_text: [
          {
            text: {
              content: summary[:decisions].join("\n")
            }
          }
        ]
      }
    end
    
    # TODOの設定
    if summary[:todos] && !summary[:todos].empty?
      properties["TODO"] = {
        rich_text: [
          {
            text: {
              content: summary[:todos].map { |todo| "• #{todo[:task]}" }.join("\n")
            }
          }
        ]
      }
    end
    
    # スコアの設定
    if summary[:score]
      properties["スコア"] = {
        number: summary[:score]
      }
    end
    
    properties
  end

  def build_page_content(summary)
    content = []
    
    # ヘッダー
    content << build_header
    
    # 各セクションを追加
    content.concat(build_decisions_section(summary[:decisions])) if summary[:decisions] && !summary[:decisions].empty?
    content.concat(build_todos_section(summary[:todos])) if summary[:todos] && !summary[:todos].empty?
    content.concat(build_warnings_section(summary[:warnings])) if summary[:warnings] && !summary[:warnings].empty?
    content.concat(build_emotion_section(summary[:emotion_analysis])) if summary[:emotion_analysis]
    content.concat(build_efficiency_section(summary[:efficiency_advice])) if summary[:efficiency_advice]
    
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
      section << {
        type: "bulleted_list_item",
        bulleted_list_item: {
          rich_text: [
            {
              type: "text",
              text: { content: decision }
            }
          ]
        }
      }
    end
    
    section
  end

  def build_todos_section(todos)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "✅ TODO項目" }
          }
        ]
      }
    }
    
    todos.each do |todo|
      todo_text = todo[:task]
      todo_text += " (担当: #{todo[:assignee]})" if todo[:assignee]
      todo_text += " (期限: #{todo[:due_date]})" if todo[:due_date]
      
      section << {
        type: "to_do",
        to_do: {
          rich_text: [
            {
              type: "text",
              text: { content: todo_text }
            }
          ],
          checked: false
        }
      }
    end
    
    section
  end

  def build_warnings_section(warnings)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "⚠️ 注意点" }
          }
        ]
      }
    }
    
    warnings.each do |warning|
      section << {
        type: "bulleted_list_item",
        bulleted_list_item: {
          rich_text: [
            {
              type: "text",
              text: { content: warning }
            }
          ]
        }
      }
    end
    
    section
  end

  def build_emotion_section(emotion_analysis)
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
    
    section << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: emotion_analysis }
          }
        ]
      }
    }
    
    section
  end

  def build_efficiency_section(efficiency_advice)
    section = []
    section << {
      type: "heading_2",
      heading_2: {
        rich_text: [
          {
            type: "text",
            text: { content: "💡 効率改善アドバイス" }
          }
        ]
      }
    }
    
    section << {
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: efficiency_advice }
          }
        ]
      }
    }
    
    section
  end

  def create_tasks_from_todos(todos, meeting_page_id)
    @logger.info("Creating tasks in task database")
    
    task_results = []
    todos.each do |todo|
      result = create_task(todo, meeting_page_id)
      task_results << { task: todo[:task], success: result[:success], error: result[:error] }
    end
    
    task_results
  end

  def create_task(todo, meeting_page_id)
    uri = URI("#{NOTION_API_BASE_URL}/pages")
    
    properties = {
      "タスク名" => {
        title: [
          {
            text: {
              content: todo[:task]
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
    
    # 担当者の設定（テキストフィールドとして設定）
    if todo[:assignee]
      properties["担当者"] = {
        rich_text: [
          {
            text: {
              content: todo[:assignee]
            }
          }
        ]
      }
    end
    
    # 期限の設定
    if todo[:due_date]
      properties["期限"] = {
        date: {
          start: todo[:due_date]
        }
      }
    end
    
    request_body = {
      parent: { database_id: @task_database_id },
      properties: properties
    }
    
    response = make_notion_request(uri, request_body)
    
    if response[:success]
      @logger.info("Successfully created task: #{todo[:task]}")
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