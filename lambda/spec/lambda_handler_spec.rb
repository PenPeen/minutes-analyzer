require 'spec_helper'
require_relative '../lib/lambda_handler'
require_relative '../lib/slack_client'
require_relative '../lib/google_drive_client'

RSpec.describe LambdaHandler do
  let(:logger) { instance_double(Logger) }
  let(:secrets_manager) { instance_double(SecretsManager) }
  let(:gemini_client) { instance_double(GeminiClient) }
  let(:google_drive_client) { instance_double(GoogleDriveClient) }
  let(:context) { double(aws_request_id: 'test-request-id') }
  let(:handler) { described_class.new(logger: logger, secrets_manager: secrets_manager, gemini_client: gemini_client) }

  before do
    allow(logger).to receive(:level=)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(logger).to receive(:warn)
  end

  describe '#handle' do
    context '正常なケース' do
      let(:event) { { 'body' => JSON.generate({ 'file_id' => 'test-file-id', 'file_name' => 'test.txt' }) } }
      let(:secrets) { { 'GEMINI_API_KEY' => 'test-api-key', 'GOOGLE_SERVICE_ACCOUNT_JSON' => '{"type":"service_account"}' } }
      let(:file_content) { 'meeting transcript' }
      let(:summary) { 
        {
          'meeting_summary' => {
            'title' => 'テスト会議',
            'date' => '2025-01-15',
            'duration_minutes' => 30
          },
          'decisions' => [
            { 'content' => 'テスト決定事項' }
          ],
          'actions' => [
            { 'task' => 'テストタスク', 'assignee' => '担当者' }
          ]
        }
      }

      before do
        allow(secrets_manager).to receive(:get_secrets).and_return(secrets)
        allow(gemini_client).to receive(:analyze_meeting).and_return(summary)
        allow(GoogleDriveClient).to receive(:new).and_return(google_drive_client)
        allow(google_drive_client).to receive(:get_file_content).and_return(file_content)
      end

      context 'Slack Webhook URLが設定されていない場合' do
        it '成功レスポンスを返す（Slack通知なし）' do
          result = handler.handle(event: event, context: context)

          expect(result[:statusCode]).to eq(200)
          expect(JSON.parse(result[:body])['analysis']).to eq(summary)
          expect(JSON.parse(result[:body])['message']).to eq('Analysis complete.')
          expect(JSON.parse(result[:body])['integrations']['slack']).to eq('not_sent')
          expect(JSON.parse(result[:body])['integrations']['notion']).to eq('not_created')
        end

        it 'Slack webhook URL未設定の警告をログに出力' do
          expect(logger).to receive(:warn).with('Slack webhook URL is not configured')
          handler.handle(event: event, context: context)
        end
      end

      context 'Slack Webhook URLが設定されている場合' do
        let(:slack_client) { instance_double(SlackClient) }
        let(:slack_result) { { success: true, response_code: '200' } }
        let(:secrets) { { 'GEMINI_API_KEY' => 'test-api-key', 'SLACK_WEBHOOK_URL' => 'https://hooks.slack.com/test', 'GOOGLE_SERVICE_ACCOUNT_JSON' => '{"type":"service_account"}' } }

        before do
          allow(SlackClient).to receive(:new).and_return(slack_client)
          allow(slack_client).to receive(:send_notification).and_return(slack_result)
        end

        it '成功レスポンスを返す（Slack通知あり）' do
          result = handler.handle(event: event, context: context)

          expect(result[:statusCode]).to eq(200)
          expect(JSON.parse(result[:body])['analysis']).to eq(summary)
          expect(JSON.parse(result[:body])['integrations']['slack']).to eq('sent')
          expect(JSON.parse(result[:body])['slack_notification']).to eq(JSON.parse(slack_result.to_json))
        end

        it 'Slack通知を送信' do
          expect(slack_client).to receive(:send_notification).with(summary)
          handler.handle(event: event, context: context)
        end
      end

      context 'Slack通知が失敗した場合' do
        let(:slack_client) { instance_double(SlackClient) }
        let(:slack_result) { { success: false, response_code: '404', error: 'channel_not_found' } }
        let(:secrets) { { 'GEMINI_API_KEY' => 'test-api-key', 'SLACK_WEBHOOK_URL' => 'https://hooks.slack.com/test', 'GOOGLE_SERVICE_ACCOUNT_JSON' => '{"type":"service_account"}' } }

        before do
          allow(SlackClient).to receive(:new).and_return(slack_client)
          allow(slack_client).to receive(:send_notification).and_return(slack_result)
        end

        it 'Lambdaは成功し、Slack通知失敗情報を含む' do
          result = handler.handle(event: event, context: context)

          expect(result[:statusCode]).to eq(200)
          expect(JSON.parse(result[:body])['integrations']['slack']).to eq('not_sent')
          expect(JSON.parse(result[:body])['slack_notification']['success']).to eq(false)
          expect(JSON.parse(result[:body])['slack_notification']['error']).to eq('channel_not_found')
        end
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

    context 'Google Driveファイルを取得する場合' do
      let(:file_id) { '1234567890abcdef' }
      let(:file_name) { '2025年1月15日_新機能リリース進捗確認ミーティング.txt' }
      let(:event) { { 'body' => JSON.generate({ 'file_id' => file_id, 'file_name' => file_name }) } }
      let(:file_content) { '2025年1月15日\n\n新機能リリース進捗確認ミーティング\n...' }
      let(:google_credentials) { '{"type":"service_account","project_id":"test"}' }
      let(:secrets) do
        {
          'GEMINI_API_KEY' => 'test-api-key',
          'GOOGLE_SERVICE_ACCOUNT_JSON' => google_credentials
        }
      end
      let(:google_drive_client) { instance_double('GoogleDriveClient') }
      let(:summary) { 
        {
          'meeting_summary' => {
            'title' => 'テスト会議',
            'date' => '2025-01-15',
            'duration_minutes' => 30
          },
          'decisions' => [
            { 'content' => 'テスト決定事項' }
          ],
          'actions' => [
            { 'task' => 'テストタスク', 'assignee' => '担当者' }
          ]
        }
      }

      before do
        allow(secrets_manager).to receive(:get_secrets).and_return(secrets)
        allow(GoogleDriveClient).to receive(:new).with(google_credentials, logger).and_return(google_drive_client)
        allow(google_drive_client).to receive(:get_file_content).with(file_id).and_return(file_content)
        allow(gemini_client).to receive(:analyze_meeting).with(file_content).and_return(summary)
      end

      it 'ファイルを取得して分析を実行' do
        result = handler.handle(event: event, context: context)

        expect(result[:statusCode]).to eq(200)
        expect(google_drive_client).to have_received(:get_file_content).with(file_id)
        expect(gemini_client).to have_received(:analyze_meeting).with(file_content)
      end

      context 'Google認証情報が不足している場合' do
        let(:secrets) { { 'GEMINI_API_KEY' => 'test-api-key' } }

        it 'エラーレスポンスを返す' do
          result = handler.handle(event: event, context: context)

          expect(result[:statusCode]).to eq(500)
          expect(JSON.parse(result[:body])['error']).to include('Google credentials missing')
        end
      end
    end

    context 'file_idが含まれていない場合' do
      let(:event) { { 'body' => JSON.generate({}) } }
      let(:secrets) { { 'GEMINI_API_KEY' => 'test-api-key' } }

      before do
        allow(secrets_manager).to receive(:get_secrets).and_return(secrets)
      end

      it 'エラーレスポンスを返す' do
        result = handler.handle(event: event, context: context)

        expect(result[:statusCode]).to eq(400)
        expect(JSON.parse(result[:body])['error']).to include("Request must include 'file_id' field")
      end
    end
  end
end
