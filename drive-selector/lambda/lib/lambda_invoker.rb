# frozen_string_literal: true

require 'aws-sdk-lambda'
require 'aws-sdk-secretsmanager'
require 'json'

class LambdaInvoker
  def initialize
    @lambda_client = Aws::Lambda::Client.new
    @target_function_arn = fetch_target_function_arn
  end

  # 議事録分析Lambdaを非同期で呼び出す
  def invoke_analysis_lambda(payload)
    # 既存Lambdaの期待するペイロード形式に変換
    lambda_payload = build_lambda_payload(payload)
    
    begin
      # Lambda関数を非同期（Event）で呼び出し
      response = @lambda_client.invoke(
        function_name: @target_function_arn,
        invocation_type: 'Event', # 非同期実行
        payload: JSON.generate(lambda_payload)
      )
      
      # ステータスコードをチェック（202が成功）
      if response.status_code == 202
        puts "Successfully invoked analysis lambda."
        {
          status: 'success',
          message: 'Analysis lambda invoked successfully'
        }
      else
        puts "Failed to invoke lambda. Status: #{response.status_code}"
        {
          status: 'error',
          message: "Failed to invoke lambda. Status: #{response.status_code}"
        }
      end
    rescue Aws::Lambda::Errors::ServiceError => e
      puts "Lambda invocation error: #{e.message}"
      {
        status: 'error',
        message: "Lambda invocation failed: #{e.message}"
      }
    rescue => e
      puts "Unexpected error during lambda invocation: #{e.message}"
      puts e.backtrace.join("\n") if e.backtrace
      {
        status: 'error',
        message: "Unexpected error: #{e.message}"
      }
    end
  end

  private

  # 既存Lambdaが期待するペイロード形式を構築
  def build_lambda_payload(slack_payload)
    # Slackからのペイロードを既存Lambda形式に変換
    # 既存Lambdaは以下の形式を期待:
    # {
    #   "body": "{\"file_id\": \"...\", \"file_name\": \"...\"}",
    #   "headers": {"Content-Type": "application/json"}
    # }
    
    body_content = {
      file_id: slack_payload[:file_id],
      file_name: slack_payload[:file_name]
    }
    
    # オプション情報を追加（将来の拡張性のため）
    if slack_payload[:options]
      body_content[:options] = slack_payload[:options]
    end
    
    # ユーザー情報を追加（監査ログ用）
    if slack_payload[:user_id]
      body_content[:slack_user_id] = slack_payload[:user_id]
    end
    
    if slack_payload[:user_email]
      body_content[:slack_user_email] = slack_payload[:user_email]
    end
    
    {
      body: JSON.generate(body_content),
      headers: {
        'Content-Type' => 'application/json'
      }
    }
  end

  # ターゲットLambda関数のARNを取得
  def fetch_target_function_arn
    # 環境変数から取得
    arn = ENV['PROCESS_LAMBDA_ARN']
    
    # 環境変数にない場合はSecrets Managerから取得
    unless arn
      arn = fetch_from_secrets('PROCESS_LAMBDA_ARN')
    end
    
    # それでもない場合はデフォルト値を使用（開発環境）
    unless arn
      environment = ENV['ENVIRONMENT'] || 'local'
      # 環境に応じたデフォルトARNパターン
      case environment
      when 'production'
        arn = 'arn:aws:lambda:ap-northeast-1:YOUR_ACCOUNT:function:minutes-analyzer-production'
      when 'development'
        arn = 'arn:aws:lambda:ap-northeast-1:YOUR_ACCOUNT:function:minutes-analyzer-development'
      else
        # LocalStack環境の場合
        arn = 'arn:aws:lambda:ap-northeast-1:000000000000:function:minutes-analyzer-local'
      end
    end
    
    puts "Using target Lambda ARN: #{arn}"
    arn
  end

  # Secrets Managerから値を取得
  def fetch_from_secrets(key)
    secrets_client = Aws::SecretsManager::Client.new
    secret_id = ENV['SECRETS_MANAGER_SECRET_ID'] || 'drive-selector-secrets'
    
    begin
      response = secrets_client.get_secret_value(secret_id: secret_id)
      secrets = JSON.parse(response.secret_string)
      secrets[key]
    rescue => e
      puts "Failed to fetch secret #{key}: #{e.message}"
      nil
    end
  end
end