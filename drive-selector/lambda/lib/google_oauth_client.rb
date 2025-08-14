# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'securerandom'
require 'aws-sdk-secretsmanager'
require_relative 'dynamodb_token_store'

class GoogleOAuthClient
  GOOGLE_OAUTH_BASE_URL = 'https://accounts.google.com/o/oauth2/v2/auth'
  GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'
  GOOGLE_DRIVE_SCOPE = 'https://www.googleapis.com/auth/drive.metadata.readonly'

  def initialize
    @client_id = fetch_secret('GOOGLE_CLIENT_ID')
    @client_secret = fetch_secret('GOOGLE_CLIENT_SECRET')
    @token_store = DynamoDbTokenStore.new
  end

  # 認証URLを生成
  def generate_auth_url(slack_user_id, state = nil, event = nil)
    state ||= generate_state(slack_user_id)
    redirect_uri = build_redirect_uri(event)

    params = {
      client_id: @client_id,
      redirect_uri: redirect_uri,
      response_type: 'code',
      scope: GOOGLE_DRIVE_SCOPE,
      access_type: 'offline',
      prompt: 'consent',
      state: state
    }

    "#{GOOGLE_OAUTH_BASE_URL}?#{URI.encode_www_form(params)}"
  end

  # 認証コードをアクセストークンに交換
  def exchange_code_for_token(code, event = nil)
    uri = URI(GOOGLE_TOKEN_URL)
    redirect_uri = build_redirect_uri(event)

    params = {
      code: code,
      client_id: @client_id,
      client_secret: @client_secret,
      redirect_uri: redirect_uri,
      grant_type: 'authorization_code'
    }

    response = make_http_request(uri, params)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      raise "Token exchange failed: #{response.code} - #{response.body}"
    end
  end

  # リフレッシュトークンを使用してアクセストークンを更新
  def refresh_access_token(refresh_token)
    uri = URI(GOOGLE_TOKEN_URL)

    params = {
      refresh_token: refresh_token,
      client_id: @client_id,
      client_secret: @client_secret,
      grant_type: 'refresh_token'
    }

    response = make_http_request(uri, params)

    if response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    else
      raise "Token refresh failed: #{response.code} - #{response.body}"
    end
  end

  # ユーザーのトークンをDynamoDBに保存
  def save_tokens(slack_user_id, tokens)
    @token_store.save_tokens(slack_user_id, tokens)
  end

  # ユーザーのトークンをDynamoDBから取得
  def get_tokens(slack_user_id, refresh_attempted: false)
    stored_token = @token_store.get_tokens(slack_user_id)
    return nil unless stored_token

    # トークンの有効期限を確認（DynamoDbTokenStoreで既にチェック済み）
    # ただし、期限切れの場合はリフレッシュを試行
    if stored_token[:expires_at] && stored_token[:expires_at] < (Time.now.to_i + 300)
      return nil if refresh_attempted  # 無限再帰を防止

      # アクセストークンの有効期限が切れている場合、リフレッシュ
      if stored_token[:refresh_token]
        begin
          new_tokens = refresh_access_token(stored_token[:refresh_token])
          @token_store.update_tokens(slack_user_id, new_tokens)
          return get_tokens(slack_user_id, refresh_attempted: true)
        rescue => e
          puts "Token refresh failed: #{e.message}"
          # リフレッシュに失敗した場合はDynamoDBからトークンを削除
          @token_store.delete_tokens(slack_user_id)
          return nil
        end
      else
        return nil # リフレッシュトークンがない場合は再認証が必要
      end
    end

    stored_token
  end

  # ユーザーが認証済みかチェック
  def authenticated?(slack_user_id)
    @token_store.authenticated?(slack_user_id)
  end

  # トークンをDynamoDBから削除（ログアウト）
  def delete_tokens(slack_user_id)
    @token_store.delete_tokens(slack_user_id)
  end

  private

  # Lambda実行時の情報からリダイレクトURIを構築
  def build_redirect_uri(event)
    if event && event['requestContext'] && event['requestContext']['domainName']
      # API Gateway経由でのLambda実行時
      domain_name = event['requestContext']['domainName']
      stage = event['requestContext']['stage'] || 'production'
      "https://#{domain_name}/#{stage}/oauth/callback"
    else
      # テスト環境やローカル開発時のフォールバック
      'http://localhost:3000/oauth/callback'
    end
  end

  # Secrets Managerから値を取得
  def fetch_secret(key)
    return ENV[key] if ENV[key] # 環境変数から直接取得できる場合

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

  # state パラメータを生成（CSRF対策）
  def generate_state(slack_user_id)
    Base64.urlsafe_encode64("#{slack_user_id}:#{SecureRandom.hex(16)}")
  end

  # Net::HTTPクライアントでHTTPリクエストを実行
  def make_http_request(uri, params)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = URI.encode_www_form(params)

    # リトライロジック（Faradayのリトライ機能の代替）
    max_retries = 2
    retries = 0

    begin
      response = http.request(request)
      puts "HTTP #{request.method} #{uri} -> #{response.code}" if ENV['DEBUG']
      response
    rescue Net::ReadTimeout, Net::OpenTimeout => e
      if (retries += 1) <= max_retries
        puts "Retrying HTTP request (#{retries}/#{max_retries}): #{e.message}" if ENV['DEBUG']
        sleep(1.0 * retries)
        retry
      else
        raise
      end
    end
  end
end
