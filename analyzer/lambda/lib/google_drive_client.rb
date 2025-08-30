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
        fields: 'id, name, size, mimeType, webViewLink'
      )
      
      @logger.info("File info - Name: #{file.name}, Size: #{file.size}, Type: #{file.mime_type}")
      @logger.info("File URL: #{file.web_view_link}")
      
      # Check if file is too large (e.g., > 100MB)
      if file.size && file.size > 100_000_000
        raise "File too large: #{file.size} bytes (max 100MB)"
      end
      
      # Download file content
      content = download_file_content(file_id)
      
      @logger.info("Successfully downloaded file content: #{content.length} characters")
      
      # Return both content and metadata
      {
        content: content,
        metadata: {
          id: file.id,
          name: file.name,
          size: file.size,
          mime_type: file.mime_type,
          web_view_link: file.web_view_link
        }
      }
      
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
    # For text files, we can export as plain text
    content = StringIO.new
    
    @drive_service.export_file(
      file_id,
      'text/plain',
      download_dest: content
    )
    
    content.string.force_encoding('UTF-8')
  rescue Google::Apis::ClientError => e
    # If export fails, try direct download
    @logger.warn("Export failed, trying direct download: #{e.message}")
    
    content = StringIO.new
    @drive_service.get_file(
      file_id,
      download_dest: content
    )
    
    content.string.force_encoding('UTF-8')
  end
end