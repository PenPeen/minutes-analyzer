require 'spec_helper'
require_relative '../lib/s3_client'

RSpec.describe S3Client do
  let(:logger) { double('logger') }
  let(:environment) { 'local' }
  let(:s3_client) { S3Client.new(logger, environment) }
  let(:mock_s3) { double('Aws::S3::Client') }
  let(:mock_response) { double('response') }
  let(:mock_body) { double('body') }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(logger).to receive(:debug)
    allow(Aws::S3::Client).to receive(:new).and_return(mock_s3)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('S3_PROMPTS_BUCKET', anything).and_return('minutes-analyzer-prompts-local')
  end

  describe '#get_prompt' do
    let(:prompt_content) { "Test prompt content" }

    context 'when successful' do
      before do
        allow(mock_s3).to receive(:get_object).and_return(mock_response)
        allow(mock_response).to receive(:body).and_return(mock_body)
        allow(mock_body).to receive(:read).and_return(prompt_content)
      end

      it 'returns the prompt content' do
        result = s3_client.get_prompt
        expect(result).to eq(prompt_content)
      end

      it 'requests from correct bucket and key' do
        expect(mock_s3).to receive(:get_object).with(
          bucket: 'minutes-analyzer-prompts-local',
          key: 'prompts/meeting_analysis_prompt.txt'
        )
        s3_client.get_prompt
      end

      it 'logs success' do
        expect(logger).to receive(:info).with('Fetching prompt from S3: minutes-analyzer-prompts-local/prompts/meeting_analysis_prompt.txt')
        expect(logger).to receive(:info).with(/Successfully retrieved prompt \(\d+ bytes\)/)
        s3_client.get_prompt
      end
    end

    context 'when S3 error occurs' do
      before do
        allow(mock_s3).to receive(:get_object).and_raise(
          Aws::S3::Errors::NoSuchKey.new(nil, 'The specified key does not exist.')
        )
      end

      it 'logs error and raises exception' do
        expect(logger).to receive(:error).with(/Failed to fetch prompt from S3/)
        expect { s3_client.get_prompt }.to raise_error(/Unable to retrieve prompt from S3/)
      end
    end
  end

  describe '#get_verification_prompt' do
    let(:verification_content) { "Test verification prompt content" }

    context 'when successful' do
      before do
        allow(mock_s3).to receive(:get_object).and_return(mock_response)
        allow(mock_response).to receive(:body).and_return(mock_body)
        allow(mock_body).to receive(:read).and_return(verification_content)
      end

      it 'returns the verification prompt content' do
        result = s3_client.get_verification_prompt
        expect(result).to eq(verification_content)
      end

      it 'requests from correct bucket and key' do
        expect(mock_s3).to receive(:get_object).with(
          bucket: 'minutes-analyzer-prompts-local',
          key: 'prompts/meeting_verification_prompt.txt'
        )
        s3_client.get_verification_prompt
      end

      it 'logs success' do
        expect(logger).to receive(:info).with('Fetching verification prompt from S3: minutes-analyzer-prompts-local/prompts/meeting_verification_prompt.txt')
        expect(logger).to receive(:info).with(/Successfully retrieved verification prompt \(\d+ bytes\)/)
        s3_client.get_verification_prompt
      end
    end

    context 'when S3 error occurs' do
      before do
        allow(mock_s3).to receive(:get_object).and_raise(
          Aws::S3::Errors::NoSuchKey.new(nil, 'The specified key does not exist.')
        )
      end

      it 'logs error and raises exception' do
        expect(logger).to receive(:error).with(/Failed to fetch verification prompt from S3/)
        expect { s3_client.get_verification_prompt }.to raise_error(/Unable to retrieve verification prompt from S3/)
      end
    end
  end

  describe '#get_output_schema' do
    let(:schema_content) { '{"type": "object", "properties": {}}' }
    let(:parsed_schema) { { "type" => "object", "properties" => {} } }

    context 'when successful' do
      before do
        allow(mock_s3).to receive(:get_object).and_return(mock_response)
        allow(mock_response).to receive(:body).and_return(mock_body)
        allow(mock_body).to receive(:read).and_return(schema_content)
      end

      it 'returns parsed JSON schema' do
        result = s3_client.get_output_schema
        expect(result).to eq(parsed_schema)
      end

      it 'requests from correct bucket and key' do
        expect(mock_s3).to receive(:get_object).with(
          bucket: 'minutes-analyzer-prompts-local',
          key: 'schemas/output_schema.json'
        )
        s3_client.get_output_schema
      end

      it 'logs success' do
        expect(logger).to receive(:info).with('Fetching output schema from S3: minutes-analyzer-prompts-local/schemas/output_schema.json')
        expect(logger).to receive(:info).with('Successfully retrieved output schema')
        s3_client.get_output_schema
      end
    end

    context 'when JSON parsing fails' do
      before do
        allow(mock_s3).to receive(:get_object).and_return(mock_response)
        allow(mock_response).to receive(:body).and_return(mock_body)
        allow(mock_body).to receive(:read).and_return('invalid json')
      end

      it 'logs error and raises exception' do
        expect(logger).to receive(:error).with(/Invalid JSON in output schema/)
        expect { s3_client.get_output_schema }.to raise_error(/Invalid output schema format/)
      end
    end
  end

  describe 'S3 client configuration' do
    context 'for local environment' do
      it 'configures LocalStack endpoint' do
        expect(Aws::S3::Client).to receive(:new).with(
          hash_including(
            endpoint: 'http://localstack:4566',
            force_path_style: true,
            region: 'ap-northeast-1'
          )
        )
        S3Client.new(logger, 'local')
      end
    end

    context 'for production environment' do
      it 'uses default AWS configuration' do
        expect(Aws::S3::Client).to receive(:new) do |opts|
          expect(opts).to include(region: 'ap-northeast-1')
          expect(opts).not_to have_key(:endpoint)
          mock_s3
        end
        S3Client.new(logger, 'production')
      end
    end
    
    context 'when S3_PROMPTS_BUCKET environment variable is set' do
      let(:custom_bucket) { 'custom-prompts-bucket' }
      
      before do
        allow(ENV).to receive(:fetch).with('S3_PROMPTS_BUCKET', anything).and_return(custom_bucket)
      end
      
      it 'uses the custom bucket name from environment variable' do
        new_client = S3Client.new(logger, environment)
        expect(mock_s3).to receive(:get_object).with(
          bucket: custom_bucket,
          key: 'prompts/meeting_analysis_prompt.txt'
        ).and_return(mock_response)
        allow(mock_response).to receive(:body).and_return(mock_body)
        allow(mock_body).to receive(:read).and_return('test')
        new_client.get_prompt
      end
    end
  end
end