require 'spec_helper'
require_relative '../lib/lambda_handler'

RSpec.describe LambdaHandler do
  let(:logger) { instance_double(Logger) }
  let(:secrets_manager) { instance_double(SecretsManager) }
  let(:gemini_client) { instance_double(GeminiClient) }
  let(:context) { double(aws_request_id: 'test-request-id') }
  let(:handler) { described_class.new(logger: logger, secrets_manager: secrets_manager, gemini_client: gemini_client) }

  before do
    allow(logger).to receive(:level=)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
  end

  describe '#handle' do
    context '正常なケース' do
      let(:event) { { 'body' => JSON.generate({ 'text' => 'meeting transcript' }) } }
      let(:secrets) { { 'GEMINI_API_KEY' => 'test-api-key' } }
      let(:summary) { 'This is a summary' }

      before do
        allow(secrets_manager).to receive(:get_secrets).and_return(secrets)
        allow(gemini_client).to receive(:summarize).and_return(summary)
      end

      it '成功レスポンスを返す' do
        result = handler.handle(event: event, context: context)

        expect(result[:statusCode]).to eq(200)
        expect(JSON.parse(result[:body])['summary']).to eq(summary)
        expect(JSON.parse(result[:body])['message']).to eq('Analysis complete.')
      end
    end

    context 'APIキーが不足している場合' do
      let(:event) { { 'body' => JSON.generate({ 'text' => 'meeting transcript' }) } }
      let(:secrets) { { 'GEMINI_API_KEY' => '' } }

      before do
        allow(secrets_manager).to receive(:get_secrets).and_return(secrets)
      end

      it 'エラーレスポンスを返す' do
        result = handler.handle(event: event, context: context)

        expect(result[:statusCode]).to eq(500)
        expect(JSON.parse(result[:body])['error']).to include('API key is missing')
      end
    end

    context 'リクエストボディが不足している場合' do
      let(:event) { {} }

      before do
        allow(secrets_manager).to receive(:get_secrets).and_return({'GEMINI_API_KEY' => 'test_key'})
      end

      it 'エラーレスポンスを返す' do
        result = handler.handle(event: event, context: context)

        expect(result[:statusCode]).to eq(400)
        expect(JSON.parse(result[:body])['error']).to include('Request body is missing')
      end
    end

    context '無効なJSONの場合' do
      let(:event) { { 'body' => 'invalid json' } }
      let(:secrets) { { 'GEMINI_API_KEY' => 'test-api-key' } }

      before do
        allow(secrets_manager).to receive(:get_secrets).and_return(secrets)
      end

      it 'エラーレスポンスを返す' do
        result = handler.handle(event: event, context: context)

        expect(result[:statusCode]).to eq(400)
        expect(JSON.parse(result[:body])['error']).to include('Invalid JSON')
      end
    end
  end
end
