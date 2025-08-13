# frozen_string_literal: true

require 'google/apis/drive_v3'
require 'googleauth'
require_relative 'google_oauth_client'

class GoogleDriveClient
  DRIVE_SERVICE = Google::Apis::DriveV3::DriveService
  SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_METADATA_READONLY
  
  def initialize(slack_user_id)
    @slack_user_id = slack_user_id
    @oauth_client = GoogleOAuthClient.new
    @drive_service = DRIVE_SERVICE.new
    setup_authorization
  end

  # ファイルを検索
  def search_files(query, limit = 20)
    return [] unless authorized?
    
    # 各検索で再試行フラグをリセット
    @authorization_retried = false

    search_query = build_search_query(query)
    
    begin
      response = @drive_service.list_files(
        q: search_query,
        page_size: limit,
        fields: 'files(id,name,mimeType,modifiedTime,owners,webViewLink)',
        order_by: 'modifiedTime desc',
        supports_all_drives: true,
        include_items_from_all_drives: true
      )
      
      format_search_results(response.files || [])
    rescue Google::Apis::AuthorizationError => e
      puts "Authorization error: #{e.message}"
      # トークンをリフレッシュして再試行
      refresh_authorization
      retry_search_files(query, limit)
    rescue Google::Apis::Error => e
      puts "Drive API error: #{e.message}"
      []
    end
  end

  # ファイルの詳細情報を取得
  def get_file_info(file_id)
    return nil unless authorized?

    begin
      @drive_service.get_file(
        file_id,
        fields: 'id,name,mimeType,modifiedTime,size,owners,webViewLink,parents',
        supports_all_drives: true
      )
    rescue Google::Apis::Error => e
      puts "Failed to get file info: #{e.message}"
      nil
    end
  end

  # ユーザーが認証済みか確認
  def authorized?
    @oauth_client.authenticated?(@slack_user_id)
  end

  private

  # 認証設定
  def setup_authorization
    tokens = @oauth_client.get_tokens(@slack_user_id)
    return unless tokens

    # Google Auth用のAuthorizerを設定
    @drive_service.authorization = create_authorization(tokens[:access_token])
  end

  # 認証オブジェクトを作成
  def create_authorization(access_token)
    # Signetを使用してOAuth2クライアントを作成
    auth = Signet::OAuth2::Client.new(
      access_token: access_token,
      token_credential_uri: 'https://oauth2.googleapis.com/token',
      client_id: fetch_from_secrets('GOOGLE_CLIENT_ID') || ENV['GOOGLE_CLIENT_ID'],
      client_secret: fetch_from_secrets('GOOGLE_CLIENT_SECRET') || ENV['GOOGLE_CLIENT_SECRET']
    )
    auth
  end

  # トークンをリフレッシュして再認証
  def refresh_authorization
    tokens = @oauth_client.get_tokens(@slack_user_id)
    return unless tokens

    if tokens[:refresh_token]
      new_tokens = @oauth_client.refresh_access_token(tokens[:refresh_token])
      if new_tokens && new_tokens[:access_token]
        @oauth_client.save_tokens(@slack_user_id, new_tokens)
        setup_authorization
      else
        puts "Failed to refresh tokens for user #{@slack_user_id}"
      end
    end
  end

  # 再試行（1回のみ）
  def retry_search_files(query, limit)
    # 既に再試行済みの場合は空配列を返す
    return [] if @authorization_retried
    
    @authorization_retried = true
    search_files(query, limit)
  end

  # 検索クエリを構築
  def build_search_query(query)
    # 基本的な検索条件
    conditions = []
    
    # ゴミ箱のファイルを除外
    conditions << "trashed = false"
    
    # Googleドキュメント形式のファイルを検索
    mime_types = [
      "application/vnd.google-apps.document",
      "text/plain",
      "application/pdf"
    ]
    mime_query = mime_types.map { |type| "mimeType = '#{type}'" }.join(" or ")
    conditions << "(#{mime_query})"
    
    # ユーザーの検索クエリを追加
    if query && !query.empty?
      # ファイル名での検索（部分一致）
      conditions << "name contains '#{escape_query(query)}'"
    end
    
    # 議事録関連のキーワードを含むファイルを優先
    if query.nil? || query.empty?
      meeting_keywords = ['議事録', 'meeting', 'minutes', 'ミーティング', 'MTG']
      keyword_query = meeting_keywords.map { |keyword| "name contains '#{keyword}'" }.join(" or ")
      conditions << "(#{keyword_query})"
    end
    
    conditions.join(" and ")
  end

  # クエリのエスケープ
  def escape_query(query)
    # バックスラッシュとクォートを適切にエスケープ
    query.gsub('\\', '\\\\').gsub("'", "\\'")
  end

  # 検索結果をフォーマット
  def format_search_results(files)
    files.map do |file|
      {
        id: file.id,
        name: file.name,
        mime_type: file.mime_type,
        modified_time: file.modified_time,
        owner: file.owners&.first&.display_name || 'Unknown',
        web_view_link: file.web_view_link
      }
    end
  end

  # Secrets Managerから値を取得
  def fetch_from_secrets(key)
    require 'aws-sdk-secretsmanager'
    
    secrets_client = Aws::SecretsManager::Client.new
    secret_id = ENV['SECRETS_MANAGER_SECRET_ID'] || 'drive-selector-secrets'
    
    begin
      response = secrets_client.get_secret_value(secret_id: secret_id)
      secrets = JSON.parse(response.secret_string)
      secrets[key]
    rescue => e
      puts "Failed to fetch secret #{key}: #{e.message}"
      nil
    end
  end
end