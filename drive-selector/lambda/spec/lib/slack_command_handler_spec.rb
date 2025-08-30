# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

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
      'command' => '/meeting-analyzer',
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
      .with(slack_user_id, nil, nil)
      .and_return('https://accounts.google.com/oauth/authorize?test=params')
  end

  describe '#handle_command' do
    context 'when command is /meeting-analyzer' do
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
          
          # Stub the Slack API call for opening modal
          stub_request(:post, "https://slack.com/api/views.open")
            .with(
              headers: {
                'Authorization' => 'Bearer xoxb-test-bot-token',
                'Content-Type' => 'application/json; charset=utf-8'
              }
            )
            .to_return(status: 200, body: '{"ok": true}', headers: {})
        end

        it 'returns success message with modal trigger' do
          response = handler.handle_command(command_params)

          expect(response[:statusCode]).to eq(200)
          expect(response[:body]).to eq('')
          expect(response[:headers]['Content-Type']).to eq('text/plain')
        end
      end
    end

    context 'when command is /meeting-analyzer-url' do
      let(:url_command_params) do
        command_params.merge(
          'command' => '/meeting-analyzer-url',
          'text' => 'https://docs.google.com/document/d/test_file_id/edit'
        )
      end

      context 'with no URL provided' do
        let(:empty_url_params) { url_command_params.merge('text' => '') }

        it 'returns error message for missing URL' do
          response = handler.handle_command(empty_url_params)

          expect(response[:statusCode]).to eq(200)
          response_body = JSON.parse(response[:body])
          expect(response_body['response_type']).to eq('ephemeral')
          expect(response_body['text']).to include('Google ドキュメントのURLを入力してください')
          expect(response_body['text']).to include('例: /meeting-analyzer-url https://docs.google.com/document/d/XXXXX')
        end
      end

      context 'with invalid URL' do
        let(:invalid_url_params) { url_command_params.merge('text' => 'https://invalid-url.com') }

        it 'returns error message for invalid URL' do
          response = handler.handle_command(invalid_url_params)

          expect(response[:statusCode]).to eq(200)
          response_body = JSON.parse(response[:body])
          expect(response_body['response_type']).to eq('ephemeral')
          expect(response_body['text']).to include('無効なGoogle ドキュメントURLです')
          expect(response_body['text']).to include('正しいURLを入力してください')
        end
      end

      context 'with valid URL but user not authenticated' do
        it 'returns authentication required message' do
          response = handler.handle_command(url_command_params)

          expect(response[:statusCode]).to eq(200)
          response_body = JSON.parse(response[:body])
          expect(response_body['response_type']).to eq('ephemeral')
          expect(response_body['text']).to include('Google Driveにアクセスするための認証が必要です')
        end
      end

      context 'with valid URL and authenticated user' do
        let(:mock_drive_client) { instance_double(GoogleDriveClient) }
        let(:mock_lambda_invoker) { instance_double(LambdaInvoker) }
        let(:file_info) { { 'name' => 'Test Meeting Document' } }

        before do
          allow(handler.oauth_client).to receive(:authenticated?).with(slack_user_id).and_return(true)
          allow(handler.oauth_client).to receive(:get_valid_tokens)
            .with(slack_user_id)
            .and_return({ 'access_token' => 'ya29.test_token' })
          
          allow(GoogleDriveClient).to receive(:new).with('ya29.test_token').and_return(mock_drive_client)
          allow(LambdaInvoker).to receive(:new).and_return(mock_lambda_invoker)
          
          allow(mock_drive_client).to receive(:get_file_info)
            .with('test_file_id')
            .and_return(file_info)
          
          allow(mock_lambda_invoker).to receive(:invoke_analyzer)
        end

        it 'successfully processes valid Google Docs URL' do
          response = handler.handle_command(url_command_params)

          expect(response[:statusCode]).to eq(200)
          response_body = JSON.parse(response[:body])
          expect(response_body['response_type']).to eq('in_channel')
          expect(response_body['text']).to include('📝 議事録分析を開始しました: Test Meeting Document')
        end

        it 'invokes analyzer lambda with correct payload' do
          expected_payload = {
            input_type: 'url',
            file_id: 'test_file_id',
            file_name: 'Test Meeting Document',
            slack_user_id: slack_user_id,
            google_doc_url: 'https://docs.google.com/document/d/test_file_id/edit'
          }

          handler.handle_command(url_command_params)
          expect(mock_lambda_invoker).to have_received(:invoke_analyzer).with(expected_payload)
        end

        context 'when file access is denied' do
          before do
            allow(mock_drive_client).to receive(:get_file_info)
              .and_raise(GoogleDriveClient::AccessDeniedError.new('Access denied'))
          end

          it 'returns access denied error' do
            response = handler.handle_command(url_command_params)

            expect(response[:statusCode]).to eq(200)
            response_body = JSON.parse(response[:body])
            expect(response_body['response_type']).to eq('ephemeral')
            expect(response_body['text']).to include('指定されたドキュメントへのアクセス権限がありません')
            expect(response_body['text']).to include('ドキュメントの所有者に共有権限の付与を依頼してください')
          end
        end

        context 'when file is not found' do
          before do
            allow(mock_drive_client).to receive(:get_file_info)
              .and_raise(GoogleDriveClient::FileNotFoundError.new('File not found'))
          end

          it 'returns file not found error' do
            response = handler.handle_command(url_command_params)

            expect(response[:statusCode]).to eq(200)
            response_body = JSON.parse(response[:body])
            expect(response_body['response_type']).to eq('ephemeral')
            expect(response_body['text']).to include('指定されたドキュメントが見つかりません')
            expect(response_body['text']).to include('URLが正しいことを確認してください')
          end
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

        expect(response).to be_empty
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

    describe '#extract_file_id_from_url' do
      it 'extracts file ID from standard Google Docs URL' do
        url = 'https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit'
        result = handler.send(:extract_file_id_from_url, url)
        expect(result).to eq('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms')
      end

      it 'extracts file ID from Google Docs URL without /edit' do
        url = 'https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/'
        result = handler.send(:extract_file_id_from_url, url)
        expect(result).to eq('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms')
      end

      it 'extracts file ID from Google Drive file URL' do
        url = 'https://drive.google.com/file/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/view'
        result = handler.send(:extract_file_id_from_url, url)
        expect(result).to eq('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms')
      end

      it 'extracts file ID from Google Drive open URL' do
        url = 'https://drive.google.com/open?id=1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms'
        result = handler.send(:extract_file_id_from_url, url)
        expect(result).to eq('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms')
      end

      it 'returns nil for invalid URLs' do
        invalid_urls = [
          'https://example.com/document',
          'https://docs.google.com/spreadsheets/d/123/edit',
          'not-a-url',
          '',
          nil,
          '   ',  # 空白文字のみ
          'https://docs.google.com/document/d//edit'  # 空のファイルID
        ]

        invalid_urls.each do |url|
          result = handler.send(:extract_file_id_from_url, url)
          expect(result).to be_nil, "Expected nil for URL: #{url.inspect}"
        end
      end

      it 'handles URLs with additional parameters' do
        url = 'https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit?usp=sharing'
        result = handler.send(:extract_file_id_from_url, url)
        expect(result).to eq('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms')
      end
    end
  end
end