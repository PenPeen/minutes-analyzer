# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'aws-sdk-secretsmanager'

class SlackApiClient
  SLACK_API_BASE = 'https://slack.com/api'

  def initialize
    @bot_token = fetch_bot_token
  end

  # モーダルを開く
  def open_modal(trigger_id, view)
    api_call('views.open', {
      trigger_id: trigger_id,
      view: view
    })
  end

  # モーダルを更新
  def update_modal(view_id, view, hash = nil)
    params = {
      view_id: view_id,
      view: view
    }
    params[:hash] = hash if hash
    
    api_call('views.update', params)
  end

  # モーダルをプッシュ（スタック）
  def push_modal(trigger_id, view)
    api_call('views.push', {
      trigger_id: trigger_id,
      view: view
    })
  end

  # メッセージを投稿
  def post_message(channel, text, blocks = nil)
    params = {
      channel: channel,
      text: text
    }
    params[:blocks] = blocks if blocks
    
    api_call('chat.postMessage', params)
  end

  # エフェメラルメッセージを投稿
  def post_ephemeral(channel, user, text, blocks = nil)
    params = {
      channel: channel,
      user: user,
      text: text
    }
    params[:blocks] = blocks if blocks
    
    api_call('chat.postEphemeral', params)
  end

  # ユーザー情報を取得
  def get_user_info(user_id)
    api_call('users.info', { user: user_id })
  end

  # ユーザーのメールアドレスを取得
  def get_user_email(user_id)
    response = get_user_info(user_id)
    
    if response['ok']
      response['user']['profile']['email']
    else
      nil
    end
  end

  private

  # Slack Bot Tokenを取得
  def fetch_bot_token
    # 環境変数から取得を試みる
    return ENV['SLACK_BOT_TOKEN'] if ENV['SLACK_BOT_TOKEN']
    
    # Secrets Managerから取得
    secrets_client = Aws::SecretsManager::Client.new
    secret_id = ENV['SECRETS_MANAGER_SECRET_ID'] || 'drive-selector-secrets'
    
    begin
      response = secrets_client.get_secret_value(secret_id: secret_id)
      secrets = JSON.parse(response.secret_string)
      secrets['SLACK_BOT_TOKEN']
    rescue => e
      puts "Failed to fetch bot token: #{e.message}"
      raise "Bot token not available"
    end
  end

  # Slack APIを呼び出す
  def api_call(method, params = {})
    uri = URI("#{SLACK_API_BASE}/#{method}")
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@bot_token}"
    request['Content-Type'] = 'application/json; charset=utf-8'
    request.body = params.to_json
    
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.read_timeout = 30
      http.open_timeout = 10
      http.request(request)
    end
    
    result = JSON.parse(response.body)
    
    unless result['ok']
      puts "Slack API error: #{result['error']}"
      puts "Response: #{result.inspect}"
    end
    
    result
  rescue => e
    puts "API call failed: #{e.message}"
    puts e.backtrace
    { 'ok' => false, 'error' => e.message }
  end
end