# frozen_string_literal: true

require 'rspec'
require 'webmock/rspec'
require 'simplecov'

# Start SimpleCov for test coverage
SimpleCov.start do
  add_filter '/spec/'
  minimum_coverage 85
  track_files 'lib/**/*.rb'
  track_files '*.rb'
end

# WebMock configuration
WebMock.disable_net_connect!(allow_localhost: true)

# Load application code
require_relative '../handler'
require_relative '../lib/slack_request_validator'
require_relative '../lib/slack_command_handler'
require_relative '../lib/slack_interaction_handler'
require_relative '../lib/google_oauth_client'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Clear environment variables before each test
  config.before(:each) do
    ENV['SLACK_SIGNING_SECRET'] = 'test_signing_secret'
    ENV['GOOGLE_CLIENT_ID'] = 'test_client_id'
    ENV['GOOGLE_CLIENT_SECRET'] = 'test_client_secret'
    ENV['GOOGLE_REDIRECT_URI'] = 'http://test.example.com/oauth/callback'
    ENV['PROCESS_LAMBDA_ARN'] = 'arn:aws:lambda:us-east-1:123456789012:function:process-lambda'
  end

  config.after(:each) do
    WebMock.reset!
  end
end

# Test helpers
def create_slack_signature(timestamp, body, secret = 'test_signing_secret')
  require 'openssl'
  basestring = "v0:#{timestamp}:#{body}"
  'v0=' + OpenSSL::HMAC.hexdigest('SHA256', secret, basestring)
end

def create_mock_lambda_event(path:, method: 'POST', body: '', headers: {})
  {
    'httpMethod' => method,
    'path' => path,
    'body' => body,
    'headers' => {
      'content-type' => 'application/x-www-form-urlencoded',
      'x-slack-request-timestamp' => Time.now.to_i.to_s,
      'x-slack-signature' => create_slack_signature(Time.now.to_i, body)
    }.merge(headers),
    'queryStringParameters' => {},
    'pathParameters' => nil
  }
end