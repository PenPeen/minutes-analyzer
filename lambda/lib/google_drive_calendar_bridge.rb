require_relative 'google_calendar_client'
require 'google/apis/drive_v3'
require 'googleauth'
require 'time'

class GoogleDriveCalendarBridge
  attr_reader :calendar_client, :drive_service
  
  def initialize(service_account_json = nil)
    @service_account_json = service_account_json || ENV['GOOGLE_SERVICE_ACCOUNT_JSON']
    raise 'Service account JSON is required' unless @service_account_json
    
    @calendar_client = GoogleCalendarClient.new(@service_account_json)
    @drive_service = initialize_drive_service
  end
  
  # 録画ファイルIDから会議を特定し、参加者情報を含む詳細を取得
  def find_meeting_with_participants(file_id)
    # ファイル情報を取得
    file_info = get_file_info(file_id)
    return nil unless file_info
    
    # ファイル作成時刻を基に会議を検索
    meeting = find_meeting_by_file_creation(file_id, file_info)
    return nil unless meeting
    
    # 参加者情報を追加
    participants = @calendar_client.get_event_participants(meeting.id)
    
    {
      event: meeting,
      participants: participants,
      file_info: {
        id: file_info.id,
        name: file_info.name,
        created_time: file_info.created_time,
        mime_type: file_info.mime_type
      }
    }
  end
  
  # 複数の録画ファイルから一括で会議を特定
  def batch_find_meetings(file_ids)
    results = {}
    
    file_ids.each do |file_id|
      begin
        results[file_id] = find_meeting_with_participants(file_id)
      rescue => e
        results[file_id] = { error: e.message }
      end
    end
    
    results
  end
  
  # 定例会議でも確実に特定するための拡張検索
  def find_recurring_meeting(file_id, series_id = nil)
    file_info = get_file_info(file_id)
    return nil unless file_info
    
    file_created_time = Time.parse(file_info.created_time)
    
    # 検索範囲を前後48時間に拡大（定例会議対応）
    time_min = (file_created_time - 48 * 3600).iso8601
    time_max = (file_created_time + 48 * 3600).iso8601
    
    events = @calendar_client.list_events('primary', time_min: time_min, time_max: time_max)
    
    # シリーズIDが指定されている場合は、それを優先
    if series_id
      event = events.find { |e| e.recurring_event_id == series_id }
      return event if event
    end
    
    # attachmentsによる特定を試みる
    event = find_by_attachments(events, file_id)
    return event if event
    
    # 定例会議パターンマッチング
    find_by_recurring_pattern(events, file_info)
  end
  
  private
  
  def initialize_drive_service
    service = Google::Apis::DriveV3::DriveService.new
    service.authorization = authorize_drive
    service
  end
  
  def authorize_drive
    if @service_account_json.start_with?('{')
      key_json = @service_account_json
    else
      key_json = File.read(@service_account_json)
    end
    
    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(key_json),
      scope: ['https://www.googleapis.com/auth/drive.readonly']
    )
  end
  
  def get_file_info(file_id)
    @drive_service.get_file(
      file_id,
      fields: 'id,name,createdTime,mimeType,parents,webViewLink'
    )
  rescue => e
    puts "Error fetching file info: #{e.message}"
    nil
  end
  
  def find_meeting_by_file_creation(file_id, file_info)
    file_created_time = Time.parse(file_info.created_time)
    
    # 前後24時間のイベントを検索
    time_min = (file_created_time - 24 * 3600).iso8601
    time_max = (file_created_time + 24 * 3600).iso8601
    
    events = @calendar_client.list_events('primary', time_min: time_min, time_max: time_max)
    
    # 1. attachmentsのfileIdで直接照合（最も確実）
    event = find_by_attachment_id(events, file_id)
    return event if event
    
    # 2. attachmentsのfileUrlでパターンマッチング
    event = find_by_attachment_url(events, file_id)
    return event if event
    
    # 3. 時刻とタイトルでマッチング（フォールバック）
    find_by_time_and_name(events, file_created_time, file_info.name)
  end
  
  def find_by_attachment_id(events, file_id)
    events.find do |event|
      next unless event.attachments
      event.attachments.any? { |att| att.file_id == file_id }
    end
  end
  
  def find_by_attachment_url(events, file_id)
    events.find do |event|
      next unless event.attachments
      event.attachments.any? do |att|
        att.file_url&.include?(file_id) || att.icon_link&.include?(file_id)
      end
    end
  end
  
  def find_by_attachments(events, file_id)
    find_by_attachment_id(events, file_id) || find_by_attachment_url(events, file_id)
  end
  
  def find_by_time_and_name(events, file_created_time, file_name)
    # ファイル名から会議タイトルを抽出
    meeting_title = extract_meeting_title(file_name)
    
    matching_events = events.select do |event|
      next unless event.start&.date_time
      
      event_start = Time.parse(event.start.date_time)
      event_end = event.end&.date_time ? Time.parse(event.end.date_time) : event_start + 3600
      
      # 録画ファイルは通常、会議終了後1時間以内に作成される
      time_match = file_created_time >= event_start && file_created_time <= event_end + 3600
      
      # タイトルの類似性チェック
      title_match = meeting_title && fuzzy_match(event.summary, meeting_title)
      
      time_match && title_match
    end
    
    # 最も時間が近いイベントを返す
    matching_events.min_by do |event|
      event_end = event.end&.date_time ? Time.parse(event.end.date_time) : Time.parse(event.start.date_time) + 3600
      (file_created_time - event_end).abs
    end
  end
  
  def find_by_recurring_pattern(events, file_info)
    file_created_time = Time.parse(file_info.created_time)
    meeting_title = extract_meeting_title(file_info.name)
    
    # 定例会議は同じタイトルパターンを持つことが多い
    recurring_candidates = events.select do |event|
      event.recurring_event_id && fuzzy_match(event.summary, meeting_title)
    end
    
    # 時間的に最も近いものを選択
    recurring_candidates.min_by do |event|
      event_start = Time.parse(event.start.date_time)
      (file_created_time - event_start).abs
    end
  end
  
  def extract_meeting_title(file_name)
    # 日付プレフィックスと拡張子を除去
    # 例: "2025年1月15日_新機能リリース進捗確認ミーティング.txt" -> "新機能リリース進捗確認ミーティング"
    cleaned = file_name.gsub(/^\d{4}年\d{1,2}月\d{1,2}日[_\s]/, '')
    cleaned.gsub(/\.\w+$/, '')
  end
  
  def fuzzy_match(str1, str2)
    return false unless str1 && str2
    
    # 正規化: 小文字化、スペース除去
    normalized1 = str1.downcase.gsub(/\s+/, '')
    normalized2 = str2.downcase.gsub(/\s+/, '')
    
    # 完全一致または部分一致をチェック
    normalized1.include?(normalized2) || normalized2.include?(normalized1)
  end
end