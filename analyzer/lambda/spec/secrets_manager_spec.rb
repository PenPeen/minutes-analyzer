require 'spec_helper'
require_relative '../lib/secrets_manager'

RSpec.describe SecretsManager do
  let(:logger) { double('logger') }
  let(:mock_client) { double('Aws::SecretsManager::Client') }
  let(:secrets_manager) { SecretsManager.new(logger, client: mock_client) }
  let(:secret_name) { 'test-secret' }
  let(:secret_value) { { 'api_key' => 'test-key', 'database_url' => 'test-url' } }
  let(:secret_string) { secret_value.to_json }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    ENV['APP_SECRETS_NAME'] = secret_name
  end

  after do
    ENV.delete('APP_SECRETS_NAME')
  end

  describe '#get_secrets' do
    context 'when secrets are successfully retrieved' do
      let(:mock_response) { double('response', secret_string: secret_string) }

      before do
        allow(mock_client).to receive(:get_secret_value)
          .with(secret_id: secret_name)
          .and_return(mock_response)
      end

      it 'returns parsed secrets' do
        result = secrets_manager.get_secrets
        expect(result).to eq(secret_value)
      end

      it 'logs success message' do
        expect(logger).to receive(:info).with("Successfully retrieved secrets from: #{secret_name}")
        secrets_manager.get_secrets
      end

      it 'caches secrets on subsequent calls' do
        secrets_manager.get_secrets
        secrets_manager.get_secrets

        expect(mock_client).to have_received(:get_secret_value).once
      end
    end

    context 'when APP_SECRETS_NAME is not set' do
      before do
        ENV.delete('APP_SECRETS_NAME')
      end

      it 'logs error and raises exception' do
        expect(logger).to receive(:error).with('APP_SECRETS_NAME environment variable is not set')
        expect { secrets_manager.get_secrets }.to raise_error('APP_SECRETS_NAME not configured')
      end
    end

    context 'when secret is not found' do
      before do
        allow(mock_client).to receive(:get_secret_value)
          .and_raise(Aws::SecretsManager::Errors::ResourceNotFoundException.new(nil, 'Secret not found'))
      end

      it 'logs error and raises exception' do
        expect(logger).to receive(:error).with("Secret '#{secret_name}' not found")
        expect { secrets_manager.get_secrets }.to raise_error("Secret not found: #{secret_name}")
      end
    end

    context 'when AWS service error occurs' do
      let(:service_error) { Aws::SecretsManager::Errors::ServiceError.new(nil, 'Service unavailable') }

      before do
        allow(mock_client).to receive(:get_secret_value)
          .and_raise(service_error)
      end

      it 'logs error and raises exception' do
        expect(logger).to receive(:error).with("AWS Secrets Manager error: #{service_error.message}")
        expect { secrets_manager.get_secrets }.to raise_error("Failed to retrieve secrets: #{service_error.message}")
      end
    end

    context 'when JSON parsing fails' do
      let(:invalid_json) { 'invalid-json' }
      let(:mock_response) { double('response', secret_string: invalid_json) }

      before do
        allow(mock_client).to receive(:get_secret_value)
          .with(secret_id: secret_name)
          .and_return(mock_response)
      end

      it 'logs error and raises exception' do
        expect(logger).to receive(:error).with(/Failed to parse secret JSON:/)
        expect { secrets_manager.get_secrets }.to raise_error(/Invalid secret format:/)
      end
    end

    context 'when unexpected error occurs' do
      let(:unexpected_error) { StandardError.new('Unexpected error') }

      before do
        allow(mock_client).to receive(:get_secret_value)
          .and_raise(unexpected_error)
      end

      it 'logs error and raises exception' do
        expect(logger).to receive(:error).with("Unexpected error retrieving secrets: #{unexpected_error.message}")
        expect { secrets_manager.get_secrets }.to raise_error("Secret retrieval failed: #{unexpected_error.message}")
      end
    end
  end

  describe '#build_client (private method behavior)' do
    let(:secrets_manager_without_client) { SecretsManager.new(logger) }

    context 'when creating client without injected client' do
      before do
        ENV['AWS_REGION'] = 'us-west-2'
        allow(Aws::SecretsManager::Client).to receive(:new)
      end

      after do
        ENV.delete('AWS_REGION')
      end

      it 'creates client with correct options' do
        allow(Aws::SecretsManager::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:get_secret_value).and_return(
          double('response', secret_string: secret_string)
        )

        secrets_manager_without_client.get_secrets

        expect(Aws::SecretsManager::Client).to have_received(:new).with(
          region: 'us-west-2'
        )
      end
    end

    context 'when AWS_REGION is not set' do
      before do
        ENV.delete('AWS_REGION')
        allow(Aws::SecretsManager::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:get_secret_value).and_return(
          double('response', secret_string: secret_string)
        )
      end

      it 'uses default region' do
        secrets_manager_without_client.get_secrets

        expect(Aws::SecretsManager::Client).to have_received(:new).with(
          region: 'ap-northeast-1'
        )
      end
    end
  end
end
