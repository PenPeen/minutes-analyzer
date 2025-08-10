require 'net/http'
require 'uri'
require 'json'
require_relative 'constants'

class NotionApiClient
  include Constants::Api
  
  def initialize(api_key, logger)
    @api_key = api_key
    @logger = logger
  end
  
  def create_page(request_body)
    uri = URI("#{NOTION_BASE_URL}/pages")
    make_request(uri, request_body)
  end
  
  def update_page(page_id, properties)
    uri = URI("#{NOTION_BASE_URL}/pages/#{page_id}")
    make_request(uri, { properties: properties }, 'PATCH')
  end
  
  def get_database(database_id)
    uri = URI("#{NOTION_BASE_URL}/databases/#{database_id}")
    make_get_request(uri)
  end
  
  def query_database(database_id, filter = nil, sorts = nil)
    uri = URI("#{NOTION_BASE_URL}/databases/#{database_id}/query")
    request_body = {}
    request_body[:filter] = filter if filter
    request_body[:sorts] = sorts if sorts
    
    make_request(uri, request_body)
  end
  
  private
  
  def make_request(uri, body, method = 'POST')
    retries = 0
    
    begin
      http = create_http_client(uri)
      request = create_request(uri, method)
      request.body = JSON.generate(body)
      
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
  
  def make_get_request(uri)
    begin
      http = create_http_client(uri)
      request = create_request(uri, 'GET')
      
      response = http.request(request)
      parse_response(response)
      
    rescue => e
      handle_error("GET request failed", e)
    end
  end
  
  def create_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = HTTP_READ_TIMEOUT
    http.open_timeout = HTTP_OPEN_TIMEOUT
    http
  end
  
  def create_request(uri, method)
    request_class = case method
                   when 'GET' then Net::HTTP::Get
                   when 'PATCH' then Net::HTTP::Patch
                   else Net::HTTP::Post
                   end
    
    request = request_class.new(uri)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Notion-Version'] = ENV['NOTION_API_VERSION'] || NOTION_VERSION
    request['Content-Type'] = 'application/json' unless method == 'GET'
    request
  end
  
  def parse_response(response)
    case response.code
    when '200', '201'
      {
        success: true,
        data: JSON.parse(response.body)
      }
    when '400'
      handle_validation_error(response)
    when '401'
      handle_auth_error(response)
    when '404'
      handle_not_found_error(response)
    when '429'
      handle_rate_limit_error(response)
    else
      handle_general_error(response)
    end
  end
  
  def handle_validation_error(response)
    error_data = JSON.parse(response.body) rescue {}
    error_message = error_data['message'] || 'Validation error'
    
    @logger.error("Notion API validation error: #{error_message}")
    { success: false, error: error_message, code: 400 }
  end
  
  def handle_auth_error(response)
    @logger.error("Notion API authentication failed")
    { success: false, error: 'Authentication failed', code: 401 }
  end
  
  def handle_not_found_error(response)
    @logger.error("Notion resource not found")
    { success: false, error: 'Resource not found', code: 404 }
  end
  
  def handle_rate_limit_error(response)
    retry_after = response['Retry-After'] || '60'
    @logger.warn("Notion API rate limited. Retry after #{retry_after} seconds")
    { success: false, error: "Rate limited. Retry after #{retry_after}s", code: 429 }
  end
  
  def handle_general_error(response)
    error_body = JSON.parse(response.body) rescue response.body
    @logger.error("Notion API error (#{response.code}): #{error_body}")
    { success: false, error: error_body, code: response.code.to_i }
  end
  
  def handle_error(message, exception)
    @logger.error("#{message}: #{exception.message}")
    @logger.error(exception.backtrace.first(5).join("\n")) if exception.backtrace
    { success: false, error: exception.message }
  end
end