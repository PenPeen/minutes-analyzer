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
  
  def find_meeting_by_recording_file(file_id, drive_client)
    file_info = drive_client.get_file(file_id, fields: 'createdTime, name')
    file_created_time = Time.parse(file_info.created_time)
    
    # Search for events within 24 hours before and after file creation
    time_min = (file_created_time - 24 * 3600).iso8601
    time_max = (file_created_time + 24 * 3600).iso8601
    
    events = list_events('primary', time_min: time_min, time_max: time_max)
    
    # First, try to find by attachment file ID (most reliable)
    event = find_event_by_attachment_file_id(events, file_id)
    return event if event
    
    # Fallback: find by attachment file URL pattern
    event = find_event_by_attachment_url(events, file_id)
    return event if event
    
    # Last fallback: find by time and title matching
    find_event_by_time_and_title(events, file_created_time, file_info.name)
  end
  
  def get_event_participants(event_id, calendar_id = 'primary')
    event = @service.get_event(calendar_id, event_id)
    return [] unless event.attendees
    
    # Filter out resources (meeting rooms, etc.) and extract email addresses
    event.attendees
      .reject { |attendee| attendee.resource }
      .map { |attendee| attendee.email }
      .compact
  end
  
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
  
  def get_event(event_id, calendar_id = 'primary')
    @service.get_event(calendar_id, event_id)
  end
  
  private
  
  def authorize
    if @service_account_json.start_with?('{')
      # JSON string provided directly
      key_json = @service_account_json
    else
      # Path to JSON file
      key_json = File.read(@service_account_json)
    end
    
    key_data = JSON.parse(key_json)
    
    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(key_json),
      scope: SCOPES
    )
  end
  
  def find_event_by_attachment_file_id(events, file_id)
    events.find do |event|
      next unless event.attachments
      
      event.attachments.any? { |attachment| attachment.file_id == file_id }
    end
  end
  
  def find_event_by_attachment_url(events, file_id)
    events.find do |event|
      next unless event.attachments
      
      event.attachments.any? do |attachment|
        attachment.file_url&.include?(file_id)
      end
    end
  end
  
  def find_event_by_time_and_title(events, file_created_time, file_name)
    # Extract meeting title from file name (e.g., "2025年1月15日_新機能リリース進捗確認ミーティング.txt")
    meeting_title = extract_meeting_title(file_name)
    
    # Find events that match the time window and title
    matching_events = events.select do |event|
      next unless event.start&.date_time
      
      event_start = Time.parse(event.start.date_time)
      event_end = Time.parse(event.end.date_time) if event.end&.date_time
      
      # Check if file was created within 1 hour after meeting end
      time_match = if event_end
                     file_created_time >= event_start && file_created_time <= event_end + 3600
                   else
                     (file_created_time - event_start).abs <= 3600
                   end
      
      # Check title similarity
      title_match = meeting_title && event.summary&.include?(meeting_title)
      
      time_match && title_match
    end
    
    # Return the best match (closest in time)
    matching_events.min_by do |event|
      event_start = Time.parse(event.start.date_time)
      (file_created_time - event_start).abs
    end
  end
  
  def extract_meeting_title(file_name)
    # Remove date prefix and file extension
    # Example: "2025年1月15日_新機能リリース進捗確認ミーティング.txt" -> "新機能リリース進捗確認ミーティング"
    file_name.gsub(/^\d{4}年\d{1,2}月\d{1,2}日_/, '').gsub(/\.\w+$/, '')
  end
end