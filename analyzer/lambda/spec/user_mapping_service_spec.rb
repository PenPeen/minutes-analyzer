require 'spec_helper'
require_relative '../lib/user_mapping_service'
require_relative '../lib/environment_config'

RSpec.describe UserMappingService do
  let(:logger) { double('logger') }
  let(:config) { double('EnvironmentConfig') }
  let(:processor) { double('MeetingTranscriptProcessor') }
  let(:service) { UserMappingService.new(logger, config) }
  let(:file_id) { 'test-file-id-123' }
  let(:secrets) do
    {
      'GOOGLE_SERVICE_ACCOUNT_JSON' => '{"type":"service_account"}',
      'SLACK_BOT_TOKEN' => 'xoxb-test-token',
      'NOTION_API_KEY' => 'secret_test_key'
    }
  end

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:level).and_return(Logger::INFO)
  end

  describe '#initialize' do
    it 'ロガーと設定が正しく設定される' do
      expect(service.instance_variable_get(:@logger)).to eq(logger)
      expect(service.instance_variable_get(:@config)).to eq(config)
      expect(service.instance_variable_get(:@processor)).to be_nil
    end
  end

  describe '#process_mapping' do
    context 'ユーザーマッピングが無効な場合' do
      before do
        allow(config).to receive(:user_mapping_enabled?).and_return(false)
      end

      it '空のハッシュを返し、処理をスキップ' do
        result = service.process_mapping(file_id, secrets)
        expect(result).to eq({})
        expect(logger).not_to have_received(:info)
      end
    end

    context 'ユーザーマッピングが有効な場合' do
      let(:mapping_result) do
        {
          status: 'completed',
          participants: ['user1@example.com', 'user2@example.com'],
          user_mappings: {
            slack: {
              'user1@example.com' => { id: 'U12345', name: 'User One' },
              'user2@example.com' => { id: 'U67890', name: 'User Two' }
            },
            notion: {
              'user1@example.com' => { id: 'notion-user-1' },
              'user2@example.com' => { id: 'notion-user-2' }
            }
          }
        }
      end

      before do
        allow(config).to receive(:user_mapping_enabled?).and_return(true)
        allow(config).to receive(:google_calendar_enabled).and_return(true)
        allow(config).to receive(:user_mapping_enabled).and_return(true)
        allow(MeetingTranscriptProcessor).to receive(:new).and_return(processor)
        allow(processor).to receive(:process_transcript).and_return(mapping_result)
        allow(processor).to receive(:get_statistics).and_return({ total_api_calls: 4, processing_time: 15.5 })
      end

      it '成功時に適切な結果を返す' do
        result = service.process_mapping(file_id, secrets)
        
        expect(result).to eq(mapping_result)
        expect(logger).to have_received(:info).with("Starting user mapping for file_id: #{file_id}")
        expect(logger).to have_received(:info).with("User mapping completed successfully")
        expect(logger).to have_received(:info).with("Found 2 participants")
      end

      it 'プロセッサが正しい設定で作成される' do
        expected_config = {
          google_calendar_enabled: true,
          user_mapping_enabled: true,
          google_service_account_json: '{"type":"service_account"}',
          slack_bot_token: 'xoxb-test-token',
          notion_api_key: 'secret_test_key',
          parallel_processing: true,
          max_threads: 10,
          api_timeout: 30
        }

        expect(MeetingTranscriptProcessor).to receive(:new).with(expected_config).and_return(processor)
        service.process_mapping(file_id, secrets)
      end

      it 'ユーザーマッピング統計をログに出力' do
        expected_stats = { total_api_calls: 4, processing_time: 15.5 }.to_json
        
        service.process_mapping(file_id, secrets)
        
        expect(logger).to have_received(:info).with("User mapping statistics: #{expected_stats}")
        expect(logger).to have_received(:info).with("Successfully mapped 2 Slack users and 2 Notion users")
      end
    end

    context '部分的成功の場合' do
      let(:partial_result) do
        {
          status: 'partial',
          participants: ['user1@example.com', 'user2@example.com'],
          warnings: ['Slack API rate limit encountered', 'One Notion user not found'],
          user_mappings: {
            slack: { 'user1@example.com' => { id: 'U12345' } },
            notion: { 'user1@example.com' => { id: 'notion-user-1' } }
          }
        }
      end

      before do
        allow(config).to receive(:user_mapping_enabled?).and_return(true)
        allow(config).to receive(:google_calendar_enabled).and_return(true)
        allow(config).to receive(:user_mapping_enabled).and_return(true)
        allow(MeetingTranscriptProcessor).to receive(:new).and_return(processor)
        allow(processor).to receive(:process_transcript).and_return(partial_result)
      end

      it '部分的成功の警告をログに出力' do
        service.process_mapping(file_id, secrets)
        
        expect(logger).to have_received(:warn).with(
          "User mapping partially completed: Slack API rate limit encountered, One Notion user not found"
        )
      end
    end

    context 'タイムアウトが発生した場合' do
      before do
        allow(config).to receive(:user_mapping_enabled?).and_return(true)
        allow(config).to receive(:google_calendar_enabled).and_return(true)
        allow(config).to receive(:user_mapping_enabled).and_return(true)
        allow(MeetingTranscriptProcessor).to receive(:new).and_return(processor)
        allow(processor).to receive(:process_transcript).and_raise(Timeout::Error)
      end

      it 'タイムアウトエラーを適切に処理' do
        result = service.process_mapping(file_id, secrets)
        
        expect(result[:status]).to eq('partial')
        expect(result[:error]).to include('Timeout during user mapping')
        expect(result[:warnings]).to include('Some user mappings may be incomplete due to timeout')
        expect(logger).to have_received(:error).with("User mapping timeout after #{UserMappingService::MAPPING_TIMEOUT} seconds")
      end
    end

    context '一般的なエラーが発生した場合' do
      let(:test_error) { StandardError.new('API connection failed') }

      before do
        allow(config).to receive(:user_mapping_enabled?).and_return(true)
        allow(config).to receive(:google_calendar_enabled).and_return(true)
        allow(config).to receive(:user_mapping_enabled).and_return(true)
        allow(MeetingTranscriptProcessor).to receive(:new).and_return(processor)
        allow(processor).to receive(:process_transcript).and_raise(test_error)
        allow(test_error).to receive(:backtrace).and_return(['line1', 'line2', 'line3', 'line4', 'line5', 'line6'])
      end

      it '一般的なエラーを適切に処理' do
        result = service.process_mapping(file_id, secrets)
        
        expect(result[:status]).to eq('partial')
        expect(result[:error]).to eq('API connection failed')
        expect(result[:warnings]).to include('User mapping unavailable, continuing without it')
        expect(logger).to have_received(:error).with("Error in user mapping process: API connection failed")
        expect(logger).to have_received(:error).with(/line1\nline2\nline3\nline4\nline5/)
      end
    end
  end

  describe '#enrich_actions_with_assignees' do
    let(:analysis_result) do
      {
        'actions' => [
          { 'task' => 'タスク1', 'assignee' => 'User One' },
          { 'task' => 'タスク2', 'assignee' => 'user2@example.com' },
          { 'task' => 'タスク3', 'assignee' => 'チーム' }
        ]
      }
    end

    let(:user_mappings) do
      {
        status: 'completed',
        participants: ['user1@example.com', 'user2@example.com'],
        user_mappings: {
          slack: {
            'user1@example.com' => { id: 'U12345', name: 'User One' },
            'user2@example.com' => { id: 'U67890', name: 'User Two' }
          },
          notion: {
            'user1@example.com' => { id: 'notion-user-1' },
            'user2@example.com' => { id: 'notion-user-2' }
          }
        }
      }
    end

    context '有効なユーザーマッピングデータの場合' do
      it 'アクションにユーザー情報を正しく追加' do
        result = service.enrich_actions_with_assignees(analysis_result, user_mappings)
        
        # 名前による一致 (User One -> user1@example.com)
        action1 = result['actions'][0]
        expect(action1['notion_user_id']).to eq('notion-user-1')
        expect(action1['slack_user_id']).to eq('U12345')
        expect(action1['slack_mention']).to eq('<@U12345>')
        expect(action1['assignee_email']).to eq('user1@example.com')
        
        # メールアドレス直接一致
        action2 = result['actions'][1]
        expect(action2['notion_user_id']).to eq('notion-user-2')
        expect(action2['slack_user_id']).to eq('U67890')
        expect(action2['slack_mention']).to eq('<@U67890>')
        expect(action2['assignee_email']).to eq('user2@example.com')
        
        # マッチしない担当者
        action3 = result['actions'][2]
        expect(action3['notion_user_id']).to be_nil
        expect(action3['slack_user_id']).to be_nil
      end

      it 'エンリッチ開始のログを出力' do
        service.enrich_actions_with_assignees(analysis_result, user_mappings)
        expect(logger).to have_received(:info).with("Enriching actions with user mapping data")
      end
    end

    context '無効な分析結果の場合' do
      it 'Hashでない分析結果はそのまま返す' do
        invalid_result = "not a hash"
        result = service.enrich_actions_with_assignees(invalid_result, user_mappings)
        expect(result).to eq(invalid_result)
      end

      it 'actionsが配列でない場合はそのまま返す' do
        invalid_actions = { 'actions' => 'not an array' }
        result = service.enrich_actions_with_assignees(invalid_actions, user_mappings)
        expect(result).to eq(invalid_actions)
      end

      it 'actionsが存在しない場合はそのまま返す' do
        no_actions = { 'decisions' => [] }
        result = service.enrich_actions_with_assignees(no_actions, user_mappings)
        expect(result).to eq(no_actions)
      end
    end

    context '無効なユーザーマッピングの場合' do
      it 'ステータスがcompletedでない場合はそのまま返す' do
        partial_mapping = user_mappings.merge(status: 'partial')
        result = service.enrich_actions_with_assignees(analysis_result, partial_mapping)
        expect(result).to eq(analysis_result)
      end

      it 'user_mappingsが存在しない場合はそのまま返す' do
        no_mappings = { status: 'completed', participants: [] }
        result = service.enrich_actions_with_assignees(analysis_result, no_mappings)
        expect(result).to eq(analysis_result)
      end
    end

    context 'assigneeが存在しないアクション' do
      let(:analysis_with_no_assignee) do
        {
          'actions' => [
            { 'task' => 'タスク1' },
            { 'task' => 'タスク2', 'assignee' => nil },
            { 'task' => 'タスク3', 'assignee' => '' }
          ]
        }
      end

      it 'assigneeのないアクションはスキップされる' do
        result = service.enrich_actions_with_assignees(analysis_with_no_assignee, user_mappings)
        
        result['actions'].each do |action|
          expect(action['notion_user_id']).to be_nil
          expect(action['slack_user_id']).to be_nil
        end
      end
    end
  end

  describe 'メール検索ロジック' do
    let(:participants) { ['user1@example.com', 'tanaka.taro@company.jp', 'mary.johnson@example.org'] }

    describe 'find_email_for_assignee' do
      it '完全なメールアドレス一致' do
        email = service.send(:find_email_for_assignee, 'user1@example.com', participants)
        expect(email).to eq('user1@example.com')
      end

      it '大文字小文字を無視した完全一致' do
        email = service.send(:find_email_for_assignee, 'USER1@EXAMPLE.COM', participants)
        expect(email).to eq('user1@example.com')
      end

      it '名前による部分一致' do
        email = service.send(:find_email_for_assignee, 'tanaka', participants)
        expect(email).to eq('tanaka.taro@company.jp')
      end

      it 'ユーザー名での部分一致' do
        email = service.send(:find_email_for_assignee, 'mary', participants)
        expect(email).to eq('mary.johnson@example.org')
      end

      it 'マッチしない場合はnil' do
        email = service.send(:find_email_for_assignee, 'nonexistent', participants)
        expect(email).to be_nil
      end

      it 'nil担当者の場合はnil' do
        email = service.send(:find_email_for_assignee, nil, participants)
        expect(email).to be_nil
      end

      it '空の参加者リストの場合はnil' do
        email = service.send(:find_email_for_assignee, 'user1', [])
        expect(email).to be_nil
      end

      it 'nil参加者リストの場合はnil' do
        email = service.send(:find_email_for_assignee, 'user1', nil)
        expect(email).to be_nil
      end
    end
  end

  describe 'ログ機能のテスト' do
    context 'マッピング結果のログ出力' do
      let(:successful_result) do
        {
          status: 'completed',
          participants: ['user1@example.com', 'user2@example.com', 'user3@example.com'],
          user_mappings: {
            slack: {
              'user1@example.com' => { id: 'U12345' },
              'user2@example.com' => { id: 'U67890' },
              'user3@example.com' => { error: 'user not found' }
            },
            notion: {
              'user1@example.com' => { id: 'notion-1' },
              'user3@example.com' => { id: 'notion-3' }
            }
          }
        }
      end

      before do
        allow(config).to receive(:user_mapping_enabled?).and_return(true)
        allow(config).to receive(:google_calendar_enabled).and_return(true)
        allow(config).to receive(:user_mapping_enabled).and_return(true)
        allow(MeetingTranscriptProcessor).to receive(:new).and_return(processor)
        allow(processor).to receive(:process_transcript).and_return(successful_result)
        allow(processor).to receive(:get_statistics).and_return(nil)
      end

      it '成功および失敗したマッピングを正しくカウント' do
        service.process_mapping(file_id, secrets)
        
        # 成功: Slack 2名 (user1, user2), Notion 2名 (user1, user3)
        expect(logger).to have_received(:info).with("Successfully mapped 2 Slack users and 2 Notion users")
      end

      it '未マップドユーザーを正しく特定' do
        service.process_mapping(file_id, secrets)
        
        # user2はNotionで未マップ、user3はSlackで未マップ
        expect(logger).to have_received(:info).with(/Unmapped users:.*user2@example\.com.*Notion.*user3@example\.com.*Slack/)
      end
    end
  end

  describe '境界値・エラーケース' do
    context 'プロセッサの再利用' do
      before do
        allow(config).to receive(:user_mapping_enabled?).and_return(true)
        allow(config).to receive(:google_calendar_enabled).and_return(true)
        allow(config).to receive(:user_mapping_enabled).and_return(true)
        allow(MeetingTranscriptProcessor).to receive(:new).and_return(processor)
        allow(processor).to receive(:process_transcript).and_return({ status: 'completed' })
      end

      it '同じサービスインスタンスで複数回呼び出されても正しく動作' do
        service.process_mapping(file_id, secrets)
        service.process_mapping('another-file-id', secrets)
        
        # プロセッサは一度だけ作成される
        expect(MeetingTranscriptProcessor).to have_received(:new).once
        expect(processor).to have_received(:process_transcript).twice
      end
    end

    context '大量のデータの処理' do
      let(:large_participants) { (1..100).map { |i| "user#{i}@example.com" } }
      let(:large_user_mappings) do
        {
          status: 'completed',
          participants: large_participants,
          user_mappings: {
            slack: large_participants.first(50).each_with_object({}) { |email, hash| hash[email] = { id: "U#{rand(10000)}" } },
            notion: large_participants.last(50).each_with_object({}) { |email, hash| hash[email] = { id: "notion-#{rand(10000)}" } }
          }
        }
      end

      before do
        allow(config).to receive(:user_mapping_enabled?).and_return(true)
        allow(config).to receive(:google_calendar_enabled).and_return(true)
        allow(config).to receive(:user_mapping_enabled).and_return(true)
        allow(MeetingTranscriptProcessor).to receive(:new).and_return(processor)
        allow(processor).to receive(:process_transcript).and_return(large_user_mappings)
        allow(processor).to receive(:get_statistics).and_return(nil)
      end

      it '大量のユーザーデータを正しく処理' do
        result = service.process_mapping(file_id, secrets)
        
        expect(result[:participants].length).to eq(100)
        expect(logger).to have_received(:info).with("Found 100 participants")
        expect(logger).to have_received(:info).with("Successfully mapped 50 Slack users and 50 Notion users")
      end
    end
  end

  describe 'デバッグログの出力' do
    before do
      allow(logger).to receive(:level).and_return(Logger::DEBUG)
    end

    context 'デバッグモードでのユーザー情報エンリッチ' do
      let(:analysis_result) do
        { 'actions' => [{ 'task' => 'テスト', 'assignee' => 'User One' }] }
      end

      let(:user_mappings) do
        {
          status: 'completed',
          participants: ['user1@example.com'],
          user_mappings: {
            slack: { 'user1@example.com' => { id: 'U12345', name: 'User One' } },
            notion: { 'user1@example.com' => { id: 'notion-user-1' } }
          }
        }
      end

      it 'デバッグレベルでSlackユーザー追加をログ出力' do
        service.enrich_actions_with_assignees(analysis_result, user_mappings)
        
        expect(logger).to have_received(:debug).with("Added Slack mention for User One: <@U12345>")
        expect(logger).to have_received(:debug).with("Added Notion user ID for User One: notion-user-1")
      end
    end
  end
end