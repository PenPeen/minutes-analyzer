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
  
  def initialize
    @client_id = fetch_secret('GOOGLE_CLIENT_ID')
    @client_secret = fetch_secret('GOOGLE_CLIENT_SECRET')
    @redirect_uri = ENV['GOOGLE_REDIRECT_URI'] || 'http://localhost:3000/oauth/callback'
    # Session-based authentication - tokens stored in-memory only
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
    
    response = Net::HTTP.post_form(uri, params)
    
    if response.code == '200'
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
    
    response = Net::HTTP.post_form(uri, params)
    
    if response.code == '200'
      JSON.parse(response.body)
    else
      raise "Token refresh failed: #{response.code} - #{response.body}"
    end
  end

  # ユーザーのトークンを保存（セッション基盤、メモリ内のみ）
  def save_tokens(slack_user_id, tokens)
    @token_cache[slack_user_id] = {
      access_token: tokens['access_token'],
      refresh_token: tokens['refresh_token'],
      expires_at: Time.now.to_i + (tokens['expires_in'] || 3600),
      created_at: Time.now.to_i
    }
  end

  # ユーザーのトークンを取得（メモリキャッシュから）
  def get_tokens(slack_user_id)
    token_data = @token_cache[slack_user_id]
    return nil unless token_data
    
    # トークンの有効期限を確認
    if token_data[:expires_at] && token_data[:expires_at] < Time.now.to_i
      # アクセストークンの有効期限が切れている場合、リフレッシュ
      if token_data[:refresh_token]
        begin
          new_tokens = refresh_access_token(token_data[:refresh_token])
          save_tokens(slack_user_id, new_tokens)
          return get_tokens(slack_user_id) # 更新後のトークンを再取得
        rescue => e
          puts "Token refresh failed: #{e.message}"
          @token_cache.delete(slack_user_id) # 失敗したトークンを削除
          return nil
        end
      else
        @token_cache.delete(slack_user_id) # 期限切れトークンを削除
        return nil # リフレッシュトークンがない場合は再認証が必要
      end
    end
    
    token_data
  end

  # ユーザーが認証済みかチェック
  def authenticated?(slack_user_id)
    tokens = get_tokens(slack_user_id)
    !tokens.nil? && !tokens[:access_token].nil?
  end

  # トークンを削除（ログアウト）
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

  # 暗号化機能は削除 - セッション基盤認証ではトークンをメモリ内にプレーンテキストで保存
end