require 'google/apis/drive_v3'
require 'googleauth'
require 'json'

# Google Drive APIクライアント
# IAMでサービスアカウントに権限を付与
class GoogleDriveClient
  def initialize(credentials_json, logger, slack_notification_service = nil)
    @logger = logger
    @credentials_json = credentials_json
    @drive_service = nil
    @slack_notification_service = slack_notification_service
  end

  def get_file_content(file_id)
    @logger.info("Fetching file content from Google Drive: #{file_id}")
    
    begin
      # Initialize the Drive service if not already done
      initialize_drive_service unless @drive_service
      
      # Get file metadata first
      @file = @drive_service.get_file(
        file_id,
        fields: 'id, name, size, mimeType, webViewLink'
      )
      
      @logger.info("File info - Name: #{@file.name}, Size: #{@file.size}, Type: #{@file.mime_type}")
      @logger.info("File URL: #{@file.web_view_link}")
      
      # Check if file is too large (e.g., > 100MB)
      if @file.size && @file.size > 100_000_000
        raise "File too large: #{@file.size} bytes (max 100MB)"
      end
      
      # Download file content using the file object we already have
      content = download_file_content(@file)
      
      @logger.info("Successfully downloaded file content: #{content.length} characters")
      
      # Return both content and metadata
      {
        content: content,
        metadata: {
          id: @file.id,
          name: @file.name,
          size: @file.size,
          mime_type: @file.mime_type,
          web_view_link: @file.web_view_link
        }
      }
      
    rescue Google::Apis::ClientError => e
      if e.status_code == 404
        @logger.error("File not found: #{file_id}")
        notify_error("File not found: #{file_id}", file_id: file_id)
        raise "File not found: #{file_id}"
      elsif e.status_code == 403
        @logger.error("Access denied to file: #{file_id}")
        notify_error("Access denied to file: #{file_id}", file_id: file_id)
        raise "Access denied to file: #{file_id}"
      else
        @logger.error("Google Drive API client error: #{e.message} (status: #{e.status_code})")
        notify_error("Google Drive API client error: #{e.message} (status: #{e.status_code})", file_id: file_id)
        raise "Failed to fetch file from Google Drive: #{e.message}"
      end
    rescue Google::Apis::AuthorizationError => e
      @logger.error("Google Drive API error: #{e.message}")
      notify_error("Google Drive API authorization error: #{e.message}", file_id: file_id)
      raise "Failed to fetch file from Google Drive: #{e.message}"
    rescue Google::Apis::Error => e
      @logger.error("Google Drive API error: #{e.message}")
      notify_error("Google Drive API error: #{e.message}", file_id: file_id)
      raise "Failed to fetch file from Google Drive: #{e.message}"
    rescue StandardError => e
      @logger.error("Error fetching file: #{e.message}")
      raise
    end
  end


  private

  def notify_error(error_message, context = {})
    return unless @slack_notification_service
    
    @slack_notification_service.send_error_notification(error_message, context)
  rescue => e
    @logger.error("Failed to send Slack error notification: #{e.message}")
  end

  def initialize_drive_service
    @logger.info("Initializing Google Drive service")
    
    # Parse credentials JSON
    credentials = JSON.parse(@credentials_json)
    
    # サービスアカウント認証の作成
    # IAMで必要な権限を付与済み
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(@credentials_json),
      scope: 'https://www.googleapis.com/auth/drive.readonly'
    )
    
    # Initialize Drive service
    @drive_service = Google::Apis::DriveV3::DriveService.new
    @drive_service.authorization = authorizer
    
    @logger.info("Google Drive service initialized successfully")
  end

  def download_file_content(file)
    # Use the file object passed in (already contains metadata)
    @logger.info("Processing file type: #{file.mime_type}")
    
    case file.mime_type
    when 'application/vnd.google-apps.document'
      # Google Docs - export as plain text
      @logger.info("Exporting Google Document as plain text")
      export_google_document(file.id)
    when 'text/plain'
      # Plain text file - direct download
      @logger.info("Downloading plain text file")
      download_text_file(file.id)
    else
      # Try to export as text first, then fallback to direct download
      @logger.info("Unknown file type #{file.mime_type}, attempting text export")
      begin
        export_google_document(file.id)
      rescue Google::Apis::ClientError => e
        @logger.warn("Export failed, trying direct download: #{e.message}")
        download_text_file(file.id)
      end
    end
  end

  def export_google_document(file_id)
    content = StringIO.new
    @drive_service.export_file(
      file_id,
      'text/plain',
      download_dest: content
    )
    content.string.force_encoding('UTF-8')
  end

  def download_text_file(file_id)
    content = StringIO.new
    @drive_service.get_file(
      file_id,
      download_dest: content
    )
    content.string.force_encoding('UTF-8')
  end
end