require 'spec_helper'
require_relative '../lib/slack_client'
require 'webmock/rspec'

RSpec.describe SlackClient do
  let(:webhook_url) { 'https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX' }
  let(:logger) { instance_double(Logger) }
  let(:slack_client) { SlackClient.new(webhook_url, logger) }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(logger).to receive(:warn)
  end

  describe '#send_notification' do
    let(:analysis_result) do
      {
        'meeting_summary' => {
          'date' => '2025-01-15',
          'title' => '新機能リリース進捗確認MTG',
          'duration_minutes' => 30,
          'participants' => ['田中太郎', '佐藤花子', '鈴木一郎']
        },
        'decisions' => [
          { 'content' => '価格設定を月額500円に決定', 'category' => 'pricing' },
          { 'content' => 'リリース日を2月1日に設定', 'category' => 'schedule' }
        ],
        'actions' => [
          {
            'task' => 'セキュリティテストの実施',
            'assignee' => 'セキュリティチーム',
            'priority' => 'high',
            'deadline_formatted' => '2025/01/20'
          },
          {
            'task' => 'API連携の実装',
            'assignee' => '開発チーム',
            'priority' => 'medium',
            'deadline_formatted' => '期日未定'
          }
        ],
        'actions_summary' => {
          'total_count' => 2,
          'with_deadline' => 1,
          'without_deadline' => 1,
          'high_priority_count' => 1
        },
        'health_assessment' => {
          'overall_score' => 85
        }
      }
    end

    context 'when notification is sent successfully' do
      before do
        stub_request(:post, webhook_url)
          .to_return(status: 200, body: 'ok')
      end

      it 'returns success' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be true
        expect(result[:response_code]).to eq '200'
      end

      it 'logs success message' do
        expect(logger).to receive(:info).with('Sending notification to Slack')
        expect(logger).to receive(:info).with('Successfully sent notification to Slack')
        slack_client.send_notification(analysis_result)
      end
    end

    context 'when notification fails' do
      before do
        stub_request(:post, webhook_url)
          .to_return(status: 404, body: 'channel_not_found')
      end

      it 'returns failure' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be false
        expect(result[:response_code]).to eq '404'
        expect(result[:error]).to eq 'channel_not_found'
      end

      it 'logs error message' do
        expect(logger).to receive(:error).with(/Failed to send notification to Slack/)
        slack_client.send_notification(analysis_result)
      end
    end

    context 'when webhook URL is not configured' do
      let(:webhook_url) { nil }

      it 'returns error without making HTTP request' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be false
        expect(result[:message]).to eq 'Webhook URL not configured'
      end
    end

    context 'when network error occurs' do
      before do
        stub_request(:post, webhook_url)
          .to_raise(Net::OpenTimeout.new('execution expired'))
      end

      it 'handles the error gracefully' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be false
        expect(result[:error]).to include('execution expired')
      end
    end
  end
end