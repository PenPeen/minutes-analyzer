# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/google_drive_client'
require_relative '../../lib/google_oauth_client'

RSpec.describe GoogleDriveClient do
  let(:user_id) { 'U123456789' }
  let(:mock_oauth_client) { instance_double('GoogleOAuthClient') }
  let(:mock_drive_service) { instance_double('Google::Apis::DriveV3::DriveService') }
  let(:client) { described_class.new(user_id) }
  
  before do
    # Mock dependencies
    allow(GoogleOAuthClient).to receive(:new).and_return(mock_oauth_client)
    stub_const("#{described_class}::DRIVE_SERVICE", Google::Apis::DriveV3::DriveService)
    allow(Google::Apis::DriveV3::DriveService).to receive(:new).and_return(mock_drive_service)
    
    # Mock OAuth client methods
    allow(mock_oauth_client).to receive(:authenticated?).with(user_id).and_return(true)
    allow(mock_oauth_client).to receive(:get_tokens).with(user_id).and_return({
      access_token: 'test_access_token',
      refresh_token: 'test_refresh_token'
    })
    
    # Mock drive service
    allow(mock_drive_service).to receive(:authorization=)
    
    # Mock Signet OAuth2 client
    mock_signet_client = double('Signet::OAuth2::Client')
    allow(Signet::OAuth2::Client).to receive(:new).and_return(mock_signet_client)
    
    # Mock secrets fetching to use environment variables in tests
    allow_any_instance_of(described_class).to receive(:fetch_from_secrets).with('GOOGLE_CLIENT_ID').and_return('test_client_id')
    allow_any_instance_of(described_class).to receive(:fetch_from_secrets).with('GOOGLE_CLIENT_SECRET').and_return('test_client_secret')
    allow_any_instance_of(described_class).to receive(:fetch_from_secrets).with('GOOGLE_REDIRECT_URI').and_return('http://localhost')
  end

  describe '#initialize' do
    it 'sets up the client with user ID' do
      expect(client.instance_variable_get(:@slack_user_id)).to eq(user_id)
    end

    it 'creates OAuth and Drive service clients' do
      expect(GoogleOAuthClient).to have_received(:new)
      expect(Google::Apis::DriveV3::DriveService).to have_received(:new)
    end
  end

  describe '#search_files' do
    let(:mock_files) do
      [
        double(
          id: 'file1',
          name: 'Meeting Notes 2025.txt',
          mime_type: 'text/plain',
          modified_time: '2025-01-15T10:00:00Z',
          owners: [double(display_name: 'John Doe')],
          web_view_link: 'https://docs.google.com/file1'
        ),
        double(
          id: 'file2',
          name: '議事録_プロジェクト会議.pdf',
          mime_type: 'application/pdf',
          modified_time: '2025-01-14T15:30:00Z',
          owners: [double(display_name: 'Jane Smith')],
          web_view_link: 'https://docs.google.com/file2'
        )
      ]
    end

    let(:mock_response) { double(files: mock_files) }

    context 'when user is authorized' do
      before do
        allow(mock_oauth_client).to receive(:authenticated?).with(user_id).and_return(true)
      end

      it 'searches files successfully' do
        allow(mock_drive_service).to receive(:list_files).and_return(mock_response)

        result = client.search_files('meeting')

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result.first[:id]).to eq('file1')
        expect(result.first[:name]).to eq('Meeting Notes 2025.txt')
        expect(result.first[:owner]).to eq('John Doe')
      end

      it 'uses correct search parameters' do
        expect(mock_drive_service).to receive(:list_files).with(
          hash_including(
            page_size: 20,
            fields: 'files(id,name,mimeType,modifiedTime,owners,webViewLink)',
            order_by: 'modifiedTime desc',
            supports_all_drives: true,
            include_items_from_all_drives: true
          )
        ).and_return(mock_response)

        client.search_files('test query', 20)
      end

      it 'handles empty search results' do
        empty_response = double(files: [])
        allow(mock_drive_service).to receive(:list_files).and_return(empty_response)

        result = client.search_files('nonexistent')

        expect(result).to eq([])
      end

      it 'handles authorization errors with retry' do
        auth_error = Google::Apis::AuthorizationError.new('Invalid token')
        
        # First call fails with auth error
        allow(mock_drive_service).to receive(:list_files).and_raise(auth_error)
        
        # Mock refresh_authorization
        allow(mock_oauth_client).to receive(:refresh_access_token).with('test_refresh_token')
          .and_return({ access_token: 'new_access_token', refresh_token: 'test_refresh_token' })
        allow(mock_oauth_client).to receive(:save_tokens)
        
        result = client.search_files('meeting')

        expect(result).to be_empty # retry_search_files returns empty when already retried
      end

      it 'handles API errors gracefully' do
        api_error = Google::Apis::Error.new('API quota exceeded')
        allow(mock_drive_service).to receive(:list_files).and_raise(api_error)

        result = client.search_files('meeting')

        expect(result).to eq([])
      end

      it 'respects file limit parameter' do
        expect(mock_drive_service).to receive(:list_files).with(
          hash_including(page_size: 5)
        ).and_return(mock_response)

        client.search_files('test', 5)
      end
    end

    context 'when user is not authorized' do
      before do
        allow(mock_oauth_client).to receive(:authenticated?).with(user_id).and_return(false)
      end

      it 'returns empty array' do
        result = client.search_files('meeting')
        expect(result).to eq([])
      end
    end
  end

  describe '#escape_query' do
    it 'escapes single quotes' do
      result = client.send(:escape_query, "user's file")
      expect(result).to eq("user\\'s file")
    end

    it 'escapes backslashes' do
      result = client.send(:escape_query, 'path\\with\\backslashes')
      expect(result).to eq('path\\\\with\\\\backslashes')
    end

    it 'escapes both backslashes and quotes' do
      result = client.send(:escape_query, "user's path\\file")
      expect(result).to eq("user\\'s path\\\\file")
    end

    it 'handles empty strings' do
      result = client.send(:escape_query, '')
      expect(result).to eq('')
    end

    it 'handles normal text without special characters' do
      result = client.send(:escape_query, 'normal file name')
      expect(result).to eq('normal file name')
    end
  end

  describe '#build_search_query' do
    it 'builds query for user search with file name' do
      query = client.send(:build_search_query, 'meeting notes')
      
      expect(query).to include("name contains 'meeting notes'")
      expect(query).to include('trashed = false')
      expect(query).to include('mimeType =')
    end

    it 'builds query for empty search with meeting keywords' do
      query = client.send(:build_search_query, '')
      
      expect(query).to include('議事録')
      expect(query).to include('meeting')
      expect(query).to include('minutes')
      expect(query).to include('trashed = false')
    end

    it 'includes proper MIME types' do
      query = client.send(:build_search_query, 'test')
      
      expect(query).to include("application/vnd.google-apps.document")
      expect(query).to include("text/plain")
      expect(query).to include("application/pdf")
    end
  end

  describe '#get_file_info' do
    let(:mock_file_info) do
      double(
        id: 'file123',
        name: 'Test Document',
        mime_type: 'application/vnd.google-apps.document',
        modified_time: '2025-01-15T10:00:00Z',
        size: 1024,
        owners: [double(display_name: 'John Doe')],
        web_view_link: 'https://docs.google.com/document/file123',
        parents: ['parent_folder_id']
      )
    end

    context 'when user is authorized' do
      before do
        allow(mock_oauth_client).to receive(:authenticated?).with(user_id).and_return(true)
      end

      it 'retrieves file info successfully' do
        allow(mock_drive_service).to receive(:get_file).with(
          'file123',
          hash_including(
            fields: 'id,name,mimeType,modifiedTime,size,owners,webViewLink,parents',
            supports_all_drives: true
          )
        ).and_return(mock_file_info)

        result = client.get_file_info('file123')

        expect(result).to eq(mock_file_info)
      end

      it 'handles API errors gracefully' do
        allow(mock_drive_service).to receive(:get_file).and_raise(Google::Apis::Error.new('File not found'))

        result = client.get_file_info('nonexistent_file')

        expect(result).to be_nil
      end
    end

    context 'when user is not authorized' do
      before do
        allow(mock_oauth_client).to receive(:authenticated?).with(user_id).and_return(false)
      end

      it 'returns nil' do
        result = client.get_file_info('file123')
        expect(result).to be_nil
      end
    end
  end

  describe '#authorized?' do
    it 'returns true when user is authenticated' do
      allow(mock_oauth_client).to receive(:authenticated?).with(user_id).and_return(true)
      
      expect(client.authorized?).to be true
    end

    it 'returns false when user is not authenticated' do
      allow(mock_oauth_client).to receive(:authenticated?).with(user_id).and_return(false)
      
      expect(client.authorized?).to be false
    end
  end

  describe 'private methods' do
    describe '#refresh_authorization' do
      context 'when refresh token is available' do
        let(:new_tokens) { { access_token: 'new_token', refresh_token: 'refresh_token' } }

        it 'refreshes tokens successfully' do
          allow(mock_oauth_client).to receive(:refresh_access_token)
            .with('test_refresh_token')
            .and_return(new_tokens)
          allow(mock_oauth_client).to receive(:save_tokens).with(user_id, new_tokens)

          client.send(:refresh_authorization)

          expect(mock_oauth_client).to have_received(:refresh_access_token).with('test_refresh_token')
          expect(mock_oauth_client).to have_received(:save_tokens).with(user_id, new_tokens)
        end

        it 'handles failed token refresh' do
          allow(mock_oauth_client).to receive(:refresh_access_token)
            .with('test_refresh_token')
            .and_return(nil)

          expect {
            client.send(:refresh_authorization)
          }.not_to raise_error

          expect(mock_oauth_client).not_to have_received(:save_tokens)
        end

        it 'handles invalid new tokens' do
          invalid_tokens = { access_token: nil }
          allow(mock_oauth_client).to receive(:refresh_access_token)
            .with('test_refresh_token')
            .and_return(invalid_tokens)

          expect {
            client.send(:refresh_authorization)
          }.not_to raise_error

          expect(mock_oauth_client).not_to have_received(:save_tokens)
        end
      end

      context 'when no tokens available' do
        it 'returns early without attempting refresh' do
          # Override the before block's mock for this specific test
          allow(mock_oauth_client).to receive(:get_tokens).with(user_id).and_return(nil)

          client.send(:refresh_authorization)

          expect(mock_oauth_client).not_to have_received(:refresh_access_token)
        end
      end
    end
  end
end