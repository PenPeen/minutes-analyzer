require 'net/http'
require 'uri'
require 'json'
require_relative 'constants'

class SlackApiClient
  include Constants::Api
  
  def initialize(bot_token, logger)
    @bot_token = bot_token
    @logger = logger
  end
  
  def post_message(channel, message_payload)
    endpoint = "#{SLACK_BASE_URL}/chat.postMessage"
    
    payload = {
      channel: channel,
      **message_payload
    }
    
    make_request(endpoint, payload)
  end
  
  def post_thread_reply(channel, thread_ts, message_payload)
    endpoint = "#{SLACK_BASE_URL}/chat.postMessage"
    
    payload = {
      channel: channel,
      thread_ts: thread_ts,
      **message_payload
    }
    
    make_request(endpoint, payload)
  end
  
  def update_message(channel, ts, message_payload)
    endpoint = "#{SLACK_BASE_URL}/chat.update"
    
    payload = {
      channel: channel,
      ts: ts,
      **message_payload
    }
    
    make_request(endpoint, payload)
  end
  
  private
  
  def make_request(endpoint, payload)
    uri = URI(endpoint)
    retries = 0
    
    begin
      http = create_http_client(uri)
      request = create_request(uri, payload)
      
      response = http.request(request)
      parse_response(response)
      
    rescue Net::ReadTimeout, Net::OpenTimeout => e
      retries += 1
      if retries <= MAX_RETRIES
        @logger.warn("Request timeout (attempt #{retries}/#{MAX_RETRIES}), retrying...")
        sleep(RETRY_DELAY * retries)
        retry
      else
        handle_error("Request timeout after #{MAX_RETRIES} attempts", e)
      end
    rescue => e
      handle_error("Request failed", e)
    end
  end
  
  def create_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = HTTP_READ_TIMEOUT
    http.open_timeout = HTTP_OPEN_TIMEOUT
    http
  end
  
  def create_request(uri, payload)
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@bot_token}"
    request['Content-Type'] = 'application/json; charset=utf-8'
    request.body = JSON.generate(payload)
    request
  end
  
  def parse_response(response)
    case response.code
    when '200'
      body = JSON.parse(response.body)
      
      if body['ok']
        {
          success: true,
          data: body
        }
      else
        handle_api_error(body)
      end
    when '429'
      handle_rate_limit_error(response)
    else
      handle_http_error(response)
    end
  end
  
  def handle_api_error(body)
    error = body['error'] || 'Unknown error'
    @logger.error("Slack API error: #{error}")
    
    # 詳細なエラー情報をログに記録
    if body['response_metadata']
      @logger.error("Error details: #{body['response_metadata']}")
    end
    
    { success: false, error: error }
  end
  
  def handle_rate_limit_error(response)
    retry_after = response['Retry-After'] || '60'
    @logger.warn("Slack API rate limited. Retry after #{retry_after} seconds")
    { success: false, error: "Rate limited. Retry after #{retry_after}s" }
  end
  
  def handle_http_error(response)
    @logger.error("Slack API HTTP error (#{response.code}): #{response.body}")
    { success: false, error: "HTTP error: #{response.code}" }
  end
  
  def handle_error(message, exception)
    @logger.error("#{message}: #{exception.message}")
    @logger.error(exception.backtrace.first(5).join("\n")) if exception.backtrace
    { success: false, error: exception.message }
  end
end