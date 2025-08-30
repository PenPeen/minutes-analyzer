require 'spec_helper'
require 'logger'
require_relative '../lib/integration_service'
require_relative '../lib/slack_notification_service'
require_relative '../lib/notion_integration_service'

RSpec.describe IntegrationService do
  let(:logger) { instance_double(Logger) }
  let(:service) { described_class.new(logger) }
  let(:analysis_result) do
    {
      meeting_summary: {
        title: 'Test Meeting',
        date: '2025-01-15',
        participants: ['User A', 'User B']
      },
      decisions: [
        { content: 'Decision 1', category: 'policy' }
      ],
      actions: [
        {
          task: 'Task 1',
          assignee: 'User A',
          priority: 'high',
          deadline: '2025-01-20',
          deadline_formatted: '2025/01/20'
        }
      ]
    }
  end
  let(:secrets) do
    {
      'SLACK_BOT_TOKEN' => 'xoxb-test-token',
      'SLACK_CHANNEL_ID' => 'C1234567890',
      'NOTION_API_KEY' => 'notion-test-key',
      'NOTION_DATABASE_ID' => 'notion-db-id',
      'NOTION_TASK_DATABASE_ID' => 'notion-task-db-id'
    }
  end
  let(:user_mappings) { {} }
  let(:executor_info) { { user_id: 'U123456789' } }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe '#process_integrations' do
    let(:slack_service) { instance_double(SlackNotificationService) }
    let(:notion_service) { instance_double(NotionIntegrationService) }

    before do
      allow(SlackNotificationService).to receive(:new).and_return(slack_service)
      allow(NotionIntegrationService).to receive(:new).and_return(notion_service)
    end

    context 'Notion連携成功時' do
      let(:notion_result) { { success: true, page_id: 'page123', url: 'https://notion.so/page123' } }
      let(:slack_result) { { success: true, timestamp: '1234567890.123' } }

      before do
        allow(notion_service).to receive(:create_meeting_page).and_return(notion_result)
        allow(slack_service).to receive(:send_notification).and_return(slack_result)
      end

      it 'NotionのURLをSlackに渡して通知を送信する' do
        result = service.process_integrations(analysis_result, secrets, user_mappings, executor_info)

        expect(notion_service).to have_received(:create_meeting_page).with(analysis_result)
        expect(slack_service).to have_received(:send_notification).with(
          analysis_result.merge(slack_mentions: nil, executor_info: executor_info),
          'https://notion.so/page123'
        )
        expect(result).to eq({
          notion: notion_result,
          slack: slack_result
        })
      end
    end

    context 'Notion連携失敗時' do
      let(:notion_result) { { success: false, error: 'Notion API error' } }
      let(:slack_result) { { success: true, timestamp: '1234567890.123' } }

      before do
        allow(notion_service).to receive(:create_meeting_page).and_return(notion_result)
        allow(slack_service).to receive(:send_notification).and_return(slack_result)
      end

      it 'Notion URLなしでSlack通知を送信する' do
        result = service.process_integrations(analysis_result, secrets, user_mappings, executor_info)

        expect(notion_service).to have_received(:create_meeting_page).with(analysis_result)
        expect(slack_service).to have_received(:send_notification).with(
          analysis_result.merge(slack_mentions: nil, executor_info: executor_info),
          nil
        )
        expect(result).to eq({
          notion: notion_result,
          slack: slack_result
        })
      end
    end

    context 'Slack設定が無効な場合' do
      let(:invalid_secrets) { secrets.merge('SLACK_BOT_TOKEN' => nil) }
      let(:notion_result) { { success: true, page_id: 'page123', url: 'https://notion.so/page123' } }

      before do
        allow(notion_service).to receive(:create_meeting_page).and_return(notion_result)
      end

      it 'Notion連携は実行してSlack連携はスキップする' do
        result = service.process_integrations(analysis_result, invalid_secrets, user_mappings, executor_info)

        expect(notion_service).to have_received(:create_meeting_page).with(analysis_result)
        expect(SlackNotificationService).not_to have_received(:new)
        expect(result[:notion]).to eq(notion_result)
        expect(result[:slack]).to be_nil
      end
    end

    context 'Notion設定が無効な場合' do
      let(:invalid_secrets) { secrets.merge('NOTION_API_KEY' => nil) }
      let(:slack_result) { { success: true, timestamp: '1234567890.123' } }

      before do
        allow(slack_service).to receive(:send_notification).and_return(slack_result)
      end

      it 'Notion連携をスキップしてSlack連携のみ実行する' do
        result = service.process_integrations(analysis_result, invalid_secrets, user_mappings, executor_info)

        expect(NotionIntegrationService).not_to have_received(:new)
        expect(slack_service).to have_received(:send_notification).with(
          analysis_result.merge(slack_mentions: nil, executor_info: executor_info),
          nil
        )
        expect(result[:notion]).to be_nil
        expect(result[:slack]).to eq(slack_result)
      end
    end
  end
end