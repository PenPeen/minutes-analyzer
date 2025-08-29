require 'spec_helper'
require 'logger'
require_relative '../lib/slack_message_builder'

RSpec.describe SlackMessageBuilder do
  let(:logger) { instance_double(Logger) }
  let(:builder) { described_class.new(logger) }
  let(:analysis_result) do
    {
      'meeting_summary' => {
        'title' => 'テスト会議',
        'date' => '2025-01-15',
        'participants' => ['山田太郎', '佐藤花子']
      },
      'decisions' => [
        { 'content' => 'プロジェクト予算を決定', 'category' => 'policy' }
      ],
      'actions' => [
        {
          'task' => 'レポート作成',
          'assignee' => '山田太郎',
          'priority' => 'high',
          'deadline' => '2025-01-20',
          'deadline_formatted' => '2025/01/20'
        }
      ],
      'executor_info' => {
        'user_id' => 'U123456789'
      }
    }
  end

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe '#build_main_message' do
    context 'notion_urlがない場合' do
      it '基本的なSlackメッセージを構築する' do
        result = builder.build_main_message(analysis_result)

        expect(result).to have_key(:text)
        expect(result).to have_key(:blocks)
        expect(result[:blocks]).to be_an(Array)
        expect(result[:blocks].length).to be >= 4 # mention, header, summary, decisions, actions
        
        # Notionボタンが含まれていないことを確認
        action_blocks = result[:blocks].select { |block| block[:type] == 'actions' }
        expect(action_blocks).to be_empty
      end
    end

    context 'notion_urlがある場合' do
      let(:notion_url) { 'https://notion.so/page123' }

      it 'Notionボタンを含むSlackメッセージを構築する' do
        result = builder.build_main_message(analysis_result, notion_url)

        expect(result).to have_key(:text)
        expect(result).to have_key(:blocks)
        expect(result[:blocks]).to be_an(Array)
        
        # Notionボタンが含まれていることを確認
        action_blocks = result[:blocks].select { |block| block[:type] == 'actions' }
        expect(action_blocks).to have_exactly(1).items
        
        button = action_blocks.first[:elements].first
        expect(button[:type]).to eq('button')
        expect(button[:text][:text]).to eq('📋 Notionで詳細を見る')
        expect(button[:url]).to eq(notion_url)
        expect(button[:style]).to eq('primary')
      end
    end

    context 'actionsが空の場合' do
      let(:analysis_result_without_actions) do
        analysis_result.dup.tap { |ar| ar['actions'] = [] }
      end

      it 'アクションセクションを含まずにメッセージを構築する' do
        result = builder.build_main_message(analysis_result_without_actions)

        expect(result[:blocks]).to be_an(Array)
        
        # アクションセクションが含まれていないことを確認
        action_sections = result[:blocks].select do |block|
          block[:type] == 'section' && 
          block.dig(:text, :text)&.include?('アクション一覧')
        end
        expect(action_sections).to be_empty
      end
    end
  end

  describe '#build_notion_button' do
    let(:notion_url) { 'https://notion.so/test-page-123' }

    it '正しい形式のNotionボタンを構築する' do
      button_block = builder.send(:build_notion_button, notion_url)

      expect(button_block).to eq({
        type: "actions",
        elements: [
          {
            type: "button",
            text: {
              type: "plain_text",
              text: "📋 Notionで詳細を見る",
              emoji: true
            },
            url: notion_url,
            style: "primary"
          }
        ]
      })
    end
  end
end