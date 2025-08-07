require 'spec_helper'
require_relative '../lib/meeting_transcript_processor'

RSpec.describe MeetingTranscriptProcessor do
  let(:config) do
    {
      google_calendar_enabled: true,
      user_mapping_enabled: true,
      parallel_processing: false, # Disable for easier testing
      google_service_account_json: '{"type": "service_account"}',
      slack_bot_token: 'xoxb-test',
      notion_api_key: 'secret_test'
    }
  end
  
  let(:processor) { described_class.new(config) }
  let(:file_id) { 'test_file_123' }
  
  before do
    # Mock dependencies
    allow_any_instance_of(GoogleDriveCalendarBridge).to receive(:initialize)
    allow_any_instance_of(SlackUserManager).to receive(:initialize)
    allow_any_instance_of(NotionUserManager).to receive(:initialize)
  end
  
  describe '#initialize' do
    it 'initializes with configuration' do
      expect { processor }.not_to raise_error
    end
    
    it 'initializes clients based on config' do
      expect(processor.calendar_bridge).to be_present
      expect(processor.slack_manager).to be_present
      expect(processor.notion_manager).to be_present
    end
    
    context 'with disabled features' do
      let(:config) do
        {
          google_calendar_enabled: false,
          user_mapping_enabled: false
        }
      end
      
      it 'does not initialize disabled clients' do
        expect(processor.calendar_bridge).to be_nil
        expect(processor.slack_manager).to be_nil
        expect(processor.notion_manager).to be_nil
      end
    end
  end
  
  describe '#process_transcript' do
    let(:meeting_info) do
      {
        event: double('event',
          id: 'event123',
          summary: 'Test Meeting',
          start: double('start', date_time: '2025-01-15T10:00:00Z'),
          end: double('end', date_time: '2025-01-15T11:00:00Z'),
          organizer: double('organizer', email: 'organizer@example.com'),
          attendees: [],
          location: 'Conference Room',
          recurring_event_id: nil
        ),
        participants: ['user1@example.com', 'user2@example.com'],
        file_info: {
          id: file_id,
          name: 'meeting.txt',
          created_time: '2025-01-15T11:05:00Z'
        }
      }
    end
    
    let(:slack_mappings) do
      {
        'user1@example.com' => { id: 'U1', name: 'user1' },
        'user2@example.com' => { id: 'U2', name: 'user2' }
      }
    end
    
    let(:notion_mappings) do
      {
        'user1@example.com' => { id: 'notion-u1', name: 'User One' },
        'user2@example.com' => { id: 'notion-u2', name: 'User Two' }
      }
    end
    
    before do
      allow(processor.calendar_bridge).to receive(:find_meeting_with_participants)
        .with(file_id)
        .and_return(meeting_info)
      
      allow(processor.slack_manager).to receive(:batch_lookup_users)
        .and_return(slack_mappings)
      
      allow(processor.notion_manager).to receive(:batch_find_users)
        .and_return(notion_mappings)
    end
    
    it 'processes transcript successfully' do
      result = processor.process_transcript(file_id)
      
      expect(result[:status]).to eq('completed')
      expect(result[:file_id]).to eq(file_id)
      expect(result[:meeting]).to be_present
      expect(result[:participants]).to eq(['user1@example.com', 'user2@example.com'])
    end
    
    it 'maps participants to Slack and Notion users' do
      result = processor.process_transcript(file_id)
      
      expect(result[:user_mappings][:slack]).to eq(slack_mappings)
      expect(result[:user_mappings][:notion]).to eq(notion_mappings)
    end
    
    it 'generates Slack mentions' do
      result = processor.process_transcript(file_id)
      
      expect(result[:user_mappings][:slack_mentions]).to include('<@U1>', '<@U2>')
    end
    
    context 'when meeting not found' do
      before do
        allow(processor.calendar_bridge).to receive(:find_meeting_with_participants)
          .and_return(nil)
      end
      
      it 'adds error and continues processing' do
        result = processor.process_transcript(file_id)
        
        expect(result[:status]).to eq('completed')
        expect(result[:errors]).to include("Meeting not found for file ID: #{file_id}")
      end
    end
    
    context 'when error occurs' do
      before do
        allow(processor.calendar_bridge).to receive(:find_meeting_with_participants)
          .and_raise(StandardError, 'Test error')
      end
      
      it 'handles errors gracefully' do
        result = processor.process_transcript(file_id)
        
        expect(result[:status]).to eq('failed')
        expect(result[:errors]).to include('Test error')
      end
    end
  end
  
  describe '#batch_process_transcripts' do
    let(:file_ids) { ['file1', 'file2', 'file3'] }
    
    before do
      allow(processor).to receive(:process_transcript).and_return({ status: 'completed' })
    end
    
    it 'processes multiple transcripts' do
      results = processor.batch_process_transcripts(file_ids)
      
      expect(results.keys).to match_array(file_ids)
      expect(results.values.all? { |r| r[:status] == 'completed' }).to be true
    end
  end
  
  describe '#assign_action_owners' do
    let(:actions) do
      [
        { 'task' => 'Task 1', 'assignee_email' => 'user1@example.com' },
        { 'task' => 'Task 2', 'assignee_email' => 'user2@example.com' },
        { 'task' => 'Task 3', 'assignee_email' => nil }
      ]
    end
    
    let(:user_mappings) do
      {
        notion: {
          'user1@example.com' => { id: 'notion-u1' },
          'user2@example.com' => { id: 'notion-u2' }
        }
      }
    end
    
    it 'assigns Notion user IDs to actions' do
      updated_actions = processor.assign_action_owners(actions, user_mappings)
      
      expect(updated_actions[0]['notion_user_id']).to eq('notion-u1')
      expect(updated_actions[0]['auto_assigned']).to be true
      expect(updated_actions[1]['notion_user_id']).to eq('notion-u2')
      expect(updated_actions[2]['notion_user_id']).to be_nil
    end
  end
  
  describe '#get_statistics' do
    before do
      # Simulate some processing
      processor.instance_variable_set(:@statistics, {
        processed: 10,
        successful: 8,
        failed: 2,
        processing_time: 15.5
      })
    end
    
    it 'returns processing statistics' do
      stats = processor.get_statistics
      
      expect(stats[:total_processed]).to eq(10)
      expect(stats[:successful]).to eq(8)
      expect(stats[:failed]).to eq(2)
      expect(stats[:success_rate]).to eq(80.0)
      expect(stats[:average_processing_time]).to eq(1.55)
    end
  end
  
  describe '#cleanup' do
    context 'with parallel processing enabled' do
      let(:config) { super().merge(parallel_processing: true) }
      
      it 'shuts down thread pool' do
        executor = processor.instance_variable_get(:@executor)
        expect(executor).to receive(:shutdown)
        expect(executor).to receive(:wait_for_termination).with(10)
        
        processor.cleanup
      end
    end
  end
end