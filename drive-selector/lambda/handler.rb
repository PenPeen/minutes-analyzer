# frozen_string_literal: true

require 'json'
require 'base64'
require_relative 'lib/slack_request_validator'
require_relative 'lib/slack_command_handler'
require_relative 'lib/slack_interaction_handler'
require_relative 'lib/oauth_callback_handler'

# Lambda関数のメインエントリーポイント
def lambda_handler(event:, context:)
  path = event['path'] || event['rawPath'] || '/'
  http_method = event['httpMethod'] || event['requestContext']&.dig('http', 'method') || 'POST'
  
  puts "Processing request: #{http_method} #{path}"
  safe_log_event(event)
  
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
      not_found_response(path)
    end
  rescue => e
    puts "Error processing request: #{e.message}"
    puts e.backtrace.join("\n")
    error_response(e.message)
  end
end

# Slackコマンドを処理
def handle_slack_command(event)
  body = get_body(event)
  headers = get_headers(event)
  
  # リクエストボディが必要
  return bad_request_response('Request body is required for Slack commands') if body.nil? || body.empty?
  
  # Slack署名を検証
  validator = SlackRequestValidator.new
  unless validator.valid_request?(body, headers)
    return unauthorized_response('Invalid Slack signature')
  end
  
  # コマンドを処理
  handler = SlackCommandHandler.new
  handler.handle_command(parse_slack_body(body))
end

# Slackインタラクションを処理
def handle_slack_interaction(event)
  body = get_body(event)
  headers = get_headers(event)
  
  # リクエストボディが必要
  return bad_request_response('Request body is required for Slack interactions') if body.nil? || body.empty?
  
  # Slack署名を検証
  validator = SlackRequestValidator.new
  unless validator.valid_request?(body, headers)
    return unauthorized_response('Invalid Slack signature')
  end
  
  # インタラクションを処理
  handler = SlackInteractionHandler.new
  parsed_body = parse_slack_body(body)
  
  begin
    payload = JSON.parse(parsed_body['payload'] || '{}')
    handler.handle_interaction(payload)
  rescue JSON::ParserError => e
    puts "JSON parse error: #{e.message}"
    bad_request_response('Invalid JSON payload')
  end
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
    begin
      params[key] = URI.decode_www_form_component(value || '')
    rescue ArgumentError => e
      puts "Failed to decode parameter #{key}: #{e.message}"
      params[key] = value || ''
    end
  end
  params
end

# 404レスポンス
def not_found_response(path = nil)
  {
    statusCode: 404,
    headers: { 'Content-Type' => 'application/json' },
    body: JSON.generate({
      error: 'Not Found',
      path: path
    }.compact)
  }
end

# 401レスポンス
def unauthorized_response(message = 'Unauthorized')
  {
    statusCode: 401,
    headers: { 'Content-Type' => 'application/json' },
    body: JSON.generate({
      error: "Unauthorized - #{message}"
    })
  }
end

# 400レスポンス
def bad_request_response(message = 'Bad Request')
  {
    statusCode: 400,
    headers: { 'Content-Type' => 'application/json' },
    body: JSON.generate({
      error: 'Bad Request',
      message: message
    })
  }
end

# 安全なイベントログ出力（機密情報を除外）
def safe_log_event(event)
  safe_event = event.dup
  if safe_event['headers']
    safe_event['headers'] = safe_event['headers'].dup
    safe_event['headers'].delete('x-slack-signature')
    safe_event['headers'].delete('authorization') 
    safe_event['headers'].delete('x-slack-request-timestamp')
  end
  puts "Event (sanitized): #{JSON.pretty_generate(safe_event)}"
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