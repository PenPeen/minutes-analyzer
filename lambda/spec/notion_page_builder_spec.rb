require 'spec_helper'
require 'logger'
require_relative '../lib/notion_page_builder'

RSpec.describe NotionPageBuilder do
  let(:logger) { instance_double(Logger, info: nil, error: nil, warn: nil) }
  let(:task_database_id) { 'task-db-123' }
  let(:database_id) { 'meeting-db-456' }
  let(:builder) { described_class.new(task_database_id, logger) }

  describe '#build_properties' do
    context 'when meeting_summary has date and title' do
      let(:analysis_result) do
        {
          'meeting_summary' => {
            'date' => '2025-01-15',
            'title' => '新機能リリース進捗確認MTG',
            'duration_minutes' => 30,
            'participants' => ['田中太郎', '山田花子']
          }
        }
      end

      it 'creates title with date prefix' do
        properties = builder.build_properties(analysis_result)
        
        expect(properties['タイトル']['title'][0]['text']['content']).to eq('2025-01-15 新機能リリース進捗確認MTG')
      end

      it 'preserves other properties' do
        properties = builder.build_properties(analysis_result)
        
        expect(properties['日付']).not_to be_nil
        expect(properties['所要時間']).not_to be_nil
        expect(properties['参加者']).not_to be_nil
      end
    end

    context 'when meeting_summary has no date' do
      let(:analysis_result) do
        {
          'meeting_summary' => {
            'title' => '緊急対応会議'
          }
        }
      end

      it 'uses current date as prefix' do
        allow(Time).to receive(:now).and_return(Time.new(2025, 1, 20, 10, 0, 0))
        
        properties = builder.build_properties(analysis_result)
        
        expect(properties['タイトル']['title'][0]['text']['content']).to eq('2025-01-20 緊急対応会議')
      end
    end

    context 'when meeting_summary has no title' do
      let(:analysis_result) do
        {
          'meeting_summary' => {
            'date' => '2025-01-15'
          }
        }
      end

      it 'uses default title with date prefix' do
        properties = builder.build_properties(analysis_result)
        
        expect(properties['タイトル']['title'][0]['text']['content']).to eq('2025-01-15 Untitled Meeting')
      end
    end

    context 'when meeting_summary is empty' do
      let(:analysis_result) do
        {
          'meeting_summary' => {}
        }
      end

      it 'uses current date and default title' do
        allow(Time).to receive(:now).and_return(Time.new(2025, 1, 20, 10, 0, 0))
        
        properties = builder.build_properties(analysis_result)
        
        expect(properties['タイトル']['title'][0]['text']['content']).to eq('2025-01-20 Untitled Meeting')
      end
    end

    context 'when analysis_result is nil' do
      let(:analysis_result) { nil }

      it 'handles nil gracefully' do
        allow(Time).to receive(:now).and_return(Time.new(2025, 1, 20, 10, 0, 0))
        
        properties = builder.build_properties(analysis_result)
        
        expect(properties['タイトル']['title'][0]['text']['content']).to eq('2025-01-20 Untitled Meeting')
      end
    end
  end

  describe '#build_meeting_page' do
    let(:analysis_result) do
      {
        'meeting_summary' => {
          'date' => '2025-01-15',
          'title' => '定例会議'
        }
      }
    end

    it 'includes date-prefixed title in the page properties' do
      page_data = builder.build_meeting_page(analysis_result, database_id)
      
      title_content = page_data[:properties]['タイトル']['title'][0]['text']['content']
      expect(title_content).to eq('2025-01-15 定例会議')
    end

    it 'sets correct parent database' do
      page_data = builder.build_meeting_page(analysis_result, database_id)
      
      expect(page_data[:parent][:database_id]).to eq(database_id)
    end
  end
end