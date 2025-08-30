require 'spec_helper'
require_relative '../lib/notion_integration_service'
require 'webmock/rspec'
require 'logger'

RSpec.describe NotionIntegrationService do
  let(:api_key) { 'test-notion-api-key' }
  let(:database_id) { 'test-database-id' }
  let(:task_database_id) { 'test-task-database-id' }
  let(:logger) { Logger.new(nil) }
  let(:client) { NotionIntegrationService.new(api_key, database_id, task_database_id, logger) }

  describe '#create_meeting_page' do
    let(:analysis_result) do
      {
        'meeting_summary' => {
          'title' => '週次定例会議',
          'date' => '2025-08-04',
          'duration_minutes' => 30,
          'participants' => ['田中', '佐藤', '鈴木']
        },
        'decisions' => [
          {
            'content' => '新機能のリリース日を来月15日に決定',
            'category' => 'schedule'
          },
          {
            'content' => '予算を20%増額することを承認',
            'category' => 'policy'
          }
        ],
        'actions' => [
          {
            'task' => '仕様書の作成',
            'assignee' => '田中',
            'priority' => 'high',
            'deadline' => '2024-02-01',
            'deadline_formatted' => '2024/02/01',
            'suggested_steps' => ['要件整理', 'ドラフト作成', 'レビュー'],
            'timestamp' => '00:20:00',
            'task_context' => '新機能リリースに向けた設計文書の準備'
          },
          {
            'task' => 'デザイン案の提出',
            'assignee' => '佐藤',
            'priority' => 'medium',
            'deadline' => nil,
            'deadline_formatted' => '期日未定',
            'suggested_steps' => ['コンセプト作成', 'プロトタイプ作成'],
            'timestamp' => '00:25:00',
            'task_context' => 'UIリニューアルのためのデザイン案作成'
          }
        ],
        'health_assessment' => {
          'overall_score' => 85,
          'contradictions' => [],
          'unresolved_issues' => ['リソース不足の懸念あり'],
          'undefined_items' => []
        },
        'participation_analysis' => {
          'balance_score' => 80,
          'speaker_stats' => [
            { 'name' => '田中', 'speaking_count' => 10, 'speaking_ratio' => '40%' },
            { 'name' => '佐藤', 'speaking_count' => 8, 'speaking_ratio' => '35%' },
            { 'name' => '鈴木', 'speaking_count' => 6, 'speaking_ratio' => '25%' }
          ],
          'silent_participants' => []
        },
        'atmosphere' => {
          'overall_tone' => 'positive',
          'comment' => 'チーム全体が積極的に議論に参加し、特にリリース計画について建設的な意見交換が行われていました。参加者からの前向きなフィードバックが多く、プロジェクトへの高いモチベーションが感じられる雰囲気でした。'
        },
        'improvement_suggestions' => [
          {
            'category' => 'time_management',
            'suggestion' => '議題の事前共有により時間短縮可能',
            'expected_impact' => '会議時間の20%削減'
          }
        ]
      }
    end

    context 'when page creation is successful' do
      let(:page_id) { 'created-page-id' }
      let(:page_url) { 'https://www.notion.so/created-page-id' }

      before do
        # Mock page creation
        stub_request(:post, "https://api.notion.com/v1/pages")
          .with(
            headers: {
              'Authorization' => "Bearer #{api_key}",
              'Notion-Version' => '2022-06-28',
              'Content-Type' => 'application/json'
            }
          )
          .to_return(
            status: 200,
            body: { id: page_id, url: page_url }.to_json
          )

        # Mock task creation
        analysis_result['actions'].each do |action|
          stub_request(:post, "https://api.notion.com/v1/pages")
            .with(
              headers: {
                'Authorization' => "Bearer #{api_key}",
                'Notion-Version' => '2022-06-28',
                'Content-Type' => 'application/json'
              },
              body: hash_including(
                parent: { database_id: task_database_id }
              )
            )
            .to_return(
              status: 200,
              body: { id: "task-#{action['task']}", url: "https://www.notion.so/task" }.to_json
            )
        end
      end

      it 'creates a page and returns success result' do
        result = client.create_meeting_page(analysis_result)

        expect(result).to eq({
          success: true,
          page_id: page_id,
          url: page_url
        })
      end

      it 'creates tasks for each todo item' do
        client.create_meeting_page(analysis_result)

        # Verify task creation requests were made
        expect(WebMock).to have_requested(:post, "https://api.notion.com/v1/pages")
          .times(3) # 1 for page + 2 for tasks
      end
    end

    context 'when page creation fails' do
      before do
        stub_request(:post, "https://api.notion.com/v1/pages")
          .to_return(
            status: 400,
            body: { message: 'Invalid database ID' }.to_json
          )
      end

      it 'returns failure result' do
        result = client.create_meeting_page(analysis_result)

        expect(result[:success]).to be false
        expect(result[:error]).to include('400')
      end
    end

    context 'when network error occurs' do
      before do
        stub_request(:post, "https://api.notion.com/v1/pages")
          .to_raise(Net::ReadTimeout)
      end

      it 'returns failure result with error message' do
        result = client.create_meeting_page(analysis_result)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Net::ReadTimeout')
      end
    end
  end

  describe '#build_task_content' do
    let(:action_with_context) do
      {
        'task' => 'タスク名',
        'assignee' => '担当者',
        'priority' => 'high',
        'deadline_formatted' => '2024/02/01',
        'timestamp' => '00:10:00',
        'task_context' => 'これはタスクの背景情報です',
        'suggested_steps' => ['ステップ1', 'ステップ2', 'ステップ3']
      }
    end

    let(:action_without_context) do
      {
        'task' => 'タスク名',
        'assignee' => '担当者',
        'priority' => 'medium',
        'deadline_formatted' => '期日未定'
      }
    end

    it 'includes task context when present' do
      content = client.send(:build_task_content, action_with_context)
      
      context_section = content.find { |c| c[:type] == 'heading_2' && c[:heading_2][:rich_text][0][:text][:content] == '📝 背景・文脈' }
      expect(context_section).not_to be_nil
      
      context_text = content.find { |c| c[:type] == 'paragraph' && c[:paragraph][:rich_text][0][:text][:content] == 'これはタスクの背景情報です' }
      expect(context_text).not_to be_nil
    end

    it 'includes task steps when present' do
      content = client.send(:build_task_content, action_with_context)
      
      steps_section = content.find { |c| c[:type] == 'heading_2' && c[:heading_2][:rich_text][0][:text][:content] == '📋 実行手順' }
      expect(steps_section).not_to be_nil
      
      numbered_items = content.select { |c| c[:type] == 'numbered_list_item' }
      expect(numbered_items.size).to eq(3)
    end

    it 'always includes task details section' do
      content = client.send(:build_task_content, action_without_context)
      
      details_section = content.find { |c| c[:type] == 'heading_2' && c[:heading_2][:rich_text][0][:text][:content] == 'ℹ️ タスク情報' }
      expect(details_section).not_to be_nil
    end

    it 'handles missing optional fields gracefully' do
      content = client.send(:build_task_content, action_without_context)
      
      context_section = content.find { |c| c[:type] == 'heading_2' && c[:heading_2][:rich_text][0][:text][:content] == '📝 背景・文脈' }
      expect(context_section).to be_nil
      
      steps_section = content.find { |c| c[:type] == 'heading_2' && c[:heading_2][:rich_text][0][:text][:content] == '📋 実行手順' }
      expect(steps_section).to be_nil
    end
  end

  describe 'page content structure' do
    let(:analysis_result) do
      {
        'meeting_summary' => {
          'title' => 'テスト会議',
          'date' => '2025-08-04'
        },
        'decisions' => [
          { 'content' => '決定事項1', 'timestamp' => '00:05:00' }
        ],
        'actions' => [
          { 'task' => 'タスク1', 'assignee' => '担当者' }
        ],
        'health_assessment' => {
          'overall_score' => 90,
          'unresolved_issues' => ['警告1']
        },
        'atmosphere' => {
          'overall_tone' => 'positive',
          'comment' => 'チーム全体が積極的に議論に参加し、特にリリース計画について建設的な意見交換が行われていました。参加者からの前向きなフィードバックが多く、プロジェクトへの高いモチベーションが感じられる雰囲気でした。'
        },
        'improvement_suggestions' => [
          { 'category' => 'facilitation', 'suggestion' => 'アドバイス', 'expected_impact' => '改善' }
        ]
      }
    end

    it 'includes all sections in the correct order' do
      # Capture the request body
      request_body = nil
      stub_request(:post, "https://api.notion.com/v1/pages")
        .with do |request|
          body = JSON.parse(request.body)
          # Only capture the main page creation request, not task creation
          if body['parent'] && body['parent']['database_id'] == database_id
            request_body = body
          end
          true
        end
        .to_return(status: 200, body: { id: 'test-id', url: 'test-url' }.to_json)

      client.create_meeting_page(analysis_result)

      # Verify page structure
      expect(request_body).not_to be_nil
      expect(request_body).to have_key('children')
      children = request_body['children']
      expect(children).not_to be_empty
      expect(children[0]['type']).to eq('heading_1')
      expect(children[0]['heading_1']['rich_text'][0]['text']['content']).to eq('議事録サマリー')

      # Check that all sections are present
      section_headers = children
        .select { |c| c['type'] == 'heading_2' }
        .map { |c| c['heading_2']['rich_text'][0]['text']['content'] }

      expect(section_headers).to include('📌 決定事項')
      expect(section_headers).to include('✅ アクション項目')
      expect(section_headers).to include('🌡️ 会議の雰囲気')
      expect(section_headers).to include('💡 改善提案')
    end
  end
end
