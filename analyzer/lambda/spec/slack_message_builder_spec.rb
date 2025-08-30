require 'spec_helper'
require 'logger'
require_relative '../lib/slack_message_builder'

RSpec.describe SlackMessageBuilder do
  let(:logger) { instance_double(Logger) }
  let(:builder) { described_class.new(logger) }
  let(:analysis_result) do
    {
      meeting_summary: {
        title: 'テスト会議',
        date: '2025-01-15',
        participants: ['山田太郎', '佐藤花子']
      },
      decisions: [
        { content: 'プロジェクト予算を決定', category: 'policy', priority: 'high' }
      ],
      actions: [
        {
          task: 'レポート作成',
          assignee: '山田太郎',
          priority: 'high',
          deadline: '2025-01-20',
          deadline_formatted: '2025/01/20'
        }
      ],
      executor_info: {
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
        expect(action_blocks.size).to eq(1)
        
        button = action_blocks.first[:elements].first
        expect(button[:type]).to eq('button')
        expect(button[:text][:text]).to eq('📋 Notionで詳細を見る')
        expect(button[:url]).to eq(notion_url)
        expect(button[:style]).to eq('primary')
      end
    end

    context 'actionsが空の場合' do
      let(:analysis_result_without_actions) do
        analysis_result.dup.tap { |ar| ar[:actions] = [] }
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

  describe '#sort_decisions' do
    let(:unsorted_decisions) do
      [
        { content: 'Low priority decision', priority: 'low' },
        { content: 'High priority decision', priority: 'high' },
        { content: 'Medium priority decision', priority: 'medium' },
        { content: 'No priority decision', priority: nil }
      ]
    end

    it '優先度順（high → medium → low → nil）で決定事項をソートする' do
      sorted = builder.send(:sort_decisions, unsorted_decisions)

      expect(sorted.map { |d| d[:content] }).to eq([
        'High priority decision',
        'Medium priority decision',
        'Low priority decision',
        'No priority decision'
      ])
    end
  end

  describe '#build_action_text' do
    it 'アクション項目に優先度絵文字を含む' do
      action = {
        task: 'レポート作成',
        assignee: '山田太郎',
        priority: 'high',
        deadline_formatted: '2025/01/20'
      }

      result = builder.send(:build_action_text, action)
      expect(result).to eq('🔴 レポート作成 - 山田太郎（2025/01/20）')
    end

    it 'medium優先度のアクション項目に黄色絵文字を含む' do
      action = {
        task: 'テスト実行',
        assignee: '佐藤花子',
        priority: 'medium',
        deadline_formatted: '期日未定'
      }

      result = builder.send(:build_action_text, action)
      expect(result).to eq('🟡 テスト実行 - 佐藤花子（期日未定）')
    end

    it '優先度がnilの場合はlow優先度として白い絵文字を使用' do
      action = {
        task: 'ドキュメント更新',
        assignee: '未定',
        priority: nil,
        deadline_formatted: '期日未定'
      }

      result = builder.send(:build_action_text, action)
      expect(result).to eq('⚪ ドキュメント更新 - 未定（期日未定）')
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