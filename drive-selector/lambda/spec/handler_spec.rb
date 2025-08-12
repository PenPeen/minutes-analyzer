# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'lambda_handler' do
  let(:timestamp) { Time.now.to_i.to_s }
  let(:body) { 'token=test&command=%2Fmeet-transcript&user_id=U1234567890' }
  let(:valid_signature) { create_slack_signature(timestamp, body) }

  before do
    # Mock all external dependencies
    allow_any_instance_of(SlackRequestValidator).to receive(:valid_request?).and_return(true)
    allow_any_instance_of(SlackCommandHandler).to receive(:handle_command).and_return({
      statusCode: 200,
      body: JSON.generate({ text: 'Command handled successfully' })
    })
    allow_any_instance_of(SlackInteractionHandler).to receive(:handle_interaction).and_return({
      statusCode: 200,
      body: JSON.generate({ text: 'Interaction handled successfully' })
    })
  end

  describe 'routing' do
    context 'slack commands endpoint' do
      let(:event) do
        create_mock_lambda_event(
          path: '/slack/commands',
          body: body,
          headers: {
            'x-slack-signature' => valid_signature,
            'x-slack-request-timestamp' => timestamp
          }
        )
      end

      it 'routes to SlackCommandHandler' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(200)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to eq('Command handled successfully')
      end

      it 'sets proper content type' do
        response = lambda_handler(event: event, context: {})
        expect(response[:headers]['Content-Type']).to eq('application/json')
      end
    end

    context 'slack interactions endpoint' do
      let(:interaction_payload) do
        {
          type: 'interactive_message',
          user: { id: 'U1234567890' },
          actions: [{ name: 'test', value: 'test' }]
        }
      end
      let(:interaction_body) { "payload=#{URI.encode_www_form_component(interaction_payload.to_json)}" }

      let(:event) do
        create_mock_lambda_event(
          path: '/slack/interactions',
          body: interaction_body,
          headers: {
            'x-slack-signature' => create_slack_signature(timestamp, interaction_body),
            'x-slack-request-timestamp' => timestamp
          }
        )
      end

      it 'routes to SlackInteractionHandler' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(200)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to eq('Interaction handled successfully')
      end
    end

    context 'oauth callback endpoint' do
      let(:event) do
        create_mock_lambda_event(
          path: '/oauth/callback',
          method: 'GET'
        )
      end

      it 'returns placeholder response for OAuth callback' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(200)
        response_body = JSON.parse(response[:body])
        expect(response_body['message']).to eq('OAuth callback - implementation pending')
      end
    end

    context 'health check endpoint' do
      let(:event) do
        create_mock_lambda_event(
          path: '/health',
          method: 'GET'
        )
      end

      it 'returns health check response' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(200)
        response_body = JSON.parse(response[:body])
        expect(response_body['status']).to eq('healthy')
        expect(response_body['timestamp']).to be_present
      end
    end

    context 'unknown endpoint' do
      let(:event) do
        create_mock_lambda_event(path: '/unknown/path')
      end

      it 'returns 404 for unknown paths' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(404)
        response_body = JSON.parse(response[:body])
        expect(response_body['error']).to eq('Not Found')
        expect(response_body['path']).to eq('/unknown/path')
      end
    end
  end

  describe 'request validation' do
    context 'when Slack signature validation fails' do
      let(:event) do
        create_mock_lambda_event(
          path: '/slack/commands',
          body: body,
          headers: {
            'x-slack-signature' => 'invalid_signature',
            'x-slack-request-timestamp' => timestamp
          }
        )
      end

      before do
        allow_any_instance_of(SlackRequestValidator).to receive(:valid_request?).and_return(false)
      end

      it 'returns 401 unauthorized' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(401)
        response_body = JSON.parse(response[:body])
        expect(response_body['error']).to eq('Unauthorized - Invalid Slack signature')
      end
    end

    context 'when request body is missing for Slack endpoints' do
      let(:event) do
        create_mock_lambda_event(
          path: '/slack/commands',
          body: nil
        )
      end

      it 'returns 400 bad request' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(400)
        response_body = JSON.parse(response[:body])
        expect(response_body['error']).to eq('Bad Request')
        expect(response_body['message']).to include('Request body is required')
      end
    end
  end

  describe 'body parsing' do
    context 'with URL encoded body' do
      let(:event) do
        create_mock_lambda_event(
          path: '/slack/commands',
          body: 'key1=value1&key2=value%20with%20spaces&key3=',
          headers: {
            'content-type' => 'application/x-www-form-urlencoded'
          }
        )
      end

      it 'parses URL encoded body correctly' do
        # Mock to capture the parsed params
        expect_any_instance_of(SlackCommandHandler).to receive(:handle_command) do |_, params|
          expect(params['key1']).to eq('value1')
          expect(params['key2']).to eq('value with spaces')
          expect(params['key3']).to eq('')
          { statusCode: 200, body: JSON.generate({ text: 'ok' }) }
        end

        lambda_handler(event: event, context: {})
      end
    end

    context 'with malformed URL encoding' do
      let(:malformed_body) { 'key1=value1&key2=%ZZ' }  # Invalid percent encoding
      let(:event) do
        create_mock_lambda_event(
          path: '/slack/commands',
          body: malformed_body,
          headers: {
            'x-slack-signature' => create_slack_signature(timestamp, malformed_body),
            'x-slack-request-timestamp' => timestamp
          }
        )
      end

      it 'handles malformed encoding gracefully' do
        response = lambda_handler(event: event, context: {})

        # Should still process the request, with malformed values handled
        expect(response[:statusCode]).to eq(200)
      end
    end

    context 'with JSON body for interactions' do
      let(:json_payload) { { type: 'test', user: { id: 'U123' } } }
      let(:interaction_body) { "payload=#{URI.encode_www_form_component(json_payload.to_json)}" }
      let(:event) do
        create_mock_lambda_event(
          path: '/slack/interactions',
          body: interaction_body
        )
      end

      it 'parses JSON payload from interactions correctly' do
        expect_any_instance_of(SlackInteractionHandler).to receive(:handle_interaction) do |_, payload|
          expect(payload['type']).to eq('test')
          expect(payload['user']['id']).to eq('U123')
          { statusCode: 200, body: JSON.generate({ text: 'ok' }) }
        end

        lambda_handler(event: event, context: {})
      end
    end
  end

  describe 'error handling' do
    context 'when handler raises an exception' do
      let(:event) do
        create_mock_lambda_event(path: '/slack/commands', body: body)
      end

      before do
        allow_any_instance_of(SlackCommandHandler).to receive(:handle_command)
          .and_raise(StandardError.new('Handler error'))
      end

      it 'returns 500 internal server error' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(500)
        response_body = JSON.parse(response[:body])
        expect(response_body['error']).to eq('Internal Server Error')
        expect(response_body['message']).to include('Handler error')
      end

      it 'logs error details' do
        expect { lambda_handler(event: event, context: {}) }
          .to output(/Error processing request: Handler error/).to_stdout
      end
    end

    context 'when JSON parsing fails' do
      let(:event) do
        create_mock_lambda_event(
          path: '/slack/interactions',
          body: 'payload=invalid_json'
        )
      end

      it 'handles JSON parsing errors gracefully' do
        response = lambda_handler(event: event, context: {})

        expect(response[:statusCode]).to eq(400)
        response_body = JSON.parse(response[:body])
        expect(response_body['error']).to eq('Bad Request')
      end
    end
  end

  describe 'logging' do
    let(:event) do
      create_mock_lambda_event(path: '/health', method: 'GET')
    end

    it 'logs sanitized event information' do
      expect { lambda_handler(event: event, context: {}) }
        .to output(/Processing request: GET \/health/).to_stdout
    end

    it 'does not log sensitive headers' do
      event_with_secrets = event.dup
      event_with_secrets['headers']['x-slack-signature'] = 'secret_signature'
      event_with_secrets['headers']['authorization'] = 'Bearer secret_token'

      output = capture(:stdout) { lambda_handler(event: event_with_secrets, context: {}) }
      expect(output).not_to include('secret_signature')
      expect(output).not_to include('secret_token')
    end
  end

  describe 'response format' do
    let(:event) do
      create_mock_lambda_event(path: '/health', method: 'GET')
    end

    it 'returns proper API Gateway response format' do
      response = lambda_handler(event: event, context: {})

      expect(response).to have_key(:statusCode)
      expect(response).to have_key(:headers)
      expect(response).to have_key(:body)
      expect(response[:headers]).to have_key('Content-Type')
    end

    it 'returns JSON response body' do
      response = lambda_handler(event: event, context: {})

      expect { JSON.parse(response[:body]) }.not_to raise_error
    end
  end

  # Helper method to capture stdout
  def capture(stream)
    begin
      stream = stream.to_s
      eval "$#{stream} = StringIO.new"
      result = eval("$#{stream}").string
      yield
      result = eval("$#{stream}").string
    ensure
      eval("$#{stream} = #{stream.upcase}")
    end
    result
  end
end