require 'concurrent'
require 'json'
require 'time'
require_relative 'google_drive_calendar_bridge'
require_relative 'slack_user_manager'
require_relative 'notion_user_manager'

class MeetingTranscriptProcessor
  attr_reader :calendar_bridge, :slack_manager, :notion_manager
  
  def initialize(config = {})
    @config = {
      google_calendar_enabled: ENV['GOOGLE_CALENDAR_ENABLED'] == 'true',
      user_mapping_enabled: ENV['USER_MAPPING_ENABLED'] == 'true',
      parallel_processing: true,
      max_threads: 10
    }.merge(config)
    
    # 各サービスのクライアントを初期化
    if @config[:google_calendar_enabled]
      @calendar_bridge = GoogleDriveCalendarBridge.new(@config[:google_service_account_json])
    end
    
    if @config[:user_mapping_enabled]
      @slack_manager = SlackUserManager.new(@config[:slack_bot_token])
      @notion_manager = NotionUserManager.new(@config[:notion_api_key])
    end
    
    # 並列処理用のスレッドプール
    if @config[:parallel_processing]
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 2,
        max_threads: @config[:max_threads],
        max_queue: 100,
        fallback_policy: :caller_runs
      )
    end
    
    @statistics = {
      processed: 0,
      successful: 0,
      failed: 0,
      processing_time: 0
    }
  end
  
  # メイン処理: ファイルIDから会議を特定し、参加者をマッピング
  def process_transcript(file_id)
    start_time = Time.now
    result = {
      file_id: file_id,
      status: 'processing',
      meeting: nil,
      participants: [],
      user_mappings: {
        slack: {},
        notion: {}
      },
      errors: []
    }
    
    begin
      # Step 1: 会議を特定
      if @config[:google_calendar_enabled]
        meeting_info = @calendar_bridge.find_meeting_with_participants(file_id)
        
        if meeting_info
          result[:meeting] = format_meeting_info(meeting_info[:event])
          result[:participants] = meeting_info[:participants]
        else
          result[:errors] << "Meeting not found for file ID: #{file_id}"
        end
      end
      
      # Step 2: 参加者をSlack/Notionユーザーにマッピング
      if @config[:user_mapping_enabled] && result[:participants].any?
        user_mappings = map_participants_to_users(result[:participants])
        result[:user_mappings] = user_mappings
      end
      
      result[:status] = 'completed'
      @statistics[:successful] += 1
    rescue => e
      result[:status] = 'failed'
      result[:errors] << e.message
      @statistics[:failed] += 1
      puts "Error processing transcript: #{e.message}"
      puts e.backtrace.join("\n")
    ensure
      @statistics[:processed] += 1
      @statistics[:processing_time] += (Time.now - start_time)
    end
    
    result
  end
  
  # 複数の議事録を並列処理
  def batch_process_transcripts(file_ids)
    results = {}
    
    if @config[:parallel_processing]
      # 並列処理
      futures = file_ids.map do |file_id|
        Concurrent::Promise.execute(executor: @executor) do
          [file_id, process_transcript(file_id)]
        end
      end
      
      # 結果を収集
      futures.each do |future|
        file_id, result = future.value
        results[file_id] = result
      end
    else
      # 逐次処理
      file_ids.each do |file_id|
        results[file_id] = process_transcript(file_id)
      end
    end
    
    results
  end
  
  # 参加者をSlack/Notionユーザーにマッピング
  def map_participants_to_users(participant_emails)
    mappings = {
      slack: {},
      notion: {}
    }
    
    if @config[:parallel_processing]
      # Slack と Notion のマッピングを並列実行
      slack_future = Concurrent::Promise.execute(executor: @executor) do
        @slack_manager.batch_lookup_users(participant_emails)
      end
      
      notion_future = Concurrent::Promise.execute(executor: @executor) do
        @notion_manager.batch_find_users(participant_emails)
      end
      
      mappings[:slack] = slack_future.value || {}
      mappings[:notion] = notion_future.value || {}
    else
      # 逐次実行
      mappings[:slack] = @slack_manager.batch_lookup_users(participant_emails)
      mappings[:notion] = @notion_manager.batch_find_users(participant_emails)
    end
    
    # メンション形式を生成
    mappings[:slack_mentions] = generate_slack_mentions(mappings[:slack])
    
    mappings
  rescue => e
    puts "Error mapping participants: #{e.message}"
    mappings
  end
  
  # Slackメンションを生成
  def generate_slack_mentions(slack_users)
    mentions = []
    
    slack_users.each do |email, user_info|
      next if user_info.is_a?(Hash) && user_info[:error]
      
      if user_info && user_info[:id]
        mentions << "<@#{user_info[:id]}>"
      end
    end
    
    mentions
  end
  
  # アクション項目の担当者を自動設定
  def assign_action_owners(actions, user_mappings)
    return actions unless @config[:user_mapping_enabled]
    
    updated_actions = []
    
    actions.each do |action|
      # 担当者のメールアドレスから Notion ユーザーを特定
      if action['assignee_email']
        notion_user = user_mappings[:notion][action['assignee_email']]
        
        if notion_user
          action['notion_user_id'] = notion_user[:id]
          action['auto_assigned'] = true
        end
      end
      
      updated_actions << action
    end
    
    updated_actions
  end
  
  # NotionタスクDBに担当者を一括更新
  def update_notion_task_assignees(task_assignments)
    return {} unless @notion_manager
    
    @notion_manager.batch_update_task_assignees(task_assignments)
  end
  
  # 統計情報を取得
  def get_statistics
    {
      total_processed: @statistics[:processed],
      successful: @statistics[:successful],
      failed: @statistics[:failed],
      success_rate: calculate_success_rate,
      average_processing_time: calculate_average_processing_time
    }
  end
  
  # CloudWatchメトリクスを送信
  def send_metrics_to_cloudwatch
    # CloudWatch カスタムメトリクスの送信
    # 実装は別途 CloudWatch SDK を使用
    metrics = {
      'ProcessedTranscripts' => @statistics[:processed],
      'SuccessfulMappings' => @statistics[:successful],
      'FailedMappings' => @statistics[:failed],
      'AverageProcessingTime' => calculate_average_processing_time
    }
    
    puts "Metrics to send: #{metrics.to_json}"
    # TODO: CloudWatch SDK を使用してメトリクスを送信
  end
  
  # クリーンアップ
  def cleanup
    @executor&.shutdown
    @executor&.wait_for_termination(10)
  end
  
  private
  
  def format_meeting_info(event)
    return nil unless event
    
    {
      id: event.id,
      summary: event.summary,
      description: event.description,
      start_time: event.start&.date_time || event.start&.date,
      end_time: event.end&.date_time || event.end&.date,
      organizer: event.organizer&.email,
      attendees_count: event.attendees&.size || 0,
      location: event.location,
      recurring: !event.recurring_event_id.nil?
    }
  end
  
  def calculate_success_rate
    return 0 if @statistics[:processed] == 0
    (@statistics[:successful].to_f / @statistics[:processed] * 100).round(2)
  end
  
  def calculate_average_processing_time
    return 0 if @statistics[:processed] == 0
    (@statistics[:processing_time] / @statistics[:processed]).round(3)
  end
end