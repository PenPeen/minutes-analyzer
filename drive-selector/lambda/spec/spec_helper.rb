# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
end

require 'bundler/setup'
Bundler.require(:default, :test)

# プロジェクトのlibディレクトリをロードパスに追加
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # WebMock設定
  require 'webmock/rspec'
  WebMock.disable_net_connect!(allow_localhost: true)

  # 環境変数のモック設定
  config.before(:each) do
    # テスト用の環境変数を設定
    ENV['ENVIRONMENT'] = 'test'
    ENV['AWS_REGION'] = 'ap-northeast-1'
  end

  config.after(:each) do
    # 環境変数をクリア
    ENV.delete('ENVIRONMENT')
    ENV.delete('AWS_REGION')
  end
end