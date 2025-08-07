require 'google/apis/calendar_v3'
require 'googleauth'
require 'json'
require 'time'

class GoogleCalendarClient
  SCOPES = ['https://www.googleapis.com/auth/calendar.readonly'].freeze
  
  def initialize(service_account_json = nil)
    @service_account_json = service_account_json || ENV['GOOGLE_SERVICE_ACCOUNT_JSON']
    raise 'Service account JSON is required' unless @service_account_json
    
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.authorization = authorize
  end
  
  # 録画ファイルIDから対応する会議イベントを検索
  # @param file_id [String] Google DriveのファイルID
  # @param drive_client [Google::Apis::DriveV3::DriveService] Google Drive APIクライアント
  # @return [Google::Apis::CalendarV3::Event, nil] 該当する会議イベント、見つからない場合はnil
  def find_meeting_by_recording_file(file_id, drive_client)
    file_info = drive_client.get_file(file_id, fields: 'createdTime, name')
    file_created_time = Time.parse(file_info.created_time)
    
    # ファイル作成時刻の前後24時間以内のイベントを検索
    time_min = (file_created_time - 24 * 3600).iso8601
    time_max = (file_created_time + 24 * 3600).iso8601
    
    events = list_events('primary', time_min: time_min, time_max: time_max)
    
    # 添付ファイルIDによる直接マッチング（最も信頼性が高い方法）
    find_event_by_attachment_file_id(events, file_id)
  end
  
  # イベントの参加者メールアドレスリストを取得
  # @param event_id [String] イベントID
  # @param calendar_id [String] カレンダーID（デフォルト: 'primary'）
  # @return [Array<String>] 参加者のメールアドレスリスト（リソースを除く）
  def get_event_participants(event_id, calendar_id = 'primary')
    event = @service.get_event(calendar_id, event_id)
    return [] unless event.attendees
    
    # リソース（会議室など）を除外して、参加者のメールアドレスのみを抽出
    event.attendees
      .reject { |attendee| attendee.resource }
      .map { |attendee| attendee.email }
      .compact
  end
  
  # カレンダーのイベントリストを取得
  # @param calendar_id [String] カレンダーID（デフォルト: 'primary'）
  # @param options [Hash] 検索オプション
  # @option options [String] :time_min 検索開始時刻（ISO8601形式）
  # @option options [String] :time_max 検索終了時刻（ISO8601形式）
  # @option options [Integer] :max_results ページあたりの最大結果数（デフォルト: 250）
  # @return [Array<Google::Apis::CalendarV3::Event>] イベントリスト
  def list_events(calendar_id = 'primary', options = {})
    events = []
    page_token = nil
    
    loop do
      response = @service.list_events(
        calendar_id,
        max_results: options[:max_results] || 250,
        page_token: page_token,
        single_events: true,
        order_by: 'startTime',
        time_min: options[:time_min],
        time_max: options[:time_max]
      )
      
      events.concat(response.items) if response.items
      
      page_token = response.next_page_token
      break unless page_token
    end
    
    events
  end
  
  # 特定のイベントを取得
  # @param event_id [String] イベントID
  # @param calendar_id [String] カレンダーID（デフォルト: 'primary'）
  # @return [Google::Apis::CalendarV3::Event] イベント情報
  def get_event(event_id, calendar_id = 'primary')
    @service.get_event(calendar_id, event_id)
  end
  
  private
  
  # サービスアカウントで認証を行う
  # @return [Google::Auth::ServiceAccountCredentials] 認証情報
  def authorize
    if @service_account_json.start_with?('{')
      # JSON文字列が直接提供された場合
      key_json = @service_account_json
    else
      # JSONファイルのパスが提供された場合
      key_json = File.read(@service_account_json)
    end
    
    key_data = JSON.parse(key_json)
    
    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(key_json),
      scope: SCOPES
    )
  end
  
  # 添付ファイルIDでイベントを検索
  # @param events [Array<Google::Apis::CalendarV3::Event>] 検索対象のイベントリスト
  # @param file_id [String] 検索するファイルID
  # @return [Google::Apis::CalendarV3::Event, nil] 該当するイベント、見つからない場合はnil
  def find_event_by_attachment_file_id(events, file_id)
    events.find do |event|
      next unless event.attachments
      
      event.attachments.any? { |attachment| attachment.file_id == file_id }
    end
  end
end