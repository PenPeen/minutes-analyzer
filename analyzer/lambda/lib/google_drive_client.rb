require 'google/apis/drive_v3'
require 'googleauth'
require 'json'

# Google Drive APIクライアント
# IAMでサービスアカウントに権限を付与
class GoogleDriveClient
  def initialize(credentials_json, logger)
    @logger = logger
    @credentials_json = credentials_json
    @drive_service = nil
  end

  def get_file_content(file_id)
    @logger.info("Fetching file content from Google Drive: #{file_id}")
    
    begin
      # Initialize the Drive service if not already done
      initialize_drive_service unless @drive_service
      
      # Get file metadata first
      file = @drive_service.get_file(
        file_id,
        fields: 'id, name, size, mimeType'
      )
      
      @logger.info("File info - Name: #{file.name}, Size: #{file.size}, Type: #{file.mime_type}")
      
      # Check if file is too large (e.g., > 100MB)
      if file.size && file.size > 100_000_000
        raise "File too large: #{file.size} bytes (max 100MB)"
      end
      
      # Download file content
      content = download_file_content(file_id)
      
      @logger.info("Successfully downloaded file content: #{content.length} characters")
      content
      
    rescue Google::Apis::ClientError => e
      if e.status_code == 404
        @logger.error("File not found: #{file_id}")
        raise "File not found: #{file_id}"
      elsif e.status_code == 403
        @logger.error("Access denied to file: #{file_id}")
        raise "Access denied to file: #{file_id}"
      else
        @logger.error("Google Drive API client error: #{e.message} (status: #{e.status_code})")
        raise "Failed to fetch file from Google Drive: #{e.message}"
      end
    rescue Google::Apis::AuthorizationError => e
      @logger.error("Google Drive API authorization error: #{e.message}")
      raise "Authorization failed for Google Drive: #{e.message}"
    rescue Google::Apis::Error => e
      @logger.error("Google Drive API error: #{e.message}")
      raise "Failed to fetch file from Google Drive: #{e.message}"
    rescue StandardError => e
      @logger.error("Error fetching file: #{e.message}")
      raise
    end
  end

  private

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

  def download_file_content(file_id)
    # Get file metadata to determine the type
    file = @drive_service.get_file(file_id, fields: 'mimeType')
    
    case file.mime_type
    when 'application/vnd.google-apps.document'
      # Google Docs - export as plain text
      @logger.info("Exporting Google Document as plain text")
      export_google_document(file_id)
    when 'text/plain'
      # Plain text file - direct download
      @logger.info("Downloading plain text file")
      download_text_file(file_id)
    else
      # Try to export as text first, then fallback to direct download
      @logger.info("Unknown file type #{file.mime_type}, attempting text export")
      begin
        export_google_document(file_id)
      rescue Google::Apis::ClientError => e
        @logger.warn("Text export failed for #{file.mime_type}, trying direct download: #{e.message}")
        download_text_file(file_id)
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