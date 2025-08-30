require 'spec_helper'
require 'lib/error_notification_service'
require 'lib/slack_notification_service'

RSpec.describe ErrorNotificationService do
  let(:logger) { create_logger_mock }
  let(:slack_service) { instance_double(SlackNotificationService) }
  let(:service) { described_class.new(slack_service, logger) }

  describe '#initialize' do
    it 'initializes with slack service and logger' do
      expect(service.instance_variable_get(:@slack_service)).to eq(slack_service)
      expect(service.instance_variable_get(:@logger)).to eq(logger)
    end
  end

  describe '#notify_error' do
    let(:error) { StandardError.new('Test error message') }
    let(:context) { { file_id: 'test-file-id', file_name: 'test-file.txt' } }
    let(:user_info) { { user_id: 'U123456', user_email: 'test@example.com' } }

    before do
      allow(slack_service).to receive(:send_slack_message).and_return({ success: true, timestamp: '1234567890' })
      allow(slack_service).to receive(:send_thread_reply).and_return({ success: true })
    end

    context 'when slack service is available' do
      it 'sends both main message and thread reply' do
        expect(slack_service).to receive(:send_slack_message).once
        expect(slack_service).to receive(:send_thread_reply).once

        result = service.notify_error(error, context: context, user_info: user_info)
        expect(result[:success]).to be true
      end

      it 'logs successful notification' do
        expect(logger).to receive(:info).with('Error notification sent successfully')
        service.notify_error(error, context: context, user_info: user_info)
      end
    end

    context 'when slack service is nil' do
      let(:slack_service) { nil }

      it 'returns early without sending notification' do
        result = service.notify_error(error, context: context, user_info: user_info)
        expect(result).to be_nil
      end
    end

    context 'when notification fails' do
      before do
        allow(slack_service).to receive(:send_slack_message).and_raise(StandardError.new('Slack error'))
      end

      it 'catches exception and logs error' do
        expect(logger).to receive(:error).with(/Failed to send error notification/)
        result = service.notify_error(error, context: context, user_info: user_info)
        expect(result[:success]).to be false
      end
    end
  end

  describe '#categorize_error (private method)' do
    it 'categorizes Google API client errors correctly' do
      error = double('error', class: double(name: 'Google::Apis::ClientError'), status_code: 404)
      category = service.send(:categorize_error, error)
      expect(category).to eq(:file_not_found)
    end

    it 'categorizes validation errors correctly' do
      error = double('error', class: double(name: 'RequestValidator::ValidationError'))
      category = service.send(:categorize_error, error)
      expect(category).to eq(:invalid_request)
    end

    it 'categorizes timeout errors correctly' do
      error = StandardError.new('timeout occurred')
      category = service.send(:categorize_error, error)
      expect(category).to eq(:timeout_error)
    end

    it 'categorizes unknown errors correctly' do
      error = StandardError.new('unknown error')
      category = service.send(:categorize_error, error)
      expect(category).to eq(:unknown_error)
    end
  end

  describe '#build_user_friendly_message (private method)' do
    it 'builds appropriate message for file not found error' do
      error = StandardError.new('File not found')
      message = service.send(:build_user_friendly_message, error, :file_not_found, {})
      expect(message).to include('📄 **ファイルが見つかりません**')
      expect(message).to include('指定されたファイルにアクセスできませんでした')
    end

    it 'builds appropriate message for access denied error' do
      error = StandardError.new('Access denied')
      message = service.send(:build_user_friendly_message, error, :access_denied, {})
      expect(message).to include('🔒 **ファイルにアクセスできません**')
      expect(message).to include('ファイルの読み取り権限がありません')
    end

    it 'builds appropriate message for Gemini API error' do
      error = StandardError.new('Gemini API error')
      message = service.send(:build_user_friendly_message, error, :gemini_api_error, {})
      expect(message).to include('🤖 **AI分析でエラーが発生しました**')
      expect(message).to include('議事録の分析中に問題が発生しました')
    end

    it 'includes timestamp in message' do
      error = StandardError.new('Test error')
      message = service.send(:build_user_friendly_message, error, :unknown_error, {})
      expect(message).to include('**発生時刻:**')
      expect(message).to match(/\d{4}年\d{2}月\d{2}日 \d{2}:\d{2}:\d{2}/)
    end
  end

  describe '#build_technical_message (private method)' do
    it 'builds technical message with error details' do
      error = StandardError.new('Test error')
      error.set_backtrace(['line1', 'line2', 'line3'])
      
      message = service.send(:build_technical_message, error, :unknown_error, { request_id: 'test-req' })
      
      expect(message).to include('🔧 **技術詳細情報**')
      expect(message).to include('"error_class": "StandardError"')
      expect(message).to include('"error_message": "Test error"')
      expect(message).to include('"request_id": "test-req"')
      expect(message).to include('line1')
    end

    it 'includes HTTP status for errors with status_code' do
      error = double('error', 
        class: double(name: 'HTTPError'), 
        message: 'HTTP error',
        status_code: 500,
        backtrace: nil
      )
      allow(error).to receive(:respond_to?).with(:status_code).and_return(true)
      
      message = service.send(:build_technical_message, error, :network_error, {})
      expect(message).to include('"http_status": 500')
    end
  end

  describe '#build_cloudwatch_logs_url (private method)' do
    before do
      stub_const('ENV', ENV.to_hash.merge({
        'AWS_REGION' => 'ap-northeast-1',
        'AWS_LAMBDA_FUNCTION_NAME' => 'test-function'
      }))
    end

    it 'builds CloudWatch Logs URL with correct parameters' do
      url = service.send(:build_cloudwatch_logs_url, 'test-request-id')
      
      expect(url).to include('ap-northeast-1.console.aws.amazon.com')
      expect(url).to include('cloudwatch/home')
      expect(url).to include('logs-insights')
      expect(url).to include('test-request-id')
    end

    it 'returns nil when function name is not available' do
      stub_const('ENV', ENV.to_hash.merge({ 'AWS_LAMBDA_FUNCTION_NAME' => nil }))
      
      url = service.send(:build_cloudwatch_logs_url, 'test-request-id')
      expect(url).to be_nil
    end

    it 'handles encoding errors gracefully' do
      allow(URI).to receive(:encode_www_form_component).and_raise(StandardError)
      
      url = service.send(:build_cloudwatch_logs_url, 'test-request-id')
      expect(url).to be_nil
    end
  end

  describe 'integration with different error types' do
    let(:context) { { request_id: 'test-req', file_id: 'file-123', file_name: 'test.txt' } }
    let(:user_info) { { user_id: 'U123456' } }

    before do
      allow(slack_service).to receive(:send_slack_message).and_return({ success: true, timestamp: '1234567890' })
      allow(slack_service).to receive(:send_thread_reply).and_return({ success: true })
    end

    it 'handles Google Drive file not found error' do
      error = double('error', 
        class: double(name: 'Google::Apis::ClientError'),
        message: 'File not found',
        status_code: 404
      )
      
      expect(slack_service).to receive(:send_slack_message) do |payload|
        text = payload[:blocks][0][:text][:text]
        expect(text).to include('📄 **ファイルが見つかりません**')
        { success: true, timestamp: '1234567890' }
      end
      
      service.notify_error(error, context: context, user_info: user_info)
    end

    it 'handles validation error' do
      error = double('error',
        class: double(name: 'RequestValidator::ValidationError'),
        message: 'Invalid request format'
      )
      
      expect(slack_service).to receive(:send_slack_message) do |payload|
        text = payload[:blocks][0][:text][:text]
        expect(text).to include('⚠️ **リクエストに問題があります**')
        { success: true, timestamp: '1234567890' }
      end
      
      service.notify_error(error, context: context, user_info: user_info)
    end

    it 'includes user information in main message' do
      error = StandardError.new('Test error')
      
      expect(slack_service).to receive(:send_slack_message) do |payload|
        text = payload[:blocks][0][:text][:text]
        expect(text).to include('**実行ユーザー:** <@U123456>')
        expect(text).to include('**ファイルID:** `file-123`')
        expect(text).to include('**ファイル名:** test.txt')
        { success: true, timestamp: '1234567890' }
      end
      
      service.notify_error(error, context: context, user_info: user_info)
    end
  end
end