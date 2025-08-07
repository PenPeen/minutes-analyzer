require 'net/http'
require 'uri'
require 'json'
require 'time'

class NotionUserManager
  API_BASE_URL = 'https://api.notion.com/v1'
  CACHE_TTL = 600 # 10分
  
  class UserCache
    def initialize(ttl = 600)
      @cache = {}
      @ttl = ttl
      @mutex = Mutex.new
    end
    
    def get(key)
      @mutex.synchronize do
        entry = @cache[key]
        return nil unless entry
        
        if Time.now - entry[:timestamp] > @ttl
          @cache.delete(key)
          nil
        else
          entry[:value]
        end
      end
    end
    
    def set(key, value)
      @mutex.synchronize do
        @cache[key] = {
          value: value,
          timestamp: Time.now
        }
      end
    end
    
    def clear
      @mutex.synchronize do
        @cache.clear
      end
    end
    
    def refresh_if_needed
      @mutex.synchronize do
        now = Time.now
        @cache.delete_if { |_, entry| now - entry[:timestamp] > @ttl }
      end
    end
  end
  
  def initialize(api_key = nil)
    @api_key = api_key || ENV['NOTION_API_KEY']
    raise 'Notion API Key is required' unless @api_key
    
    @user_cache = UserCache.new(CACHE_TTL)
    @all_users_cache = nil
    @all_users_cache_time = nil
  end
  
  # 全ユーザーを取得（ページネーション対応）
  def list_all_users
    # キャッシュチェック
    if @all_users_cache && @all_users_cache_time && 
       (Time.now - @all_users_cache_time) < CACHE_TTL
      return @all_users_cache
    end
    
    users = []
    start_cursor = nil
    
    loop do
      response = make_api_request('GET', '/users', {
        page_size: 100,
        start_cursor: start_cursor
      })
      
      if response['object'] == 'list'
        users.concat(response['results'])
        
        if response['has_more']
          start_cursor = response['next_cursor']
        else
          break
        end
      else
        handle_error(response)
        break
      end
    end
    
    # メールアドレスでインデックス化
    indexed_users = index_users_by_email(users)
    
    # キャッシュ更新
    @all_users_cache = indexed_users
    @all_users_cache_time = Time.now
    
    indexed_users
  end
  
  # メールアドレスからNotionユーザーIDを検索
  def find_user_by_email(email)
    return nil unless email
    
    # 個別キャッシュチェック
    cached_user = @user_cache.get(email)
    return cached_user if cached_user
    
    # 全ユーザーリストから検索
    all_users = list_all_users
    user = all_users[email.downcase]
    
    if user
      @user_cache.set(email, user)
      user
    else
      nil
    end
  end
  
  # 複数のメールアドレスから一括でユーザー情報を取得
  def batch_find_users(emails)
    results = {}
    
    emails.each do |email|
      user = find_user_by_email(email)
      results[email] = user if user
    end
    
    results
  end
  
  # タスクDBの担当者プロパティを更新
  def update_task_assignee(page_id, user_email)
    user = find_user_by_email(user_email)
    return false unless user
    
    update_page_property(page_id, 'assignee', {
      people: [{ id: user[:id] }]
    })
  end
  
  # 複数タスクの担当者を一括更新
  def batch_update_task_assignees(task_assignments)
    results = {}
    
    task_assignments.each do |page_id, email|
      begin
        success = update_task_assignee(page_id, email)
        results[page_id] = { success: success, email: email }
      rescue => e
        results[page_id] = { success: false, error: e.message }
      end
    end
    
    results
  end
  
  # ページプロパティの更新
  def update_page_property(page_id, property_name, property_value)
    response = make_api_request('PATCH', "/pages/#{page_id}", {
      properties: {
        property_name => property_value
      }
    })
    
    response['object'] == 'page'
  rescue => e
    puts "Error updating page property: #{e.message}"
    false
  end
  
  # ユーザー情報の取得（IDから）
  def get_user(user_id)
    response = make_api_request('GET', "/users/#{user_id}")
    
    if response['object'] == 'user'
      format_user_info(response)
    else
      nil
    end
  rescue => e
    puts "Error getting user: #{e.message}"
    nil
  end
  
  # キャッシュのクリア
  def clear_cache
    @user_cache.clear
    @all_users_cache = nil
    @all_users_cache_time = nil
  end
  
  # キャッシュのリフレッシュ
  def refresh_cache
    @user_cache.refresh_if_needed
    
    if @all_users_cache_time && (Time.now - @all_users_cache_time) > CACHE_TTL
      @all_users_cache = nil
      @all_users_cache_time = nil
    end
  end
  
  private
  
  def make_api_request(method, endpoint, body = nil)
    uri = URI("#{API_BASE_URL}#{endpoint}")
    
    if method == 'GET' && body
      uri.query = URI.encode_www_form(body)
      body = nil
    end
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    
    request = case method
              when 'GET'
                Net::HTTP::Get.new(uri)
              when 'POST'
                Net::HTTP::Post.new(uri)
              when 'PATCH'
                Net::HTTP::Patch.new(uri)
              else
                raise "Unsupported HTTP method: #{method}"
              end
    
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    request['Notion-Version'] = '2022-06-28'
    
    request.body = body.to_json if body
    
    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    puts "API request error: #{e.message}"
    { 'object' => 'error', 'message' => e.message }
  end
  
  def index_users_by_email(users)
    indexed = {}
    
    users.each do |user|
      user_info = format_user_info(user)
      if user_info[:email]
        indexed[user_info[:email].downcase] = user_info
      end
    end
    
    indexed
  end
  
  def format_user_info(user)
    {
      id: user['id'],
      type: user['type'],
      name: user['name'],
      email: user['person']&.dig('email'),
      avatar_url: user['avatar_url']
    }
  end
  
  def handle_error(response)
    if response['object'] == 'error'
      error_code = response['code']
      error_message = response['message']
      
      case error_code
      when 'unauthorized'
        raise "Notion API authentication failed: #{error_message}"
      when 'restricted_resource'
        puts "Access restricted to resource: #{error_message}"
      when 'object_not_found'
        puts "Object not found: #{error_message}"
      when 'rate_limited'
        puts "Rate limited by Notion API: #{error_message}"
      else
        puts "Notion API error: #{error_code} - #{error_message}"
      end
    end
  end
end