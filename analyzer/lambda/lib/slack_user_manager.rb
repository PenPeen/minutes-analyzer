require 'net/http'
require 'uri'
require 'json'
require 'time'

class RateLimitError < StandardError; end

class SlackUserManager
  API_BASE_URL = 'https://slack.com/api'
  RATE_LIMIT_PER_MINUTE = 50
  
  class RateLimiter
    def initialize(max_requests_per_minute = 50)
      @max_requests = max_requests_per_minute
      @requests = []
      @mutex = Mutex.new
    end
    
    def throttle
      @mutex.synchronize do
        now = Time.now
        # 1分以内のリクエストをフィルタ
        @requests = @requests.select { |t| now - t < 60 }
        
        if @requests.size >= @max_requests
          # レート制限に達した場合は待機
          sleep_time = 60 - (now - @requests.first)
          sleep(sleep_time) if sleep_time > 0
          @requests = []
        end
        
        @requests << now
      end
    end
    
    def handle_rate_limit_error(retry_after)
      sleep_time = retry_after.to_i > 0 ? retry_after.to_i : 60
      puts "Rate limited. Waiting #{sleep_time} seconds..."
      sleep(sleep_time)
    end
  end
  
  def initialize(bot_token = nil)
    @bot_token = bot_token || ENV['SLACK_BOT_TOKEN']
    raise 'Slack Bot Token is required' unless @bot_token
    
    @rate_limiter = RateLimiter.new(RATE_LIMIT_PER_MINUTE)
    @user_cache = {}
  end
  
  # メールアドレスからSlackユーザーIDを取得
  def lookup_user_by_email(email)
    return nil unless email
    
    # キャッシュチェック
    return @user_cache[email] if @user_cache.key?(email)
    
    @rate_limiter.throttle
    
    response = make_api_request('users.lookupByEmail', { email: email })
    
    if response['ok']
      user = response['user']
      @user_cache[email] = {
        id: user['id'],
        name: user['name'],
        real_name: user['real_name'],
        display_name: user['profile']['display_name'],
        email: email,
        is_bot: user['is_bot'],
        is_admin: user['is_admin']
      }
      @user_cache[email]
    else
      handle_error(response)
      nil
    end
  rescue => e
    puts "Error looking up user by email #{email}: #{e.message}"
    nil
  end
  
  # 複数のメールアドレスから一括でユーザー情報を取得
  def batch_lookup_users(emails)
    results = {}
    
    emails.each do |email|
      begin
        user_info = lookup_user_by_email(email)
        results[email] = user_info if user_info
      rescue => e
        results[email] = { error: e.message }
      end
    end
    
    results
  end
  
  # SlackユーザーIDからメンション形式を生成
  def generate_mention(user_id)
    return nil unless user_id
    "<@#{user_id}>"
  end
  
  # メールアドレスから直接メンション形式を生成
  def generate_mention_from_email(email)
    user = lookup_user_by_email(email)
    return nil unless user
    
    generate_mention(user[:id])
  end
  
  # 複数のメールアドレスからメンションリストを生成
  def generate_mentions_from_emails(emails)
    mentions = []
    
    emails.each do |email|
      mention = generate_mention_from_email(email)
      mentions << mention if mention
    end
    
    mentions
  end
  
  # ユーザー情報を取得（IDから）
  def get_user_info(user_id)
    @rate_limiter.throttle
    
    response = make_api_request('users.info', { user: user_id })
    
    if response['ok']
      user = response['user']
      {
        id: user['id'],
        name: user['name'],
        real_name: user['real_name'],
        display_name: user['profile']['display_name'],
        email: user['profile']['email'],
        is_bot: user['is_bot'],
        is_admin: user['is_admin']
      }
    else
      handle_error(response)
      nil
    end
  rescue => e
    puts "Error getting user info for #{user_id}: #{e.message}"
    nil
  end
  
  # 全ユーザーリストを取得（ページネーション対応）
  def list_all_users
    users = []
    cursor = nil
    
    loop do
      @rate_limiter.throttle
      
      params = { limit: 200 }
      params[:cursor] = cursor if cursor
      
      response = make_api_request('users.list', params)
      
      if response['ok']
        users.concat(response['members'])
        cursor = response['response_metadata']&.dig('next_cursor')
        break if cursor.nil? || cursor.empty?
      else
        handle_error(response)
        break
      end
    end
    
    users
  end
  
  # キャッシュをクリア
  def clear_cache
    @user_cache.clear
  end
  
  private
  
  def make_api_request(method, params = {})
    uri = URI("#{API_BASE_URL}/#{method}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@bot_token}"
    request['Content-Type'] = 'application/json'
    request.body = params.to_json
    
    max_retries = 3
    retry_count = 0
    
    begin
      response = http.request(request)
      result = JSON.parse(response.body)
      
      # Rate limitエラーの処理
      if response.code == '429' || result['error'] == 'rate_limited'
        retry_after = response['Retry-After'] || result['retry_after'] || 60
        raise RateLimitError.new(retry_after)
      end
      
      result
    rescue RateLimitError => e
      retry_count += 1
      if retry_count < max_retries
        @rate_limiter.handle_rate_limit_error(e.message.to_i)
        retry
      else
        return { 'ok' => false, 'error' => 'rate_limited' }
      end
    rescue => e
      retry_count += 1
      if retry_count < max_retries
        sleep(2 ** retry_count)
        retry
      else
        raise e
      end
    end
  end
  
  def handle_error(response)
    error = response['error']
    
    case error
    when 'users_not_found'
      puts "User not found in Slack workspace"
    when 'invalid_auth'
      raise "Invalid Slack authentication token"
    when 'account_inactive'
      puts "Slack account is inactive"
    when 'not_authed'
      raise "No authentication token provided"
    when 'invalid_email'
      puts "Invalid email address format"
    else
      puts "Slack API error: #{error}"
    end
  end
end