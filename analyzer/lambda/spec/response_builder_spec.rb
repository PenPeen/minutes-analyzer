require 'spec_helper'
require_relative '../lib/response_builder'
require 'json'

RSpec.describe ResponseBuilder do
  describe '.error_response' do
    context '基本的なエラーレスポンス' do
      it 'ステータスコードとエラーメッセージを含む適切なレスポンスを返す' do
        result = ResponseBuilder.error_response(400, 'Bad Request')
        
        expect(result[:statusCode]).to eq(400)
        
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Bad Request')
        expect(body).not_to have_key('details')
      end
    end

    context '詳細情報付きエラーレスポンス' do
      it 'ステータスコード、エラーメッセージ、詳細情報を含むレスポンスを返す' do
        details = { field: 'file_id', reason: 'missing required field' }
        result = ResponseBuilder.error_response(400, 'Validation failed', details)
        
        expect(result[:statusCode]).to eq(400)
        
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Validation failed')
        expect(body['details']).to eq({
          'field' => 'file_id',
          'reason' => 'missing required field'
        })
      end
    end

    context '様々なHTTPステータスコード' do
      it '500エラーが正しく処理される' do
        result = ResponseBuilder.error_response(500, 'Internal Server Error')
        
        expect(result[:statusCode]).to eq(500)
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Internal Server Error')
      end

      it '401エラーが正しく処理される' do
        result = ResponseBuilder.error_response(401, 'Unauthorized')
        
        expect(result[:statusCode]).to eq(401)
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Unauthorized')
      end

      it '404エラーが正しく処理される' do
        result = ResponseBuilder.error_response(404, 'Not Found')
        
        expect(result[:statusCode]).to eq(404)
        body = JSON.parse(result[:body])
        expect(body['error']).to eq('Not Found')
      end
    end

    context 'エラーメッセージの種類' do
      it '長いエラーメッセージが正しく処理される' do
        long_message = 'a' * 1000
        result = ResponseBuilder.error_response(400, long_message)
        
        body = JSON.parse(result[:body])
        expect(body['error']).to eq(long_message)
      end

      it '日本語エラーメッセージが正しく処理される' do
        japanese_message = 'リクエストが無効です'
        result = ResponseBuilder.error_response(400, japanese_message)
        
        body = JSON.parse(result[:body])
        expect(body['error']).to eq(japanese_message)
      end

      it '特殊文字を含むエラーメッセージが正しく処理される' do
        special_message = 'Error: "field" is missing (required)'
        result = ResponseBuilder.error_response(400, special_message)
        
        body = JSON.parse(result[:body])
        expect(body['error']).to eq(special_message)
      end
    end

    context '詳細情報の様々な形式' do
      it '複雑な詳細オブジェクトが正しく処理される' do
        complex_details = {
          validation_errors: [
            { field: 'file_id', message: 'required' },
            { field: 'file_name', message: 'invalid format' }
          ],
          timestamp: '2025-01-15T10:00:00Z',
          request_id: '12345'
        }
        
        result = ResponseBuilder.error_response(422, 'Validation failed', complex_details)
        
        body = JSON.parse(result[:body])
        expect(body['details']['validation_errors']).to be_an(Array)
        expect(body['details']['validation_errors'].length).to eq(2)
        expect(body['details']['timestamp']).to eq('2025-01-15T10:00:00Z')
      end

      it '空の詳細オブジェクトが正しく処理される' do
        result = ResponseBuilder.error_response(400, 'Error', {})
        
        body = JSON.parse(result[:body])
        expect(body['details']).to eq({})
      end
    end
  end

  describe '.success_response' do
    let(:analysis_result) do
      {
        'meeting_summary' => {
          'title' => 'テスト会議',
          'date' => '2025-01-15',
          'duration_minutes' => 30
        },
        'decisions' => [
          { 'content' => 'テスト決定事項' }
        ],
        'actions' => [
          { 'task' => 'テストタスク', 'assignee' => '担当者' }
        ]
      }
    end

    context '統合結果なしの基本レスポンス' do
      let(:integration_results) { { slack: nil, notion: nil } }

      it '200ステータスと分析結果を含む適切なレスポンスを返す' do
        result = ResponseBuilder.success_response(analysis_result, integration_results)
        
        expect(result[:statusCode]).to eq(200)
        expect(result[:headers]).to eq({ 'Content-Type': 'application/json' })
        
        body = JSON.parse(result[:body])
        expect(body['message']).to eq('Analysis complete.')
        expect(body['analysis']).to eq(analysis_result)
        expect(body['integrations']['slack']).to eq('not_sent')
        expect(body['integrations']['notion']).to eq('not_created')
      end
    end

    context 'Slack統合成功の場合' do
      let(:slack_result) { { success: true, response_code: '200', message_ts: '1642234567.123' } }
      let(:integration_results) { { slack: slack_result, notion: nil } }

      it 'Slack統合成功状態を含むレスポンスを返す' do
        result = ResponseBuilder.success_response(analysis_result, integration_results)
        
        body = JSON.parse(result[:body])
        expect(body['integrations']['slack']).to eq('sent')
        expect(body['slack_notification']).to eq({
          'success' => true,
          'response_code' => '200',
          'message_ts' => '1642234567.123'
        })
      end
    end

    context 'Slack統合失敗の場合' do
      let(:slack_result) { { success: false, response_code: '404', error: 'channel_not_found' } }
      let(:integration_results) { { slack: slack_result, notion: nil } }

      it 'Slack統合失敗状態を含むレスポンスを返す' do
        result = ResponseBuilder.success_response(analysis_result, integration_results)
        
        body = JSON.parse(result[:body])
        expect(body['integrations']['slack']).to eq('not_sent')
        expect(body['slack_notification']).to eq({
          'success' => false,
          'response_code' => '404',
          'error' => 'channel_not_found'
        })
      end
    end

    context 'Notion統合成功の場合' do
      let(:notion_result) { { success: true, page_id: 'notion-page-123', url: 'https://notion.so/page-123' } }
      let(:integration_results) { { slack: nil, notion: notion_result } }

      it 'Notion統合成功状態を含むレスポンスを返す' do
        result = ResponseBuilder.success_response(analysis_result, integration_results)
        
        body = JSON.parse(result[:body])
        expect(body['integrations']['notion']).to eq('created')
        expect(body['notion_result']).to eq({
          'success' => true,
          'page_id' => 'notion-page-123',
          'url' => 'https://notion.so/page-123'
        })
      end
    end

    context 'Notion統合失敗の場合' do
      let(:notion_result) { { success: false, error: 'database_not_found' } }
      let(:integration_results) { { slack: nil, notion: notion_result } }

      it 'Notion統合失敗状態を含むレスポンスを返す' do
        result = ResponseBuilder.success_response(analysis_result, integration_results)
        
        body = JSON.parse(result[:body])
        expect(body['integrations']['notion']).to eq('not_created')
        expect(body['notion_result']).to eq({
          'success' => false,
          'error' => 'database_not_found'
        })
      end
    end

    context '両方の統合が成功した場合' do
      let(:slack_result) { { success: true, response_code: '200' } }
      let(:notion_result) { { success: true, page_id: 'notion-123' } }
      let(:integration_results) { { slack: slack_result, notion: notion_result } }

      it '両方の統合成功状態を含むレスポンスを返す' do
        result = ResponseBuilder.success_response(analysis_result, integration_results)
        
        body = JSON.parse(result[:body])
        expect(body['integrations']['slack']).to eq('sent')
        expect(body['integrations']['notion']).to eq('created')
        expect(body['slack_notification']).to eq({ 'success' => true, 'response_code' => '200' })
        expect(body['notion_result']).to eq({ 'success' => true, 'page_id' => 'notion-123' })
      end
    end

    context 'ユーザーマッピング結果付きの場合' do
      let(:integration_results) { { slack: nil, notion: nil } }
      let(:user_mappings) do
        {
          status: 'completed',
          participants: ['user@example.com'],
          user_mappings: {
            slack: { 'user@example.com' => { id: 'U12345', name: 'Test User' } },
            notion: { 'user@example.com' => { id: 'notion-user-id' } }
          }
        }
      end

      it 'ユーザーマッピング結果を含むレスポンスを返す' do
        result = ResponseBuilder.success_response(analysis_result, integration_results, user_mappings)
        
        body = JSON.parse(result[:body])
        expect(body['user_mappings']).to eq({
          'status' => 'completed',
          'participants' => ['user@example.com'],
          'user_mappings' => {
            'slack' => { 'user@example.com' => { 'id' => 'U12345', 'name' => 'Test User' } },
            'notion' => { 'user@example.com' => { 'id' => 'notion-user-id' } }
          }
        })
      end

      it '空のユーザーマッピングは含まれない' do
        result = ResponseBuilder.success_response(analysis_result, integration_results, {})
        
        body = JSON.parse(result[:body])
        expect(body).not_to have_key('user_mappings')
      end

      it 'nilユーザーマッピングは含まれない' do
        result = ResponseBuilder.success_response(analysis_result, integration_results, nil)
        
        body = JSON.parse(result[:body])
        expect(body).not_to have_key('user_mappings')
      end
    end
  end

  describe 'プライベートメソッドの動作確認' do
    describe '.slack_integration_status' do
      it 'nilの場合はnot_sentを返す' do
        status = ResponseBuilder.send(:slack_integration_status, nil)
        expect(status).to eq('not_sent')
      end

      it '成功の場合はsentを返す' do
        result = { success: true }
        status = ResponseBuilder.send(:slack_integration_status, result)
        expect(status).to eq('sent')
      end

      it '失敗の場合はnot_sentを返す' do
        result = { success: false }
        status = ResponseBuilder.send(:slack_integration_status, result)
        expect(status).to eq('not_sent')
      end
    end

    describe '.notion_integration_status' do
      it 'nilの場合はnot_createdを返す' do
        status = ResponseBuilder.send(:notion_integration_status, nil)
        expect(status).to eq('not_created')
      end

      it '成功の場合はcreatedを返す' do
        result = { success: true }
        status = ResponseBuilder.send(:notion_integration_status, result)
        expect(status).to eq('created')
      end

      it '失敗の場合はnot_createdを返す' do
        result = { success: false }
        status = ResponseBuilder.send(:notion_integration_status, result)
        expect(status).to eq('not_created')
      end
    end
  end

  describe 'JSONシリアライゼーション' do
    context '複雑な分析結果' do
      let(:complex_analysis) do
        {
          'meeting_summary' => {
            'title' => 'プロジェクト進捗確認',
            'date' => '2025-01-15',
            'participants' => ['田中太郎', '佐藤花子', 'John Smith'],
            'duration_minutes' => 45
          },
          'decisions' => [
            { 'content' => '価格設定を500円に決定', 'category' => 'pricing' },
            { 'content' => 'リリース日を2月1日に設定', 'category' => 'schedule' }
          ],
          'actions' => [
            {
              'task' => 'セキュリティテストの実施',
              'assignee' => 'セキュリティチーム',
              'priority' => 'high',
              'deadline' => '来週末'
            }
          ],
          'health_assessment' => {
            'overall_score' => 85,
            'contradictions' => [],
            'unresolved_issues' => ['予算の最終確認']
          }
        }
      end

      it '複雑な分析結果が正しくJSONシリアライズされる' do
        result = ResponseBuilder.success_response(complex_analysis, { slack: nil, notion: nil })
        
        expect { JSON.parse(result[:body]) }.not_to raise_error
        
        body = JSON.parse(result[:body])
        expect(body['analysis']['meeting_summary']['participants']).to include('田中太郎', '佐藤花子', 'John Smith')
        expect(body['analysis']['decisions'].length).to eq(2)
        expect(body['analysis']['actions'][0]['priority']).to eq('high')
      end
    end
  end

  describe '境界値・エラーケース' do
    context '空の分析結果' do
      it '空の分析結果が正しく処理される' do
        empty_analysis = {}
        result = ResponseBuilder.success_response(empty_analysis, { slack: nil, notion: nil })
        
        body = JSON.parse(result[:body])
        expect(body['analysis']).to eq({})
        expect(body['message']).to eq('Analysis complete.')
      end
    end

    context '大量のデータ' do
      it '大きな分析結果が正しく処理される' do
        large_analysis = {
          'actions' => (1..100).map do |i|
            {
              'task' => "タスク #{i}",
              'assignee' => "担当者#{i}",
              'description' => 'x' * 500
            }
          end
        }
        
        expect { 
          ResponseBuilder.success_response(large_analysis, { slack: nil, notion: nil })
        }.not_to raise_error
      end
    end
  end
end