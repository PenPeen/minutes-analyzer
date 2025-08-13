require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
  minimum_coverage 95
  track_files 'lib/**/*.rb'
  
  add_group 'Core', 'lib/lambda_handler.rb'
  add_group 'Clients', ['lib/*_client.rb', 'lib/secrets_manager.rb']
  add_group 'Services', ['lib/*_service.rb', 'lib/*_processor.rb']
  add_group 'Builders', ['lib/*_builder.rb', 'lib/response_builder.rb']
  add_group 'Configuration', ['lib/constants.rb', 'lib/environment_config.rb']
  add_group 'Validation', ['lib/request_validator.rb']
end if ENV['COVERAGE']

require 'rspec'
require 'webmock/rspec'
require 'json'
require 'logger'

# Lambdaディレクトリをロードパスに追加
$LOAD_PATH.unshift(File.expand_path('../lambda', __dir__))

# テスト環境でのWebMock設定
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # テスト前後の処理
  config.before(:each) do
    # 環境変数のクリア
    stub_const('ENV', ENV.to_hash.merge({
      'APP_SECRETS_NAME' => 'test-secrets',
      'AWS_REGION' => 'ap-northeast-1',
      'LOG_LEVEL' => 'ERROR'
    }))
  end
  
  # テスト後のクリーンアップ
  config.after(:each) do
    WebMock.reset!
  end
end

# テストヘルパーメソッド
module TestHelpers
  # 標準的なロガーモックを生成
  def create_logger_mock
    logger = double('logger')
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:level).and_return(Logger::INFO)
    allow(logger).to receive(:level=)
    logger
  end

  # Gemini分析結果のサンプルデータ
  def sample_analysis_result
    {
      'meeting_summary' => {
        'title' => 'テスト会議',
        'date' => '2025-01-15',
        'duration_minutes' => 30,
        'participants' => ['田中太郎', '佐藤花子']
      },
      'decisions' => [
        { 'content' => 'テスト決定事項', 'category' => 'other' }
      ],
      'actions' => [
        {
          'task' => 'テストタスク',
          'assignee' => '田中太郎',
          'priority' => 'high',
          'deadline' => '来週',
          'deadline_formatted' => '2025/01/22'
        }
      ],
      'health_assessment' => {
        'overall_score' => 85,
        'contradictions' => [],
        'unresolved_issues' => []
      }
    }
  end

  # 統合結果のサンプルデータ
  def sample_integration_results(slack_success: true, notion_success: true)
    {
      slack: slack_success ? { success: true, response_code: '200' } : nil,
      notion: notion_success ? { success: true, page_id: 'test-page' } : nil
    }
  end

  # ユーザーマッピング結果のサンプルデータ
  def sample_user_mappings
    {
      status: 'completed',
      participants: ['tanaka@example.com', 'sato@example.com'],
      user_mappings: {
        slack: {
          'tanaka@example.com' => { id: 'U12345', name: '田中太郎' },
          'sato@example.com' => { id: 'U67890', name: '佐藤花子' }
        },
        notion: {
          'tanaka@example.com' => { id: 'notion-user-1' },
          'sato@example.com' => { id: 'notion-user-2' }
        }
      }
    }
  end

  # API Gatewayイベントの生成
  def create_api_gateway_event(body:, method: 'POST', path: '/analyze')
    {
      'httpMethod' => method,
      'path' => path,
      'headers' => {
        'Content-Type' => 'application/json',
        'User-Agent' => 'test-client'
      },
      'body' => body.is_a?(String) ? body : JSON.generate(body),
      'isBase64Encoded' => false,
      'queryStringParameters' => {},
      'pathParameters' => nil
    }
  end

  # AWS Lambda contextの生成
  def create_lambda_context(request_id: 'test-request-id')
    double('context', aws_request_id: request_id)
  end

  # Secretsのサンプルデータ
  def sample_secrets(include_slack: false, include_notion: false)
    secrets = {
      'GEMINI_API_KEY' => 'test-gemini-key',
      'GOOGLE_SERVICE_ACCOUNT_JSON' => '{"type":"service_account","project_id":"test"}'
    }
    
    if include_slack
      secrets['SLACK_BOT_TOKEN'] = 'xoxb-test-token'
      secrets['SLACK_CHANNEL_ID'] = 'C1234567890'
    end
    
    if include_notion
      secrets['NOTION_API_KEY'] = 'secret_test_key'
      secrets['NOTION_DATABASE_ID'] = 'database-123'
    end
    
    secrets
  end

  # WebMockスタブの設定
  def stub_http_request(method, url, response_body: {}, status: 200, headers: {})
    WebMock.stub_request(method, url)
      .to_return(
        status: status,
        body: response_body.is_a?(String) ? response_body : JSON.generate(response_body),
        headers: { 'Content-Type' => 'application/json' }.merge(headers)
      )
  end

  # エラー検証ヘルパー
  def expect_error_response(result, status_code, error_message_pattern = nil)
    expect(result[:statusCode]).to eq(status_code)
    
    if error_message_pattern
      body = JSON.parse(result[:body])
      expect(body['error']).to match(error_message_pattern)
    end
  end

  # 成功検証ヘルパー
  def expect_success_response(result, expected_analysis = nil)
    expect(result[:statusCode]).to eq(200)
    
    body = JSON.parse(result[:body])
    expect(body['message']).to eq('Analysis complete.')
    
    if expected_analysis
      expect(body['analysis']).to eq(expected_analysis)
    end
  end
end

# テストヘルパーをインクルード
RSpec.configure do |config|
  config.include TestHelpers
end
