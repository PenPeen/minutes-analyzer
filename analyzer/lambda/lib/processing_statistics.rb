require 'json'
require 'time'

class ProcessingStatistics
  def initialize
    @statistics = {
      processed: 0,
      successful: 0,
      failed: 0,
      processing_time: 0
    }
  end
  
  def record_success(processing_time)
    @statistics[:processed] += 1
    @statistics[:successful] += 1
    @statistics[:processing_time] += processing_time
  end
  
  def record_failure(processing_time)
    @statistics[:processed] += 1
    @statistics[:failed] += 1
    @statistics[:processing_time] += processing_time
  end
  
  def get_statistics
    {
      total_processed: @statistics[:processed],
      successful: @statistics[:successful],
      failed: @statistics[:failed],
      success_rate: calculate_success_rate,
      average_processing_time: calculate_average_processing_time
    }
  end
  
  def send_metrics_to_cloudwatch
    metrics = {
      'ProcessedTranscripts' => @statistics[:processed],
      'SuccessfulAnalyses' => @statistics[:successful],
      'FailedAnalyses' => @statistics[:failed],
      'AverageProcessingTime' => calculate_average_processing_time
    }
    
    puts "Metrics to send: #{metrics.to_json}"
  end
  
  def reset
    @statistics = {
      processed: 0,
      successful: 0,
      failed: 0,
      processing_time: 0
    }
  end
  
  private
  
  def calculate_success_rate
    return 0 if @statistics[:processed] == 0
    (@statistics[:successful].to_f / @statistics[:processed] * 100).round(2)
  end
  
  def calculate_average_processing_time
    return 0 if @statistics[:processed] == 0
    (@statistics[:processing_time] / @statistics[:processed]).round(3)
  end
end