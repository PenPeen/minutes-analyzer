require 'json'
require 'time'
require 'logger'

class StructuredLogger
  LEVELS = {
    debug: Logger::DEBUG,
    info: Logger::INFO,
    warn: Logger::WARN,
    error: Logger::ERROR,
    fatal: Logger::FATAL
  }.freeze
  
  def initialize(output = STDOUT, level = nil)
    @logger = Logger.new(output)
    @logger.level = parse_level(level || ENV['LOG_LEVEL'] || 'INFO')
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{msg}\n"
    end
    
    @request_id = nil
    @context = {}
  end
  
  # リクエストIDを設定（Lambdaの場合はコンテキストから取得）
  def set_request_id(request_id)
    @request_id = request_id
  end
  
  # コンテキスト情報を設定
  def set_context(context)
    @context = context
  end
  
  # コンテキスト情報を追加
  def add_context(key, value)
    @context[key] = value
  end
  
  # コンテキストをクリア
  def clear_context
    @context = {}
    @request_id = nil
  end
  
  # ログレベルごとのメソッド
  [:debug, :info, :warn, :error, :fatal].each do |level|
    define_method(level) do |message, data = {}|
      log(level, message, data)
    end
  end
  
  # 構造化ログを出力
  def log(level, message, data = {})
    log_entry = build_log_entry(level, message, data)
    
    case level
    when :debug
      @logger.debug(log_entry.to_json)
    when :info
      @logger.info(log_entry.to_json)
    when :warn
      @logger.warn(log_entry.to_json)
    when :error
      @logger.error(log_entry.to_json)
    when :fatal
      @logger.fatal(log_entry.to_json)
    end
  end
  
  # API呼び出しのログ
  def log_api_call(api_name, method, endpoint, duration_ms = nil, status = nil, error = nil)
    data = {
      api_name: api_name,
      method: method,
      endpoint: endpoint,
      duration_ms: duration_ms,
      status: status
    }
    
    if error
      data[:error] = {
        message: error.message,
        class: error.class.name,
        backtrace: error.backtrace&.first(5)
      }
      error("API call failed: #{api_name}", data)
    else
      info("API call completed: #{api_name}", data)
    end
  end
  
  # 処理時間を計測してログ出力
  def measure(operation_name, level = :info)
    start_time = Time.now
    result = nil
    error = nil
    
    begin
      result = yield
    rescue => e
      error = e
    ensure
      duration_ms = ((Time.now - start_time) * 1000).round
      
      data = {
        operation: operation_name,
        duration_ms: duration_ms,
        success: error.nil?
      }
      
      if error
        data[:error] = {
          message: error.message,
          class: error.class.name
        }
        self.error("Operation failed: #{operation_name}", data)
        raise error
      else
        log(level, "Operation completed: #{operation_name}", data)
      end
    end
    
    result
  end
  
  # エラーログ（例外オブジェクト付き）
  def log_exception(exception, message = nil, data = {})
    message ||= "Exception occurred: #{exception.class.name}"
    
    error_data = data.merge({
      error: {
        message: exception.message,
        class: exception.class.name,
        backtrace: exception.backtrace&.first(10)
      }
    })
    
    error(message, error_data)
  end
  
  # Lambda関数のログ
  def log_lambda_start(event, context)
    info("Lambda function started", {
      function_name: context.function_name,
      function_version: context.function_version,
      request_id: context.aws_request_id,
      memory_limit: context.memory_limit_in_mb,
      event_type: event['source'] || 'unknown'
    })
    
    set_request_id(context.aws_request_id)
  end
  
  def log_lambda_end(context, result = nil, error = nil)
    data = {
      function_name: context.function_name,
      request_id: context.aws_request_id,
      remaining_time_ms: context.get_remaining_time_in_millis
    }
    
    if error
      data[:error] = {
        message: error.message,
        class: error.class.name
      }
      self.error("Lambda function failed", data)
    else
      data[:result_size] = result.to_json.bytesize if result
      info("Lambda function completed", data)
    end
  end
  
  # 参加者マッピングのログ
  def log_participant_mapping(email, slack_user, notion_user)
    data = {
      email: email,
      slack_mapped: !slack_user.nil?,
      notion_mapped: !notion_user.nil?
    }
    
    data[:slack_user_id] = slack_user[:id] if slack_user
    data[:notion_user_id] = notion_user[:id] if notion_user
    
    debug("Participant mapping", data)
  end
  
  # キャッシュヒット/ミスのログ
  def log_cache(cache_key, hit)
    debug("Cache #{hit ? 'hit' : 'miss'}", {
      cache_key: cache_key,
      cache_hit: hit
    })
  end
  
  # レート制限のログ
  def log_rate_limit(api_name, retry_after)
    warn("Rate limited", {
      api_name: api_name,
      retry_after_seconds: retry_after
    })
  end
  
  private
  
  def build_log_entry(level, message, data)
    entry = {
      timestamp: Time.now.iso8601,
      level: level.to_s.upcase,
      message: message
    }
    
    entry[:request_id] = @request_id if @request_id
    entry[:context] = @context unless @context.empty?
    entry[:data] = data unless data.empty?
    
    # 環境情報を追加
    entry[:environment] = ENV['ENVIRONMENT'] if ENV['ENVIRONMENT']
    entry[:function_name] = ENV['AWS_LAMBDA_FUNCTION_NAME'] if ENV['AWS_LAMBDA_FUNCTION_NAME']
    entry[:function_version] = ENV['AWS_LAMBDA_FUNCTION_VERSION'] if ENV['AWS_LAMBDA_FUNCTION_VERSION']
    
    entry
  end
  
  def parse_level(level_str)
    level_sym = level_str.downcase.to_sym
    LEVELS[level_sym] || Logger::INFO
  end
end