# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/slack_options_provider'
require_relative '../../lib/google_drive_client'

RSpec.describe SlackOptionsProvider do
  let(:provider) { described_class.new }
  let(:user_id) { 'U123456789' }
  let(:mock_drive_client) { instance_double('GoogleDriveClient') }

  before do
    allow(GoogleDriveClient).to receive(:new).with(user_id).and_return(mock_drive_client)
  end

  describe '#provide_file_options' do
    context 'when user is authenticated' do
      let(:mock_files) do
        [
          {
            id: 'file1',
            name: 'Meeting Notes 2025-01-15.txt',
            mime_type: 'text/plain',
            modified_time: '2025-01-15T10:30:00Z',
            owner: 'John Doe',
            web_view_link: 'https://docs.google.com/file1'
          },
          {
            id: 'file2',
            name: '議事録_プロジェクト会議_とても長いファイル名でテストするためのサンプルファイルであり非常に長いファイル名の例でありさらに長くしたバージョンです.pdf',
            mime_type: 'application/pdf',
            modified_time: '2025-01-14T15:45:00Z',
            owner: 'Jane Smith',
            web_view_link: 'https://docs.google.com/file2'
          }
        ]
      end

      before do
        allow(mock_drive_client).to receive(:authorized?).and_return(true)
      end

      it 'returns formatted file options for search results' do
        allow(mock_drive_client).to receive(:search_files).with('meeting', 5).and_return(mock_files)

        result = provider.provide_file_options(user_id, 'meeting')

        expect(result).to have_key(:options)
        expect(result[:options]).to be_an(Array)
        expect(result[:options].length).to eq(2)

        first_option = result[:options].first
        expect(first_option[:text][:type]).to eq('plain_text')
        expect(first_option[:text][:text]).to eq('Meeting Notes 2025-01-15.txt')
        expect(first_option[:value]).to eq('file1')
      end

      it 'handles long file names correctly' do
        allow(mock_drive_client).to receive(:search_files).with('test', 5).and_return(mock_files)

        result = provider.provide_file_options(user_id, 'test')

        second_option = result[:options][1]
        expect(second_option[:text][:text]).to eq('議事録_プロジェクト会議_とても長いファイル名でテストするためのサンプルファイルであり非常に長いファイル名の例でありさらに長くしたバージョンです.pdf')
        expect(second_option[:value]).to eq('file2')
      end

      it 'handles empty query' do
        allow(mock_drive_client).to receive(:search_files).with('', 3).and_return(mock_files)

        result = provider.provide_file_options(user_id, '')

        expect(result[:options]).to be_an(Array)
        expect(result[:options].length).to eq(2)
      end

      it 'handles nil query' do
        allow(mock_drive_client).to receive(:search_files).with(nil, 3).and_return(mock_files)

        result = provider.provide_file_options(user_id, nil)

        expect(result[:options]).to be_an(Array)
        expect(result[:options].length).to eq(2)
      end

      it 'handles empty search results' do
        allow(mock_drive_client).to receive(:search_files).with('nonexistent', 5).and_return([])

        result = provider.provide_file_options(user_id, 'nonexistent')

        expect(result[:options]).to be_an(Array)
        expect(result[:options].length).to eq(1)
        expect(result[:options].first[:text][:text]).to include('「nonexistent」に一致するファイル')
        expect(result[:options].first[:value]).to eq('no_results')
      end

      it 'handles empty search results with no query' do
        allow(mock_drive_client).to receive(:search_files).with('', 3).and_return([])

        result = provider.provide_file_options(user_id, '')

        expect(result[:options]).to be_an(Array)
        expect(result[:options].length).to eq(1)
        expect(result[:options].first[:text][:text]).to include('ファイルが見つかりませんでした')
        expect(result[:options].first[:value]).to eq('no_results')
      end
    end

    context 'when user is not authenticated' do
      before do
        allow(mock_drive_client).to receive(:authorized?).and_return(false)
      end

      it 'returns unauthorized response' do
        result = provider.provide_file_options(user_id, 'meeting')

        expect(result[:options]).to be_an(Array)
        expect(result[:options].length).to eq(1)
        expect(result[:options].first[:text][:text]).to include('Google認証が必要です。/meet-transcript コマンドを再実行してください。')
        expect(result[:options].first[:value]).to eq('unauthorized')
      end
    end
  end


  describe 'private methods' do
    describe '#format_file_options' do
      let(:test_files) do
        [
          {
            id: 'file1',
            name: 'Test File.txt',
            modified_time: '2025-01-15T10:00:00Z'
          }
        ]
      end

      it 'formats files into proper Slack option structure' do
        result = provider.send(:format_file_options, test_files)

        expect(result).to have_key(:options)
        expect(result[:options].first).to have_key(:text)
        expect(result[:options].first).to have_key(:value)
        expect(result[:options].first[:text]).to have_key(:type)
        expect(result[:options].first[:text][:type]).to eq('plain_text')
      end
    end

    describe '#format_no_results_response' do
      it 'formats response for query with results' do
        result = provider.send(:format_no_results_response, 'test query')

        expect(result[:options].first[:text][:text]).to include('「test query」に一致するファイル')
      end

      it 'formats response for empty query' do
        result = provider.send(:format_no_results_response, '')

        expect(result[:options].first[:text][:text]).to include('ファイルが見つかりませんでした')
      end

      it 'formats response for nil query' do
        result = provider.send(:format_no_results_response, nil)

        expect(result[:options].first[:text][:text]).to include('ファイルが見つかりませんでした')
      end
    end

    describe '#format_unauthorized_response' do
      it 'returns proper unauthorized message structure' do
        result = provider.send(:format_unauthorized_response)

        expect(result[:options]).to be_an(Array)
        expect(result[:options].first[:value]).to eq('unauthorized')
        expect(result[:options].first[:text][:text]).to include('Google認証が必要です。/meet-transcript コマンドを再実行してください。')
      end
    end
  end
end