require 'spec_helper'
require_relative '../lib/google_drive_client'
require 'google/apis/drive_v3'

RSpec.describe GoogleDriveClient do
  let(:logger) { instance_double(Logger, info: nil, error: nil, warn: nil) }
  let(:credentials_json) do
    {
      "type": "service_account",
      "project_id": "test-project",
      "private_key_id": "key-id",
      "private_key": "-----BEGIN PRIVATE KEY-----\ntest_key\n-----END PRIVATE KEY-----",
      "client_email": "test@test-project.iam.gserviceaccount.com",
      "client_id": "123456789",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/test%40test-project.iam.gserviceaccount.com"
    }.to_json
  end
  let(:client) { described_class.new(credentials_json, logger) }

  describe '#get_file_content' do
    let(:file_id) { '1234567890abcdef' }
    let(:mock_drive_service) { instance_double(Google::Apis::DriveV3::DriveService) }
    let(:mock_file) do
      Google::Apis::DriveV3::File.new(
        id: file_id,
        name: 'test_meeting.txt',
        size: 1024,
        mime_type: 'text/plain'
      )
    end

    before do
      allow(Google::Apis::DriveV3::DriveService).to receive(:new).and_return(mock_drive_service)
      allow(mock_drive_service).to receive(:authorization=)
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(double(apply!: nil))
    end

    context 'when file is successfully retrieved' do
      let(:file_content) { "2025年1月15日\n\n新機能リリース進捗確認ミーティング\n..." }

      before do
        # Mock get_file with different parameter combinations
        allow(mock_drive_service).to receive(:get_file) do |file_id_arg, options|
          if options[:fields] == 'id, name, size, mimeType'
            mock_file
          elsif options.key?(:download_dest)
            options[:download_dest].write(file_content)
          end
        end
        
        # Mock export_file for text/plain
        allow(mock_drive_service).to receive(:export_file) do |id, mime_type, options|
          options[:download_dest].write(file_content)
        end
      end

      it 'returns the file content' do
        result = client.get_file_content(file_id)
        expect(result).to eq([file_content, 'test_meeting.txt'])
      end

      it 'logs file information' do
        expect(logger).to receive(:info).with("Fetching file content from Google Drive: #{file_id}")
        expect(logger).to receive(:info).with(/File info - Name: test_meeting.txt/)
        expect(logger).to receive(:info).with(/Successfully downloaded file content/)
        
        client.get_file_content(file_id)
      end
    end

    context 'when file is too large' do
      before do
        large_file = Google::Apis::DriveV3::File.new(
          id: file_id,
          name: 'large_file.txt',
          size: 150_000_000,  # 150MB
          mime_type: 'text/plain'
        )
        
        allow(mock_drive_service).to receive(:get_file)
          .with(file_id, fields: 'id, name, size, mimeType')
          .and_return(large_file)
      end

      it 'raises an error' do
        expect { client.get_file_content(file_id) }.to raise_error(/File too large/)
      end
    end

    context 'when export fails and falls back to direct download' do
      let(:file_content) { "Meeting transcript content" }
      let(:unknown_mime_file) do 
        Google::Apis::DriveV3::File.new(
          id: file_id,
          name: 'test_meeting.unknown',
          size: 1000,
          mime_type: 'application/octet-stream'  # Unknown MIME type to trigger fallback
        )
      end

      before do
        # Mock get_file with different parameter combinations
        allow(mock_drive_service).to receive(:get_file) do |file_id_arg, options|
          if options[:fields] == 'id, name, size, mimeType'
            unknown_mime_file
          elsif options.key?(:download_dest)
            options[:download_dest].write(file_content)
          end
        end
        
        # Mock export_file to fail
        allow(mock_drive_service).to receive(:export_file)
          .and_raise(Google::Apis::ClientError.new("Export not supported"))
      end

      it 'falls back to direct download and returns content' do
        expect(logger).to receive(:warn).with(/Export failed, trying direct download/)
        
        result = client.get_file_content(file_id)
        expect(result).to eq([file_content, 'test_meeting.unknown'])
      end
    end

    context 'when Google Drive API returns an error' do
      before do
        allow(mock_drive_service).to receive(:get_file)
          .and_raise(Google::Apis::AuthorizationError.new("Unauthorized"))
      end

      it 'raises an error with details' do
        expect { client.get_file_content(file_id) }.to raise_error(/Failed to fetch file from Google Drive/)
      end

      it 'logs the error' do
        expect(logger).to receive(:error).with(/Google Drive API error/)
        
        expect { client.get_file_content(file_id) }.to raise_error
      end
    end
  end
end