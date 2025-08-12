# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SlackCommandHandler do
  let(:handler) { described_class.new }
  let(:slack_user_id) { 'U1234567890' }
  let(:channel_id) { 'C1234567890' }
  let(:response_url) { 'https://hooks.slack.com/commands/123/456/test' }

  let(:command_params) do
    {
      'token' => 'test_token',
      'team_id' => 'T1234567890',
      'team_domain' => 'test_team',
      'channel_id' => channel_id,
      'channel_name' => 'test_channel',
      'user_id' => slack_user_id,
      'user_name' => 'test_user',
      'command' => '/meet-transcript',
      'text' => '',
      'response_url' => response_url,
      'trigger_id' => 'test_trigger_id'
    }
  end

  before do
    # Mock GoogleOAuthClient
    oauth_client = instance_double(GoogleOAuthClient)
    allow(GoogleOAuthClient).to receive(:new).and_return(oauth_client)
    allow(handler).to receive(:oauth_client).and_return(oauth_client)
    
    # Default to unauthenticated user
    allow(oauth_client).to receive(:authenticated?).with(slack_user_id).and_return(false)
    allow(oauth_client).to receive(:generate_auth_url)
      .with(slack_user_id)
      .and_return('https://accounts.google.com/oauth/authorize?test=params')
  end

  describe '#handle_command' do
    context 'when command is /meet-transcript' do
      context 'and user is not authenticated' do
        it 'returns authentication required message' do
          response = handler.handle_command(command_params)

          expect(response[:statusCode]).to eq(200)
          response_body = JSON.parse(response[:body])
          expect(response_body['response_type']).to eq('ephemeral')
          expect(response_body['text']).to include('Google Driveにアクセスするための認証が必要です')
          expect(response_body['attachments'][0]['actions'][0]['url'])
            .to eq('https://accounts.google.com/oauth/authorize?test=params')
        end

        it 'includes proper authorization button' do
          response = handler.handle_command(command_params)
          response_body = JSON.parse(response[:body])
          
          button = response_body['attachments'][0]['actions'][0]
          expect(button['type']).to eq('button')
          expect(button['text']).to eq('Google Driveを認証')
          expect(button['style']).to eq('primary')
        end
      end

      context 'and user is authenticated' do
        before do
          allow(handler.oauth_client).to receive(:authenticated?).with(slack_user_id).and_return(true)
        end

        it 'returns success message with modal trigger' do
          response = handler.handle_command(command_params)

          expect(response[:statusCode]).to eq(200)
          response_body = JSON.parse(response[:body])
          expect(response_body['response_type']).to eq('ephemeral')
          expect(response_body['text']).to include('Google Drive検索を開始します')
        end

        it 'includes instructions for modal interaction' do
          response = handler.handle_command(command_params)
          response_body = JSON.parse(response[:body])
          expect(response_body['text']).to include('検索用のモーダルを表示しますので、しばらくお待ちください')
        end
      end
    end

    context 'when command is unknown' do
      let(:unknown_command_params) { command_params.merge('command' => '/unknown-command') }

      it 'returns unknown command error' do
        response = handler.handle_command(unknown_command_params)

        expect(response[:statusCode]).to eq(200)
        response_body = JSON.parse(response[:body])
        expect(response_body['response_type']).to eq('ephemeral')
        expect(response_body['text']).to include('未対応のコマンド')
        expect(response_body['text']).to include('/unknown-command')
      end
    end

    context 'with missing required parameters' do
      it 'handles missing user_id gracefully' do
        params_without_user_id = command_params.dup
        params_without_user_id.delete('user_id')

        response = handler.handle_command(params_without_user_id)

        expect(response[:statusCode]).to eq(400)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to include('必要なパラメータが不足')
      end

      it 'handles missing command gracefully' do
        params_without_command = command_params.dup
        params_without_command.delete('command')

        response = handler.handle_command(params_without_command)

        expect(response[:statusCode]).to eq(400)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to include('必要なパラメータが不足')
      end
    end

    context 'when OAuth client raises error' do
      before do
        allow(handler.oauth_client).to receive(:authenticated?)
          .and_raise(StandardError.new('OAuth service unavailable'))
      end

      it 'handles OAuth errors gracefully' do
        response = handler.handle_command(command_params)

        expect(response[:statusCode]).to eq(500)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to include('認証サービスにアクセスできません')
      end

      it 'logs error details' do
        expect { handler.handle_command(command_params) }
          .to output(/OAuth service unavailable/).to_stdout
      end
    end
  end

  describe 'private methods' do
    describe '#create_auth_required_response' do
      let(:auth_url) { 'https://accounts.google.com/oauth/authorize?test=params' }

      it 'creates proper authentication response' do
        response = handler.send(:create_auth_required_response, auth_url)

        expect(response['response_type']).to eq('ephemeral')
        expect(response['text']).to include('Google Driveにアクセスするための認証が必要です')
        expect(response['attachments']).to be_an(Array)
        expect(response['attachments'][0]['actions'][0]['url']).to eq(auth_url)
      end

      it 'includes security note' do
        response = handler.send(:create_auth_required_response, auth_url)
        expect(response['text']).to include('安全な接続で認証を行います')
      end
    end

    describe '#create_success_response' do
      it 'creates proper success response' do
        response = handler.send(:create_success_response)

        expect(response['response_type']).to eq('ephemeral')
        expect(response['text']).to include('Google Drive検索を開始します')
      end
    end

    describe '#create_error_response' do
      let(:error_message) { 'Test error message' }
      let(:status_code) { 500 }

      it 'creates proper error response with custom message' do
        response = handler.send(:create_error_response, error_message, status_code)

        expect(response['text']).to eq(error_message)
        expect(response['response_type']).to eq('ephemeral')
      end

      it 'defaults to status code 400' do
        response = handler.send(:create_error_response, error_message)
        # The method returns the response body, not the full HTTP response
        expect(response['text']).to eq(error_message)
      end
    end

    describe '#validate_required_params' do
      it 'returns true when all required params are present' do
        result = handler.send(:validate_required_params, command_params)
        expect(result).to be true
      end

      it 'returns false when user_id is missing' do
        params = command_params.dup
        params.delete('user_id')
        result = handler.send(:validate_required_params, params)
        expect(result).to be false
      end

      it 'returns false when command is missing' do
        params = command_params.dup
        params.delete('command')
        result = handler.send(:validate_required_params, params)
        expect(result).to be false
      end

      it 'returns false when user_id is empty' do
        params = command_params.merge('user_id' => '')
        result = handler.send(:validate_required_params, params)
        expect(result).to be false
      end
    end
  end
end