# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'securerandom'
require 'aws-sdk-secretsmanager'

class GoogleOAuthClient
  GOOGLE_OAUTH_BASE_URL = 'https://accounts.google.com/o/oauth2/v2/auth'
  GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'
  GOOGLE_DRIVE_SCOPE = 'https://www.googleapis.com/auth/drive.metadata.readonly'
  
  MAX_CACHE_SIZE = 100  # キャッシュサイズ制限
  EXPIRY_BUFFER = 300   # トークン期限のバッファ（5分）
  
  def initialize
    @client_id = fetch_secret('GOOGLE_CLIENT_ID')
    @client_secret = fetch_secret('GOOGLE_CLIENT_SECRET')
    @redirect_uri = ENV['GOOGLE_REDIRECT_URI'] || 'http://localhost:3000/oauth/callback'
    # Lambdaメモリ内でのトークンキャッシュ（Lambda実行期間中のみ有効）
    @token_cache = {}
  end

  # 認証URLを生成
  def generate_auth_url(slack_user_id, state = nil)
    state ||= generate_state(slack_user_id)
    
    params = {
      client_id: @client_id,
      redirect_uri: @redirect_uri,
      response_type: 'code',
      scope: GOOGLE_DRIVE_SCOPE,
      access_type: 'offline',
      prompt: 'consent',
      state: state
    }
    
    "#{GOOGLE_OAUTH_BASE_URL}?#{URI.encode_www_form(params)}"
  end

  # 認証コードをアクセストークンに交換
  def exchange_code_for_token(code)
    uri = URI(GOOGLE_TOKEN_URL)
    
    params = {
      code: code,
      client_id: @client_id,
      client_secret: @client_secret,
      redirect_uri: @redirect_uri,
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

  # ユーザーのトークンをメモリキャッシュに保存
  def save_tokens(slack_user_id, tokens)
    # キャッシュサイズ制限（LRU風の簡単な削除）
    if @token_cache.size >= MAX_CACHE_SIZE
      # 最も古いエントリを削除
      oldest_key = @token_cache.keys.first
      @token_cache.delete(oldest_key)
    end
    
    @token_cache[slack_user_id] = {
      access_token: tokens['access_token'],
      refresh_token: tokens['refresh_token'],
      expires_at: Time.now.to_i + (tokens['expires_in'] || 3600),
      created_at: Time.now.to_i,
      updated_at: Time.now.to_i
    }
  end

  # ユーザーのトークンをメモリキャッシュから取得
  def get_tokens(slack_user_id, refresh_attempted: false)
    cached_token = @token_cache[slack_user_id]
    return nil unless cached_token
    
    # トークンの有効期限を確認（バッファ付き）
    if cached_token[:expires_at] && cached_token[:expires_at] < (Time.now.to_i + EXPIRY_BUFFER)
      return nil if refresh_attempted  # 無限再帰を防止
      
      # アクセストークンの有効期限が切れている場合、リフレッシュ
      if cached_token[:refresh_token]
        begin
          new_tokens = refresh_access_token(cached_token[:refresh_token])
          save_tokens(slack_user_id, new_tokens)
          return get_tokens(slack_user_id, refresh_attempted: true)
        rescue => e
          puts "Token refresh failed: #{e.message}"
          # リフレッシュに失敗した場合はキャッシュからトークンを削除
          @token_cache.delete(slack_user_id)
          return nil
        end
      else
        return nil # リフレッシュトークンがない場合は再認証が必要
      end
    end
    
    {
      access_token: cached_token[:access_token],
      refresh_token: cached_token[:refresh_token],
      expires_at: cached_token[:expires_at]
    }
  end

  # ユーザーが認証済みかチェック
  def authenticated?(slack_user_id)
    tokens = get_tokens(slack_user_id)
    !tokens.nil? && !tokens[:access_token].nil?
  end

  # トークンをメモリキャッシュから削除（ログアウト）
  def delete_tokens(slack_user_id)
    @token_cache.delete(slack_user_id)
  end

  private

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