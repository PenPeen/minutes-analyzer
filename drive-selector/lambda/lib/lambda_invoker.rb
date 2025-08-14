# frozen_string_literal: true

require 'aws-sdk-lambda'
require 'json'

class LambdaInvoker
  def initialize
    @lambda_client = Aws::Lambda::Client.new
    @target_function_arn = ENV['PROCESS_LAMBDA_ARN'] || 'arn:aws:lambda:ap-northeast-1:339712736892:function:minutes-analyzer-production'
  end

  # 議事録分析Lambdaを呼び出す
  def invoke_analysis_lambda(payload)
    puts "Invoking analysis lambda with ARN: #{@target_function_arn}"
    puts "Payload: #{payload.inspect}"
    
    begin
      # AWS Lambda を非同期で呼び出し（Event invocation type）
      response = @lambda_client.invoke({
        function_name: @target_function_arn,
        invocation_type: 'Event', # 非同期呼び出し
        payload: JSON.generate(payload)
      })
      
      puts "Lambda invocation response status: #{response.status_code}"
      
      if response.status_code == 202
        {
          status: 'success',
          message: 'Analysis lambda invoked successfully'
        }
      else
        {
          status: 'error',
          message: "Unexpected status code: #{response.status_code}"
        }
      end
    rescue Aws::Lambda::Errors::ServiceError => e
      puts "AWS Lambda error: #{e.message}"
      raise e
    rescue => e
      puts "Unexpected error: #{e.message}"
      raise e
    end
  end
end