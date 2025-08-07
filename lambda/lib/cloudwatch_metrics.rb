require 'aws-sdk-cloudwatch'
require 'json'
require 'time'

class CloudWatchMetrics
  NAMESPACE = 'MinutesAnalyzer'
  
  def initialize(region = nil)
    @region = region || ENV['AWS_REGION'] || 'ap-northeast-1'
    @environment = ENV['ENVIRONMENT'] || 'local'
    @client = Aws::CloudWatch::Client.new(region: @region)
    @metrics_buffer = []
    @max_buffer_size = 20 # CloudWatch allows max 20 metrics per request
  end
  
  # メトリクスを送信（即座に送信）
  def put_metric(metric_name, value, unit = 'Count', dimensions = {})
    dimensions = default_dimensions.merge(dimensions)
    
    metric_data = {
      metric_name: metric_name,
      value: value,
      unit: unit,
      timestamp: Time.now,
      dimensions: dimensions.map { |k, v| { name: k.to_s, value: v.to_s } }
    }
    
    @client.put_metric_data({
      namespace: NAMESPACE,
      metric_data: [metric_data]
    })
    
    log_metric(metric_name, value, unit, dimensions)
  rescue => e
    puts "Error sending metric #{metric_name}: #{e.message}"
  end
  
  # メトリクスをバッファに追加（バッチ送信用）
  def buffer_metric(metric_name, value, unit = 'Count', dimensions = {})
    dimensions = default_dimensions.merge(dimensions)
    
    metric_data = {
      metric_name: metric_name,
      value: value,
      unit: unit,
      timestamp: Time.now,
      dimensions: dimensions.map { |k, v| { name: k.to_s, value: v.to_s } }
    }
    
    @metrics_buffer << metric_data
    
    # バッファが満杯になったら自動送信
    flush_metrics if @metrics_buffer.size >= @max_buffer_size
  end
  
  # バッファのメトリクスを送信
  def flush_metrics
    return if @metrics_buffer.empty?
    
    @client.put_metric_data({
      namespace: NAMESPACE,
      metric_data: @metrics_buffer
    })
    
    @metrics_buffer.each do |metric|
      log_metric(
        metric[:metric_name],
        metric[:value],
        metric[:unit],
        metric[:dimensions].map { |d| [d[:name], d[:value]] }.to_h
      )
    end
    
    @metrics_buffer.clear
  rescue => e
    puts "Error flushing metrics: #{e.message}"
    @metrics_buffer.clear
  end
  
  # 処理時間を計測してメトリクスとして送信
  def measure_duration(metric_name, dimensions = {})
    start_time = Time.now
    result = yield
    duration_ms = ((Time.now - start_time) * 1000).round
    
    put_metric(metric_name, duration_ms, 'Milliseconds', dimensions)
    
    result
  end
  
  # カウンターメトリクス
  def increment_counter(metric_name, dimensions = {})
    put_metric(metric_name, 1, 'Count', dimensions)
  end
  
  # エラーメトリクス
  def record_error(error_type, dimensions = {})
    dimensions[:error_type] = error_type
    increment_counter('Errors', dimensions)
  end
  
  # 成功率メトリクス
  def record_success_rate(success_count, total_count, dimensions = {})
    return if total_count == 0
    
    success_rate = (success_count.to_f / total_count * 100).round(2)
    put_metric('SuccessRate', success_rate, 'Percent', dimensions)
  end
  
  # API呼び出しメトリクス
  def record_api_call(api_name, success, duration_ms = nil, dimensions = {})
    dimensions[:api_name] = api_name
    dimensions[:status] = success ? 'success' : 'failure'
    
    increment_counter('APICallCount', dimensions)
    
    if duration_ms
      put_metric('APICallDuration', duration_ms, 'Milliseconds', dimensions)
    end
  end
  
  # 参加者マッピングメトリクス
  def record_participant_mapping(total_participants, mapped_slack, mapped_notion, dimensions = {})
    buffer_metric('TotalParticipants', total_participants, 'Count', dimensions)
    buffer_metric('MappedSlackUsers', mapped_slack, 'Count', dimensions)
    buffer_metric('MappedNotionUsers', mapped_notion, 'Count', dimensions)
    
    if total_participants > 0
      slack_rate = (mapped_slack.to_f / total_participants * 100).round(2)
      notion_rate = (mapped_notion.to_f / total_participants * 100).round(2)
      
      buffer_metric('SlackMappingRate', slack_rate, 'Percent', dimensions)
      buffer_metric('NotionMappingRate', notion_rate, 'Percent', dimensions)
    end
    
    flush_metrics
  end
  
  # Lambda実行メトリクス
  def record_lambda_execution(duration_ms, memory_used_mb, dimensions = {})
    buffer_metric('LambdaDuration', duration_ms, 'Milliseconds', dimensions)
    buffer_metric('LambdaMemoryUsed', memory_used_mb, 'Megabytes', dimensions)
    flush_metrics
  end
  
  # カスタムメトリクスのバッチ送信
  def put_custom_metrics(metrics)
    metric_data = metrics.map do |metric|
      {
        metric_name: metric[:name],
        value: metric[:value],
        unit: metric[:unit] || 'None',
        timestamp: metric[:timestamp] || Time.now,
        dimensions: (default_dimensions.merge(metric[:dimensions] || {}))
          .map { |k, v| { name: k.to_s, value: v.to_s } }
      }
    end
    
    # 20個ずつのバッチに分割して送信
    metric_data.each_slice(@max_buffer_size) do |batch|
      @client.put_metric_data({
        namespace: NAMESPACE,
        metric_data: batch
      })
    end
  rescue => e
    puts "Error sending custom metrics: #{e.message}"
  end
  
  private
  
  def default_dimensions
    {
      Environment: @environment,
      Region: @region
    }
  end
  
  def log_metric(name, value, unit, dimensions)
    log_entry = {
      timestamp: Time.now.iso8601,
      metric_name: name,
      value: value,
      unit: unit,
      dimensions: dimensions,
      namespace: NAMESPACE
    }
    
    puts "[METRIC] #{log_entry.to_json}"
  end
end