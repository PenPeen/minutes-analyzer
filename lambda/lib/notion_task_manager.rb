require 'date'
require_relative 'notion_api_client'

class NotionTaskManager
  def initialize(api_key, task_database_id, logger)
    @api_key = api_key
    @task_database_id = task_database_id
    @logger = logger
    @notion_api = NotionApiClient.new(api_key, logger)
  end
  
  def create_tasks_from_actions(actions, parent_page_id)
    return [] unless actions.is_a?(Array) && actions.any?
    
    @logger.info("Creating #{actions.size} tasks in Notion task database")
    
    actions.map do |action|
      create_single_task(action, parent_page_id)
    end
  end
  
  private
  
  def create_single_task(action, parent_page_id)
    properties = build_task_properties(action, parent_page_id)
    children = build_task_children(action)
    
    request_body = {
      parent: { database_id: @task_database_id },
      properties: properties,
      children: children
    }
    
    response = @notion_api.create_page(request_body)
    
    if response[:success]
      {
        success: true,
        task_id: response[:data]['id'],
        task: action['task']
      }
    else
      @logger.error("Failed to create task: #{action['task']}, Error: #{response[:error]}")
      {
        success: false,
        task: action['task'],
        error: response[:error]
      }
    end
  rescue => e
    @logger.error("Exception creating task: #{e.message}")
    {
      success: false,
      task: action['task'],
      error: e.message
    }
  end
  
  def build_task_properties(action, parent_page_id)
    properties = {
      'Name' => {
        'title' => [
          {
            'text' => {
              'content' => action['task'] || 'Untitled Task'
            }
          }
        ]
      },
      'Status' => {
        'select' => { 'name' => '未着手' }
      },
      'Priority' => build_priority_property(action['priority'])
    }
    
    # 担当者設定
    if action['notion_user_id']
      properties['Assignee'] = {
        'people' => [{ 'id' => action['notion_user_id'] }]
      }
    end
    
    # 期限設定
    if action['deadline']
      properties['Deadline'] = build_deadline_property(action['deadline'])
    end
    
    # 親ページへのリレーション
    if parent_page_id
      properties['Meeting'] = {
        'relation' => [{ 'id' => parent_page_id }]
      }
    end
    
    properties
  end
  
  def build_task_children(action)
    page_builder = NotionPageBuilder.new(@logger)
    page_builder.build_task_content(action)
  end
  
  def build_priority_property(priority)
    priority_map = {
      'high' => '高',
      'medium' => '中',
      'low' => '低'
    }
    
    {
      'select' => { 'name' => priority_map[priority] || '低' }
    }
  end
  
  def build_deadline_property(deadline)
    return { 'date' => nil } unless deadline
    
    begin
      # 相対的な日付表現を処理
      parsed_date = parse_relative_date(deadline)
      { 'date' => { 'start' => parsed_date.to_s } }
    rescue => e
      @logger.warn("Failed to parse deadline: #{deadline}, Error: #{e.message}")
      { 'date' => nil }
    end
  end
  
  def parse_relative_date(deadline_text)
    today = Date.today
    
    case deadline_text
    when /今週末/
      days_until_sunday = (7 - today.wday) % 7
      days_until_sunday = 7 if days_until_sunday == 0
      today + days_until_sunday
    when /来週/
      today + 7
    when /今月末/
      Date.new(today.year, today.month, -1)
    when /(\d+)月(\d+)日/
      month = $1.to_i
      day = $2.to_i
      year = month >= today.month ? today.year : today.year + 1
      Date.new(year, month, day)
    else
      Date.parse(deadline_text)
    end
  end
end