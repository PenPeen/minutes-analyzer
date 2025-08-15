# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SlackInteractionHandler do
  let(:handler) { described_class.new }
  let(:user_id) { 'U1234567890' }
  let(:trigger_id) { 'test_trigger_id' }
  let(:channel_id) { 'C1234567890' }

  let(:button_payload) do
    {
      'type' => 'interactive_message',
      'user' => { 'id' => user_id },
      'channel' => { 'id' => channel_id },
      'trigger_id' => trigger_id,
      'actions' => [
        {
          'name' => 'file_search',
          'type' => 'button',
          'value' => 'start_search'
        }
      ]
    }
  end

  let(:modal_submission_payload) do
    {
      'type' => 'view_submission',
      'user' => { 'id' => user_id },
      'view' => {
        'id' => 'view_123',
        'state' => {
          'values' => {
            'file_select_block' => {
              'file_select' => {
                'selected_option' => {
                  'value' => 'file_id_123',
                  'text' => { 'text' => 'Meeting Notes 2025-01-15.txt' }
                }
              }
            },
            'custom_title_block' => {
              'custom_title' => {
                'value' => 'Custom Meeting Name'
              }
            }
          }
        }
      }
    }
  end

  before do
    # Mock dependencies to avoid actual API calls
    allow_any_instance_of(SlackApiClient).to receive(:post_message)
    allow_any_instance_of(SlackApiClient).to receive(:post_ephemeral)
    allow_any_instance_of(SlackApiClient).to receive(:get_user_email).and_return('test@example.com')
    allow_any_instance_of(LambdaInvoker).to receive(:invoke_analysis_lambda)
      .and_return({ status: 'success', message: 'Analysis started' })
    allow_any_instance_of(SlackOptionsProvider).to receive(:provide_file_options)
      .and_return({ 'options' => [] })
    
    # Mock AWS STS client to prevent actual AWS calls
    mock_sts_client = double('STS Client')
    mock_identity = double('Identity', account: '123456789012')
    allow(Aws::STS::Client).to receive(:new).and_return(mock_sts_client)
    allow(mock_sts_client).to receive(:get_caller_identity).and_return(mock_identity)
    
    # Mock AWS Lambda client
    mock_lambda_client = double('Lambda Client')
    allow(Aws::Lambda::Client).to receive(:new).and_return(mock_lambda_client)
    allow(mock_lambda_client).to receive(:invoke)
    
    # Mock AWS Secrets Manager client
    mock_secrets_client = double('Secrets Manager Client')
    allow(Aws::SecretsManager::Client).to receive(:new).and_return(mock_secrets_client)
  end

  describe '#handle_interaction' do
    context 'with button interaction' do
      it 'handles file search button click' do
        response = handler.handle_interaction(button_payload)

        expect(response[:statusCode]).to eq(200)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to include('ファイル検索機能は現在開発中です')
      end

      it 'returns ephemeral response for button clicks' do
        response = handler.handle_interaction(button_payload)
        response_body = JSON.parse(response[:body])
        expect(response_body['response_type']).to eq('ephemeral')
      end
    end

    context 'with modal submission' do
      context 'when valid file is selected' do
        it 'processes modal submission successfully' do
          response = handler.handle_interaction(modal_submission_payload)

          expect(response[:statusCode]).to eq(200)
          response_body = JSON.parse(response[:body])
          expect(response_body['response_action']).to eq('clear')
        end

        it 'logs the selected file information' do
          expect { handler.handle_interaction(modal_submission_payload) }
            .to output(/Selected file: file_id_123/).to_stdout
        end

        it 'logs custom filename when provided' do
          expect { handler.handle_interaction(modal_submission_payload) }
            .to output(/Custom filename: Custom Meeting Name/).to_stdout
        end
      end

      context 'when no file is selected' do
        let(:empty_modal_payload) do
          payload = JSON.parse(modal_submission_payload.to_json)
          payload['view']['state']['values']['file_select_block']['file_select'].delete('selected_option')
          payload
        end

        it 'returns validation error' do
          response = handler.handle_interaction(empty_modal_payload)

          expect(response[:statusCode]).to eq(200)
          response_body = JSON.parse(response[:body])
          expect(response_body['response_action']).to eq('errors')
          expect(response_body['errors']['file_select']).to include('ファイルを選択してください')
        end
      end

      context 'when modal state is malformed' do
        let(:malformed_modal_payload) do
          payload = JSON.parse(modal_submission_payload.to_json)
          payload['view']['state'] = nil
          payload
        end

        it 'handles malformed payload gracefully' do
          response = handler.handle_interaction(malformed_modal_payload)

          expect(response[:statusCode]).to eq(400)
          response_body = JSON.parse(response[:body])
          expect(response_body['text']).to include('無効なモーダルデータ')
        end
      end
    end

    context 'with unsupported interaction type' do
      let(:unsupported_payload) do
        {
          'type' => 'unsupported_type',
          'user' => { 'id' => user_id }
        }
      end

      it 'returns unsupported interaction error' do
        response = handler.handle_interaction(unsupported_payload)

        expect(response[:statusCode]).to eq(400)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to include('サポートされていないインタラクションタイプ')
        expect(response_body['text']).to include('unsupported_type')
      end
    end

    context 'with missing user information' do
      let(:payload_without_user) do
        button_payload.dup.tap { |p| p.delete('user') }
      end

      it 'handles missing user gracefully' do
        response = handler.handle_interaction(payload_without_user)

        expect(response[:statusCode]).to eq(400)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to include('ユーザー情報が不足')
      end
    end

    context 'when processing raises an error' do
      before do
        allow(handler).to receive(:process_button_click).and_raise(StandardError.new('Processing error'))
      end

      it 'handles processing errors gracefully' do
        response = handler.handle_interaction(button_payload)

        expect(response[:statusCode]).to eq(500)
        response_body = JSON.parse(response[:body])
        expect(response_body['text']).to include('処理中にエラーが発生しました')
      end

      it 'logs error details' do
        expect { handler.handle_interaction(button_payload) }
          .to output(/Error processing interaction: Processing error/).to_stdout
      end
    end
  end

  describe 'private methods' do
    describe '#process_button_click' do
      it 'handles file search action' do
        actions = [{ 'name' => 'file_search', 'value' => 'start_search' }]
        response = handler.send(:process_button_click, actions, user_id)

        expect(response['text']).to include('ファイル検索機能は現在開発中です')
        expect(response['response_type']).to eq('ephemeral')
      end

      it 'handles unknown action' do
        actions = [{ 'name' => 'unknown_action', 'value' => 'test' }]
        response = handler.send(:process_button_click, actions, user_id)

        expect(response['text']).to include('未対応のアクション')
        expect(response['text']).to include('unknown_action')
      end

      it 'handles empty actions array' do
        response = handler.send(:process_button_click, [], user_id)
        expect(response['text']).to include('アクションが指定されていません')
      end
    end

    describe '#process_modal_submission' do
      let(:view_state) { modal_submission_payload['view']['state'] }

      it 'processes valid modal submission' do
        response = handler.send(:process_modal_submission, view_state, user_id)

        expect(response['response_action']).to eq('clear')
      end

      it 'extracts file information correctly' do
        expect { handler.send(:process_modal_submission, view_state, user_id) }
          .to output(/Selected file: file_id_123/).to_stdout
      end

      it 'extracts custom filename when provided' do
        expect { handler.send(:process_modal_submission, view_state, user_id) }
          .to output(/Custom filename: Custom Meeting Name/).to_stdout
      end

      it 'handles missing filename gracefully' do
        state = JSON.parse(view_state.to_json)
        state['values']['custom_title_block']['custom_title']['value'] = ''

        expect { handler.send(:process_modal_submission, state, user_id) }
          .to output(/Custom filename: \(none\)/).to_stdout
      end
    end

    describe '#extract_selected_file' do
      let(:values) { modal_submission_payload['view']['state']['values'] }

      it 'extracts file information correctly' do
        file_info = handler.send(:extract_selected_file, values)

        expect(file_info[:file_id]).to eq('file_id_123')
        expect(file_info[:file_name]).to eq('Meeting Notes 2025-01-15.txt')
        expect(file_info[:custom_filename]).to eq('Custom Meeting Name')
      end

      it 'handles missing selected option' do
        values = modal_submission_payload['view']['state']['values'].deep_dup
        values['file_select_block']['file_select'].delete('selected_option')

        file_info = handler.send(:extract_selected_file, values)
        expect(file_info).to be_nil
      end

      it 'handles missing custom filename' do
        values = JSON.parse(modal_submission_payload['view']['state']['values'].to_json)
        values['custom_title_block']['custom_title']['value'] = ''

        file_info = handler.send(:extract_selected_file, values)
        expect(file_info[:custom_filename]).to be_nil
      end

      it 'handles completely malformed values' do
        file_info = handler.send(:extract_selected_file, {})
        expect(file_info).to be_nil
      end
    end

    describe '#create_validation_error' do
      it 'creates proper validation error response' do
        errors = { 'field1' => 'Error message 1', 'field2' => 'Error message 2' }
        response = handler.send(:create_validation_error, errors)

        expect(response['response_action']).to eq('errors')
        expect(response['errors']).to eq(errors)
      end
    end

    describe '#create_success_response' do
      it 'creates proper success response' do
        response = handler.send(:create_success_response)
        expect(response['response_action']).to eq('clear')
      end
    end

    describe '#create_error_response' do
      it 'creates proper error response' do
        message = 'Test error message'
        response = handler.send(:create_error_response, message, 500)

        expect(response['text']).to eq(message)
        expect(response['response_type']).to eq('ephemeral')
      end
    end
  end

  describe '#handle_options_request' do
    let(:options_payload) do
      {
        'type' => 'options',
        'user' => { 'id' => user_id },
        'value' => 'search query'
      }
    end

    let(:mock_options_provider) { instance_double('SlackOptionsProvider') }

    before do
      # Mock the @options_provider instance variable
      allow_any_instance_of(described_class).to receive(:options_provider).and_return(mock_options_provider)
      # Also allow access to the instance variable directly
      handler.instance_variable_set(:@options_provider, mock_options_provider)
    end

    it 'calls options provider with correct parameters' do
      expected_result = {
        options: [
          {
            text: { type: 'plain_text', text: 'Test File.txt (2025/01/15 10:00)' },
            value: 'file_123'
          }
        ]
      }

      allow(mock_options_provider).to receive(:provide_file_options)
        .with(user_id, 'search query')
        .and_return(expected_result)

      result = handler.send(:handle_options_request, options_payload)

      expect(result).to eq(expected_result)
      expect(mock_options_provider).to have_received(:provide_file_options)
        .with(user_id, 'search query')
    end

    it 'handles empty search query' do
      payload_with_empty_query = options_payload.dup
      payload_with_empty_query['value'] = ''

      expected_result = { options: [] }
      allow(mock_options_provider).to receive(:provide_file_options)
        .with(user_id, '')
        .and_return(expected_result)

      result = handler.send(:handle_options_request, payload_with_empty_query)

      expect(result).to eq(expected_result)
    end

    it 'handles missing value in payload' do
      payload_without_value = options_payload.dup
      payload_without_value.delete('value')

      expected_result = { options: [] }
      allow(mock_options_provider).to receive(:provide_file_options)
        .with(user_id, '')
        .and_return(expected_result)

      result = handler.send(:handle_options_request, payload_without_value)

      expect(result).to eq(expected_result)
    end
  end

end