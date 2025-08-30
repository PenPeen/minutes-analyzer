require 'spec_helper'
require 'logger'
require_relative '../lib/slack_notification_service'
require_relative '../lib/slack_api_client'
require_relative '../lib/slack_message_builder'

RSpec.describe SlackNotificationService do
  let(:bot_token) { 'xoxb-test-token' }
  let(:channel_id) { 'C1234567890' }
  let(:logger) { instance_double(Logger) }
  let(:api_client) { instance_double(SlackApiClient) }
  let(:message_builder) { instance_double(SlackMessageBuilder) }
  let(:service) { described_class.new(bot_token, channel_id, logger) }
  let(:analysis_result) do
    {
      meeting_summary: {
        title: 'テスト会議',
        date: '2025-01-15'
      },
      decisions: [],
      actions: []
    }
  end
  let(:main_message) do
    {
      text: 'テスト会議の議事録レビューが完了しました！',
      blocks: []
    }
  end

  before do
    allow(SlackApiClient).to receive(:new).and_return(api_client)
    allow(SlackMessageBuilder).to receive(:new).and_return(message_builder)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe '#send_notification' do
    context 'notion_urlがない場合' do
      let(:api_response) { { success: true, data: { 'ts' => '1234567890.123' } } }

      before do
        allow(message_builder).to receive(:build_main_message).and_return(main_message)
        allow(api_client).to receive(:post_message).and_return(api_response)
      end

      it 'notion_url無しでメッセージを構築して送信する' do
        result = service.send_notification(analysis_result)

        expect(message_builder).to have_received(:build_main_message).with(analysis_result, nil)
        expect(api_client).to have_received(:post_message).with(channel_id, main_message)
        expect(result).to eq({ success: true, timestamp: '1234567890.123' })
      end
    end

    context 'notion_urlがある場合' do
      let(:notion_url) { 'https://notion.so/page123' }
      let(:api_response) { { success: true, data: { 'ts' => '1234567890.123' } } }

      before do
        allow(message_builder).to receive(:build_main_message).and_return(main_message)
        allow(api_client).to receive(:post_message).and_return(api_response)
      end

      it 'notion_urlを含めてメッセージを構築して送信する' do
        result = service.send_notification(analysis_result, notion_url)

        expect(message_builder).to have_received(:build_main_message).with(analysis_result, notion_url)
        expect(api_client).to have_received(:post_message).with(channel_id, main_message)
        expect(result).to eq({ success: true, timestamp: '1234567890.123' })
      end
    end

    context 'Slack API送信失敗時' do
      let(:api_response) { { success: false, error: 'channel_not_found' } }

      before do
        allow(message_builder).to receive(:build_main_message).and_return(main_message)
        allow(api_client).to receive(:post_message).and_return(api_response)
      end

      it '失敗結果を返す' do
        result = service.send_notification(analysis_result)

        expect(result).to eq({ success: false, error: 'channel_not_found' })
        expect(logger).to have_received(:error).with(/Failed to send Slack notification/)
      end
    end

    context 'botトークンが設定されていない場合' do
      let(:service) { described_class.new(nil, channel_id, logger) }

      it 'エラーを返す' do
        result = service.send_notification(analysis_result)

        expect(result).to eq({ success: false, error: 'Slack bot token is not configured' })
        expect(logger).to have_received(:error).with('Slack bot token is not configured')
      end
    end

    context 'チャンネルIDが設定されていない場合' do
      let(:service) { described_class.new(bot_token, nil, logger) }

      it 'エラーを返す' do
        result = service.send_notification(analysis_result)

        expect(result).to eq({ success: false, error: 'Slack channel ID is not configured' })
        expect(logger).to have_received(:error).with('Slack channel ID is not configured')
      end
    end

    context 'スレッド返信が必要な場合' do
      let(:analysis_result_with_suggestions) do
        analysis_result.merge({
          atmosphere: { overall_tone: 'positive' },
          improvement_suggestions: [
            { suggestion: '改善提案1' }
          ]
        })
      end
      let(:api_response) { { success: true, data: { 'ts' => '1234567890.123' } } }
      let(:thread_message) { { text: 'スレッドメッセージ', blocks: [] } }

      before do
        allow(message_builder).to receive(:build_main_message).and_return(main_message)
        allow(message_builder).to receive(:build_thread_message).and_return(thread_message)
        allow(api_client).to receive(:post_message).and_return(api_response)
        allow(api_client).to receive(:post_thread_reply).and_return({ success: true })
      end

      it 'メイン送信後にスレッド返信も送信する' do
        result = service.send_notification(analysis_result_with_suggestions)

        expect(api_client).to have_received(:post_message).with(channel_id, main_message)
        expect(api_client).to have_received(:post_thread_reply)
          .with(channel_id, '1234567890.123', thread_message)
        expect(result).to eq({ success: true, timestamp: '1234567890.123' })
      end
    end
  end
end