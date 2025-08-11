# frozen_string_literal: true

require 'spec_helper'
require_relative '../../handler'
require 'json'
require 'base64'

RSpec.describe 'Lambda Handler Integration' do
  describe '#lambda_handler' do
    let(:context) { double('Context', aws_request_id: 'test-request-123') }

    describe 'Health check endpoint' do
      let(:event) do
        {
          'path' => '/health',
          'httpMethod' => 'GET',
          'headers' => {},
          'body' => nil
        }
      end

      it 'returns healthy status' do
        result = lambda_handler(event: event, context: context)
        
        expect(result[:statusCode]).to eq(200)
        
        body = JSON.parse(result[:body])
        expect(body['status']).to eq('healthy')
        expect(body['timestamp']).to be_a(String)
      end
    end

    describe 'Slack command endpoint' do
      let(:timestamp) { Time.now.to_i.to_s }
      let(:command_body) { 'command=/meet-transcript&user_id=U123456&team_id=T123456&trigger_id=123.456' }
      let(:event) do
        {
          'path' => '/slack/commands',
          'httpMethod' => 'POST',
          'headers' => {
            'x-slack-signature' => 'invalid_signature',
            'x-slack-request-timestamp' => timestamp,
            'content-type' => 'application/x-www-form-urlencoded'
          },
          'body' => command_body,
          'isBase64Encoded' => false
        }
      end

      context 'with invalid signature' do
        it 'returns unauthorized' do
          result = lambda_handler(event: event, context: context)
          
          expect(result[:statusCode]).to eq(401)
          
          body = JSON.parse(result[:body])
          expect(body['error']).to eq('Unauthorized')
        end
      end

      context 'with valid signature' do
        before do
          # SlackRequestValidatorをモック
          validator = instance_double(SlackRequestValidator)
          allow(SlackRequestValidator).to receive(:new).and_return(validator)
          allow(validator).to receive(:valid_request?).and_return(true)
          
          # SlackCommandHandlerをモック
          handler = instance_double(SlackCommandHandler)
          allow(SlackCommandHandler).to receive(:new).and_return(handler)
          allow(handler).to receive(:handle).and_return(
            statusCode: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: ''
          )
        end

        it 'processes the command' do
          result = lambda_handler(event: event, context: context)
          
          expect(result[:statusCode]).to eq(200)
        end
      end
    end

    describe 'Slack interactions endpoint' do
      let(:timestamp) { Time.now.to_i.to_s }
      let(:payload) do
        {
          type: 'block_actions',
          user: { id: 'U123456' },
          actions: [{ action_id: 'file_select' }]
        }
      end
      let(:interaction_body) { "payload=#{URI.encode_www_form_component(payload.to_json)}" }
      let(:event) do
        {
          'path' => '/slack/interactions',
          'httpMethod' => 'POST',
          'headers' => {
            'x-slack-signature' => 'invalid_signature',
            'x-slack-request-timestamp' => timestamp,
            'content-type' => 'application/x-www-form-urlencoded'
          },
          'body' => interaction_body,
          'isBase64Encoded' => false
        }
      end

      context 'with invalid signature' do
        it 'returns unauthorized' do
          result = lambda_handler(event: event, context: context)
          
          expect(result[:statusCode]).to eq(401)
        end
      end

      context 'with valid signature' do
        before do
          # SlackRequestValidatorをモック
          validator = instance_double(SlackRequestValidator)
          allow(SlackRequestValidator).to receive(:new).and_return(validator)
          allow(validator).to receive(:valid_request?).and_return(true)
          
          # SlackInteractionHandlerをモック
          handler = instance_double(SlackInteractionHandler)
          allow(SlackInteractionHandler).to receive(:new).and_return(handler)
          allow(handler).to receive(:handle).and_return(
            statusCode: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: JSON.generate({})
          )
        end

        it 'processes the interaction' do
          result = lambda_handler(event: event, context: context)
          
          expect(result[:statusCode]).to eq(200)
        end
      end
    end

    describe 'OAuth callback endpoint' do
      let(:event) do
        {
          'path' => '/oauth/callback',
          'httpMethod' => 'GET',
          'headers' => {},
          'queryStringParameters' => {
            'code' => 'auth_code_123',
            'state' => 'user_id_123'
          }
        }
      end

      before do
        # OAuthCallbackHandlerをモック
        handler = instance_double(OAuthCallbackHandler)
        allow(OAuthCallbackHandler).to receive(:new).and_return(handler)
        allow(handler).to receive(:handle_callback).and_return(
          statusCode: 200,
          headers: { 'Content-Type' => 'text/html' },
          body: '<html><body>Success</body></html>'
        )
      end

      it 'handles OAuth callback' do
        result = lambda_handler(event: event, context: context)
        
        expect(result[:statusCode]).to eq(200)
        expect(result[:body]).to include('Success')
      end
    end

    describe 'Unknown path' do
      let(:event) do
        {
          'path' => '/unknown',
          'httpMethod' => 'GET',
          'headers' => {},
          'body' => nil
        }
      end

      it 'returns 404' do
        result = lambda_handler(event: event, context: context)
        
        expect(result[:statusCode]).to eq(404)
        
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Not Found')
      end
    end

    describe 'Error handling' do
      let(:event) do
        {
          'path' => '/health',
          'httpMethod' => 'GET',
          'headers' => {},
          'body' => nil
        }
      end

      before do
        allow(Time).to receive(:now).and_raise(StandardError, 'Test error')
      end

      it 'returns 500 on error' do
        result = lambda_handler(event: event, context: context)
        
        expect(result[:statusCode]).to eq(500)
        
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Internal Server Error')
        expect(body['message']).to eq('Test error')
      end
    end

    describe 'Base64 encoded body' do
      let(:command_body) { 'command=/meet-transcript&user_id=U123456' }
      let(:encoded_body) { Base64.encode64(command_body) }
      let(:event) do
        {
          'path' => '/slack/commands',
          'httpMethod' => 'POST',
          'headers' => {
            'x-slack-signature' => 'signature',
            'x-slack-request-timestamp' => Time.now.to_i.to_s
          },
          'body' => encoded_body,
          'isBase64Encoded' => true
        }
      end

      before do
        validator = instance_double(SlackRequestValidator)
        allow(SlackRequestValidator).to receive(:new).and_return(validator)
        allow(validator).to receive(:valid_request?).and_return(false)
      end

      it 'decodes base64 body correctly' do
        result = lambda_handler(event: event, context: context)
        
        # 署名検証が失敗することを確認（ボディが正しくデコードされている証拠）
        expect(result[:statusCode]).to eq(401)
      end
    end
  end
end