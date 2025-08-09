require 'spec_helper'
require_relative '../lib/slack_client'
require 'webmock/rspec'
require 'logger'

RSpec.describe SlackClient do
  let(:bot_token) { 'xoxb-test-token-12345' }
  let(:channel_id) { 'C1234567890' }
  let(:logger) { instance_double(Logger) }
  let(:slack_client) { SlackClient.new(bot_token, channel_id, logger) }
  let(:api_endpoint) { "https://slack.com/api/chat.postMessage" }

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
            'deadline' => '2025/01/20',
            'deadline_formatted' => '2025/01/20'
          },
          {
            'task' => 'API連携の実装',
            'assignee' => '開発チーム',
            'priority' => 'medium',
            'deadline' => nil,
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
      let(:main_response) do
        {
          ok: true,
          ts: '1234567890.123456',
          channel: 'C1234567890'
        }.to_json
      end
      
      let(:thread_response) do
        {
          ok: true,
          ts: '1234567890.123457',
          channel: 'C1234567890'
        }.to_json
      end
      
      before do
        # メインメッセージの送信をスタブ化
        stub_request(:post, api_endpoint)
          .with(
            headers: { 'Authorization' => "Bearer #{bot_token}" }
          )
          .to_return(status: 200, body: main_response)
          .then
          .to_return(status: 200, body: thread_response)
      end

      it 'returns success with timestamp' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be true
        expect(result[:response_code]).to eq '200'
        expect(result[:timestamp]).to eq '1234567890.123456'
      end

      it 'logs success message' do
        expect(logger).to receive(:info).with('Sending message to Slack via Web API').at_least(:once)
        expect(logger).to receive(:info).with('Successfully sent message to Slack').at_least(:once)
        slack_client.send_notification(analysis_result)
      end
    end

    context 'when notification fails' do
      let(:error_response) do
        {
          ok: false,
          error: 'channel_not_found'
        }.to_json
      end
      
      before do
        stub_request(:post, api_endpoint)
          .with(
            headers: { 'Authorization' => "Bearer #{bot_token}" }
          )
          .to_return(status: 200, body: error_response)
      end

      it 'returns failure' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be false
        expect(result[:error]).to eq 'channel_not_found'
      end

      it 'logs error message' do
        expect(logger).to receive(:error).with(/Slack API error: channel_not_found/)
        slack_client.send_notification(analysis_result)
      end
    end

    context 'when bot token is not configured' do
      let(:bot_token) { nil }

      it 'returns error without making HTTP request' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be false
        expect(result[:message]).to eq 'Bot token not configured'
      end
    end
    
    context 'when channel ID is not configured' do
      let(:channel_id) { nil }

      it 'returns error without making HTTP request' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be false
        expect(result[:message]).to eq 'Channel ID not configured'
      end
    end

    context 'when network error occurs' do
      before do
        stub_request(:post, api_endpoint)
          .to_raise(Net::OpenTimeout.new('execution expired'))
      end

      it 'handles the error gracefully' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be false
        expect(result[:error]).to include('execution expired')
      end
    end

    context 'with many participants' do
      let(:analysis_result) do
        {
          'meeting_summary' => {
            'date' => '2025-01-15',
            'title' => '新機能リリース進捗確認MTG',
            'duration_minutes' => 30,
            'participants' => ['田中太郎', '佐藤花子', '鈴木一郎', '山田太郎', '高橋花子']
          },
          'decisions' => [],
          'actions' => [],
          'actions_summary' => {}
        }
      end

      before do
        stub_request(:post, api_endpoint)
          .to_return(status: 200, body: { ok: true, ts: '1234567890.123456' }.to_json)
      end

      it 'limits participants display to 3 with others count' do
        slack_client.send_notification(analysis_result)
        expect(WebMock).to have_requested(:post, api_endpoint)
          .with { |req| 
            body = JSON.parse(req.body)
            body['blocks'].any? { |block| 
              block['fields'] && block['fields'].any? { |field| 
                field['text'] && field['text'].include?('…他2名')
              }
            }
          }
      end
    end

    context 'with many decisions' do
      let(:analysis_result) do
        {
          'meeting_summary' => {
            'title' => '新機能リリース進捗確認MTG'
          },
          'decisions' => [
            { 'content' => '決定事項1' },
            { 'content' => '決定事項2' },
            { 'content' => '決定事項3' },
            { 'content' => '決定事項4' },
            { 'content' => '決定事項5' }
          ],
          'actions' => [],
          'actions_summary' => {}
        }
      end

      before do
        stub_request(:post, api_endpoint)
          .to_return(status: 200, body: { ok: true, ts: '1234567890.123456' }.to_json)
      end

      it 'limits decisions display to 3 with others count' do
        slack_client.send_notification(analysis_result)
        expect(WebMock).to have_requested(:post, api_endpoint)
          .with { |req| 
            body = JSON.parse(req.body)
            body['blocks'].any? { |block| 
              block['text'] && block['text']['text'] && 
              block['text']['text'].include?('…他2件')
            }
          }
      end
    end

    context 'with atmosphere and suggestions for thread reply' do
      let(:analysis_result) do
        {
          'meeting_summary' => {
            'title' => '新機能リリース進捗確認MTG'
          },
          'decisions' => [],
          'actions' => [],
          'atmosphere' => {
            'overall_tone' => 'positive',
            'evidence' => [
              '素晴らしい進捗ですね',
              '順調に進んでいます'
            ]
          },
          'improvement_suggestions' => [
            {
              'category' => 'time_management',
              'suggestion' => 'アクションアイテムには可能な限り具体的な期日を設定しましょう',
              'expected_impact' => 'タスクの実行が加速し、進捗管理がより明確になります'
            },
            {
              'category' => 'participation',
              'suggestion' => '各トピックで全員から意見を求める時間を設けると良いでしょう',
              'expected_impact' => 'チーム全体の当事者意識向上'
            }
          ]
        }
      end

      before do
        # メインメッセージとスレッド返信の両方をスタブ化
        stub_request(:post, api_endpoint)
          .to_return(status: 200, body: { ok: true, ts: '1234567890.123456' }.to_json)
          .then
          .to_return(status: 200, body: { ok: true, ts: '1234567890.123457' }.to_json)
      end

      it 'sends thread reply with atmosphere and suggestions' do
        result = slack_client.send_notification(analysis_result)
        expect(result[:success]).to be true
        expect(result[:thread_sent]).to be true
      end

      it 'sends two requests (main and thread)' do
        slack_client.send_notification(analysis_result)
        # 2回のリクエスト（メイン通知とスレッド返信）が送信されることを確認
        expect(WebMock).to have_requested(:post, api_endpoint).times(2)
      end
      
      it 'includes thread_ts in second request' do
        slack_client.send_notification(analysis_result)
        
        # 2番目のリクエストにthread_tsが含まれていることを確認
        expect(WebMock).to have_requested(:post, api_endpoint)
          .with { |req| 
            body = JSON.parse(req.body)
            body['thread_ts'] == '1234567890.123456'
          }
      end
    end

    context 'with actions sorted by priority and deadline' do
      let(:analysis_result) do
        {
          'meeting_summary' => {
            'title' => '新機能リリース進捗確認MTG'
          },
          'decisions' => [],
          'actions' => [
            {
              'task' => 'Low priority late',
              'assignee' => 'チームA',
              'priority' => 'low',
              'deadline' => '2025/03/01',
              'deadline_formatted' => '2025/03/01'
            },
            {
              'task' => 'High priority soon',
              'assignee' => 'チームB',
              'priority' => 'high',
              'deadline' => '2025/01/15',
              'deadline_formatted' => '2025/01/15'
            },
            {
              'task' => 'High priority no deadline',
              'assignee' => 'チームC',
              'priority' => 'high',
              'deadline' => nil,
              'deadline_formatted' => '期日未定'
            },
            {
              'task' => 'Medium priority',
              'assignee' => 'チームD',
              'priority' => 'medium',
              'deadline' => '2025/02/01',
              'deadline_formatted' => '2025/02/01'
            }
          ],
          'actions_summary' => {
            'total_count' => 4,
            'with_deadline' => 3,
            'without_deadline' => 1,
            'high_priority_count' => 2
          }
        }
      end

      before do
        stub_request(:post, api_endpoint)
          .to_return(status: 200, body: { ok: true, ts: '1234567890.123456' }.to_json)
      end

      it 'sorts actions by priority then deadline' do
        slack_client.send_notification(analysis_result)
        expect(WebMock).to have_requested(:post, api_endpoint)
          .with { |req| 
            body = JSON.parse(req.body)
            actions_text = body['blocks'].find { |b| b['text'] && b['text']['text'] && b['text']['text'].include?('アクション一覧') }['text']['text']
            
            # 期待される順序: High priority soon, High priority no deadline, Medium priority
            actions_text.include?('High priority soon') &&
            actions_text.index('High priority soon') < actions_text.index('High priority no deadline') &&
            actions_text.index('High priority no deadline') < actions_text.index('Medium priority')
          }
      end
    end
  end
end