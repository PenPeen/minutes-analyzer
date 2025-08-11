require 'spec_helper'
require_relative '../lib/google_calendar_client'
require 'google/apis/calendar_v3'
require 'google/apis/drive_v3'

RSpec.describe GoogleCalendarClient do
  let(:service_account_json) { '{"type": "service_account", "project_id": "test"}' }
  let(:client) { described_class.new(service_account_json) }
  let(:mock_service) { instance_double(Google::Apis::CalendarV3::CalendarService) }
  let(:mock_drive_service) { instance_double(Google::Apis::DriveV3::DriveService) }
  
  before do
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(double('creds'))
    allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(mock_service)
    allow(mock_service).to receive(:authorization=)
  end
  
  describe '#initialize' do
    it 'initializes with service account JSON' do
      expect { client }.not_to raise_error
    end
    
    it 'raises error without service account JSON' do
      expect { described_class.new(nil) }.to raise_error('Service account JSON is required')
    end
  end
  
  describe '#find_meeting_by_recording_file' do
    let(:file_id) { 'test_file_id_123' }
    let(:drive_client) { mock_drive_service }
    let(:file_info) do
      double('file_info',
        created_time: '2025-01-15T10:00:00Z',
        name: '2025年1月15日_新機能リリース進捗確認ミーティング.txt'
      )
    end
    
    let(:event_with_attachment) do
      double('event',
        id: 'event123',
        summary: '新機能リリース進捗確認ミーティング',
        attachments: [
          double('attachment', file_id: file_id, file_url: nil)
        ],
        start: double('start', date_time: '2025-01-15T09:00:00Z'),
        end: double('end', date_time: '2025-01-15T10:00:00Z')
      )
    end
    
    before do
      allow(drive_client).to receive(:get_file).and_return(file_info)
      allow(mock_service).to receive(:list_events).and_return(
        double('response', items: [event_with_attachment], next_page_token: nil)
      )
    end
    
    it 'finds meeting by attachment file ID' do
      result = client.find_meeting_by_recording_file(file_id, drive_client)
      expect(result).to eq(event_with_attachment)
    end
  end
  
  describe '#get_event_participants' do
    let(:event_id) { 'event123' }
    let(:event) do
      double('event',
        attendees: [
          double('attendee', email: 'user1@example.com', resource: false),
          double('attendee', email: 'user2@example.com', resource: false),
          double('attendee', email: 'room@resource.calendar.google.com', resource: true)
        ]
      )
    end
    
    before do
      allow(mock_service).to receive(:get_event).with('primary', event_id).and_return(event)
    end
    
    it 'returns participant emails excluding resources' do
      participants = client.get_event_participants(event_id)
      expect(participants).to eq(['user1@example.com', 'user2@example.com'])
    end
    
    it 'filters out resource attendees' do
      participants = client.get_event_participants(event_id)
      expect(participants).not_to include('room@resource.calendar.google.com')
    end
  end
  
  describe '#list_events' do
    let(:events) do
      [
        double('event1', id: '1'),
        double('event2', id: '2')
      ]
    end
    
    before do
      allow(mock_service).to receive(:list_events).and_return(
        double('response', items: events, next_page_token: nil)
      )
    end
    
    it 'returns list of events' do
      result = client.list_events('primary')
      expect(result).to eq(events)
    end
    
    context 'with pagination' do
      let(:page1_events) { [double('event1', id: '1')] }
      let(:page2_events) { [double('event2', id: '2')] }
      
      before do
        allow(mock_service).to receive(:list_events).and_return(
          double('response1', items: page1_events, next_page_token: 'token123'),
          double('response2', items: page2_events, next_page_token: nil)
        )
      end
      
      it 'handles pagination correctly' do
        result = client.list_events('primary')
        expect(result.size).to eq(2)
      end
    end
  end
end