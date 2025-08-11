# frozen_string_literal: true

require 'json'
require 'base64'
require_relative 'lib/slack_request_validator'
require_relative 'lib/slack_command_handler'
require_relative 'lib/slack_interaction_handler'
require_relative 'lib/oauth_callback_handler'

# Lambda関数のメインエントリーポイント
def lambda_handler(event:, context:)
  puts "Event: #{JSON.pretty_generate(event)}"
  
  # パスに基づいてルーティング
  path = event['path'] || event['rawPath'] || '/'
  http_method = event['httpMethod'] || event['requestContext']['http']['method'] || 'POST'
  
  begin
    case path
    when '/slack/commands'
      handle_slack_command(event)
    when '/slack/interactions'
      handle_slack_interaction(event)
    when '/oauth/callback'
      handle_oauth_callback(event)
    when '/health'
      health_check
    else
      not_found_response
    end
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace.join("\n")
    error_response(e.message)
  end
end

# Slackコマンドを処理
def handle_slack_command(event)
  # Slack署名を検証
  validator = SlackRequestValidator.new
  body = get_body(event)
  headers = get_headers(event)
  
  unless validator.valid_request?(body, headers)
    return unauthorized_response
  end
  
  # コマンドを処理
  handler = SlackCommandHandler.new
  handler.handle(parse_slack_body(body))
end

# Slackインタラクションを処理
def handle_slack_interaction(event)
  # Slack署名を検証
  validator = SlackRequestValidator.new
  body = get_body(event)
  headers = get_headers(event)
  
  unless validator.valid_request?(body, headers)
    return unauthorized_response
  end
  
  # インタラクションを処理
  handler = SlackInteractionHandler.new
  parsed_body = parse_slack_body(body)
  payload = JSON.parse(parsed_body['payload'] || '{}')
  handler.handle(payload)
end

# OAuthコールバックを処理
def handle_oauth_callback(event)
  handler = OAuthCallbackHandler.new
  handler.handle_callback(event)
end

# ヘルスチェック
def health_check
  {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.generate({
      status: 'healthy',
      timestamp: Time.now.iso8601
    })
  }
end

# リクエストボディを取得
def get_body(event)
  if event['isBase64Encoded']
    Base64.decode64(event['body'])
  else
    event['body'] || ''
  end
end

# ヘッダーを取得（大文字小文字を正規化）
def get_headers(event)
  headers = event['headers'] || {}
  normalized = {}
  headers.each do |key, value|
    normalized[key.downcase] = value
  end
  normalized
end

# Slackのフォームエンコードされたボディをパース
def parse_slack_body(body)
  params = {}
  body.split('&').each do |pair|
    key, value = pair.split('=', 2)
    params[key] = URI.decode_www_form_component(value || '')
  end
  params
end

# 404レスポンス
def not_found_response
  {
    statusCode: 404,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.generate({
      error: 'Not Found'
    })
  }
end

# 401レスポンス
def unauthorized_response
  {
    statusCode: 401,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.generate({
      error: 'Unauthorized'
    })
  }
end

# エラーレスポンス
def error_response(message)
  {
    statusCode: 500,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.generate({
      error: 'Internal Server Error',
      message: message
    })
  }
end