require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
end if ENV['COVERAGE']

require 'rspec'
require 'webmock/rspec'
require 'json'

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
end
