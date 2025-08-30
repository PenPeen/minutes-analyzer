# frozen_string_literal: true

require 'google/apis/drive_v3'
require 'googleauth'
require_relative 'google_oauth_client'
require 'logger'

class GoogleDriveClient
  # カスタムエラークラス
  class AccessDeniedError < StandardError; end
  class FileNotFoundError < StandardError; end

  DRIVE_SERVICE = Google::Apis::DriveV3::DriveService
  SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_METADATA_READONLY

  def initialize(user_identifier)
    @logger = Logger.new(STDOUT)

    if user_identifier.is_a?(String) && user_identifier.start_with?('ya29.')
      # OAuth2アクセストークンとして扱う（新しい用途）
      @access_token = user_identifier
      @slack_user_id = nil
      @oauth_client = nil
    else
      # 既存の用途（Slack User IDとして扱う）
      @slack_user_id = user_identifier
      @access_token = nil
      @oauth_client = GoogleOAuthClient.new
    end

    @drive_service = DRIVE_SERVICE.new
    setup_authorization
  end

  # ファイルを検索
  def search_files(query, limit = 20, retry_on_auth_error = true)
    return [] unless authorized?

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
      @logger.error("Authorization error: #{e.message}")

      # retry_on_auth_errorフラグで再試行を制御（ローカル変数として管理）
      if retry_on_auth_error
        # トークンをリフレッシュして再試行
        refresh_authorization
        # 再帰呼び出しではなく、フラグを変更して再度呼び出し
        search_files(query, limit, false)
      else
        # 再試行済みの場合は空配列を返す
        []
      end
    rescue Google::Apis::Error => e
      @logger.error("Drive API error: #{e.message}")
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
    rescue Google::Apis::ClientError => e
      if e.status_code == 404
        notify_slack_error("File not found: #{file_id}", user_id: @slack_user_id)
        raise FileNotFoundError, "File not found: #{file_id}"
      elsif e.status_code == 403
        notify_slack_error("Access denied to file: #{file_id}", user_id: @slack_user_id)
        raise AccessDeniedError, "Access denied to file: #{file_id}"
      else
        @logger.error("Failed to get file info: #{e.message}")
        notify_slack_error("Failed to get file info: #{e.message}", user_id: @slack_user_id)
        raise StandardError, "Failed to get file info: #{e.message}"
      end
    rescue Google::Apis::AuthorizationError => e
      notify_slack_error("Authorization error: #{e.message}", user_id: @slack_user_id)
      raise AccessDeniedError, "Authorization error: #{e.message}"
    rescue Google::Apis::Error => e
      @logger.error("Failed to get file info: #{e.message}")
      notify_slack_error("Failed to get file info: #{e.message}", user_id: @slack_user_id)
      return nil
    end
  end

  # ユーザーが認証済みか確認
  def authorized?
    if @access_token
      # アクセストークンベースの場合は常にtrue（トークンが提供されている前提）
      true
    elsif @oauth_client && @slack_user_id
      # Slack User IDベースの場合は従来通り
      @oauth_client.authenticated?(@slack_user_id)
    else
      false
    end
  end

  # クエリのエスケープ（public for testing）
  def escape_query(query)
    return '' if query.nil? || query.empty?

    # Google Drive APIクエリの仕様に準拠したエスケープ
    # バックスラッシュ、シングルクォート、ダブルクォートをエスケープ
    query.to_s
      .gsub('\\', '\\\\\\\\')  # バックスラッシュを2重エスケープ（4つのバックスラッシュに変換）
      .gsub("'", "\\\\'")
      .gsub('"', '\\\\"')
  end

  private

  # Slack にエラー通知を送信
  def notify_slack_error(error_message, user_id: nil)
    @logger.info("notify_slack_error called: #{error_message}")
    @logger.info("SLACK_CHANNEL_ID: #{ENV['SLACK_CHANNEL_ID']}")
    @logger.info("SLACK_BOT_TOKEN present: #{!ENV['SLACK_BOT_TOKEN'].nil?}")
    
    return unless ENV['SLACK_CHANNEL_ID'] && ENV['SLACK_BOT_TOKEN']

    begin
      require_relative 'slack_api_client'
      slack_client = SlackApiClient.new

      error_blocks = [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: "🚨 *Drive API エラーが発生しました*"
          }
        },
        {
          type: 'section',
          fields: [
            {
              type: 'mrkdwn',
              text: "*エラー内容:*\n```#{error_message}```"
            },
            {
              type: 'mrkdwn',
              text: "*発生時刻:*\n#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
            }
          ]
        }
      ]

      if user_id
        error_blocks[1][:fields] << {
          type: 'mrkdwn',
          text: "*ユーザー:*\n<@#{user_id}>"
        }
      end

      slack_client.post_message(
        ENV['SLACK_CHANNEL_ID'],
        "Drive API エラーが発生しました",
        error_blocks
      )
    rescue => slack_error
      @logger.error("Failed to send Slack error notification: #{slack_error.message}")
    end
  end

  # 認証設定
  def setup_authorization
    if @access_token
      # アクセストークンベースの認証
      @drive_service.authorization = create_authorization(@access_token)
    elsif @oauth_client && @slack_user_id
      # Slack User IDベースの認証（従来通り）
      tokens = @oauth_client.get_tokens(@slack_user_id)
      return unless tokens
      @drive_service.authorization = create_authorization(tokens[:access_token])
    end
  end

  # 認証オブジェクトを作成
  def create_authorization(access_token)
    # Signetを使用してOAuth2クライアントを作成
    auth = Signet::OAuth2::Client.new(
      access_token: access_token,
      token_credential_uri: 'https://oauth2.googleapis.com/token',
      client_id: ENV.fetch('USE_SECRETS_MANAGER', 'true') == 'true' ?
                   fetch_from_secrets('GOOGLE_CLIENT_ID') :
                   ENV['GOOGLE_CLIENT_ID'],
      client_secret: ENV.fetch('USE_SECRETS_MANAGER', 'true') == 'true' ?
                      fetch_from_secrets('GOOGLE_CLIENT_SECRET') :
                      ENV['GOOGLE_CLIENT_SECRET']
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
        @logger.error("Failed to refresh tokens for user #{@slack_user_id}")
      end
    end
  end

  # Meet Recordingsフォルダ内のファイルを検索するためのクエリを構築
  def build_search_query(query)
    # Meet Recordingsフォルダを取得
    meet_folders = find_meet_recordings_folders

    if meet_folders.empty?
      @logger.warn("No Meet Recordings folders found")
      return "1=0"  # 結果なしを意図的に作る無効なクエリ
    end

    # 基本的な検索条件
    conditions = []

    # Meet Recordingsフォルダのいずれかを親に持つファイル
    folder_conditions = meet_folders.map { |folder| "'#{folder[:id]}' in parents" }
    conditions << "(#{folder_conditions.join(' or ')})"

    # ゴミ箱のファイルを除外
    conditions << "trashed = false"

    # 議事録として利用される可能性のあるファイル形式（Google Docsのみに制限）
    mime_types = [
      "application/vnd.google-apps.document",  # Google Docs
    ]
    mime_query = mime_types.map { |type| "mimeType = '#{type}'" }.join(" or ")
    conditions << "(#{mime_query})"

    # ユーザーの検索クエリを追加
    if query && !query.empty?
      escaped_query = escape_query(query)
      @logger.info("Original query: '#{query}' -> Escaped: '#{escaped_query}'")
      search_conditions = ["name contains '#{escaped_query}'"]

      # 大文字小文字の違いに対応
      if escaped_query != escaped_query.downcase
        search_conditions << "name contains '#{escaped_query.downcase}'"
      end
      if escaped_query != escaped_query.upcase
        search_conditions << "name contains '#{escaped_query.upcase}'"
      end

      query_condition = "(#{search_conditions.join(' or ')})"
      @logger.info("Query condition: #{query_condition}")
      conditions << query_condition
    end

    final_query = conditions.join(" and ")
    @logger.info("Final search query: #{final_query}")
    final_query
  end

  # Meet Recordingsフォルダを検索
  def find_meet_recordings_folders
    query = "name contains 'Meet Recordings' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
    @logger.info("Searching for folders with query: #{query}")

    begin
      response = @drive_service.list_files(
        q: query,
        page_size: 50,  # Meet Recordingsフォルダは複数存在する可能性がある
        fields: 'files(id,name)',
        supports_all_drives: true,
        include_items_from_all_drives: true
      )

      folders = (response.files || []).map do |folder|
        {
          id: folder.id,
          name: folder.name
        }
      end

      @logger.info("Found #{folders.size} meeting folders: #{folders.map { |f| f[:name] }.join(', ')}")
      folders
    rescue Google::Apis::Error => e
      @logger.error("Failed to find Meet Recordings folders: #{e.message}")
      notify_slack_error("Failed to find Meet Recordings folders: #{e.message}", user_id: @slack_user_id)
      []
    end
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
      @logger.error("Failed to fetch secret #{key}: #{e.message}")
      nil
    end
  end
end
