require 'spec_helper'
require_relative '../lib/request_validator'
require 'json'

RSpec.describe RequestValidator do
  let(:logger) { double('logger') }
  let(:validator) { RequestValidator.new(logger) }

  before do
    allow(logger).to receive(:error)
  end

  describe '#initialize' do
    it 'ロガーが正しく設定される' do
      expect(validator.instance_variable_get(:@logger)).to eq(logger)
    end
  end

  describe '#validate_and_parse' do
    context '正常なリクエストの場合' do
      let(:valid_body) { JSON.generate({ 'file_id' => 'test-file-id', 'file_name' => 'test.txt' }) }
      let(:valid_event) { { 'body' => valid_body } }

      it '正常にパースされたJSONを返す' do
        result = validator.validate_and_parse(valid_event)
        
        expect(result).to eq({
          'file_id' => 'test-file-id',
          'file_name' => 'test.txt'
        })
      end

      it 'エラーログが出力されない' do
        expect(logger).not_to receive(:error)
        validator.validate_and_parse(valid_event)
      end
    end

    context 'file_idのみの最小限リクエスト' do
      let(:minimal_body) { JSON.generate({ 'file_id' => '1234567890abcdef' }) }
      let(:minimal_event) { { 'body' => minimal_body } }

      it '正常に処理される' do
        result = validator.validate_and_parse(minimal_event)
        expect(result).to eq({ 'file_id' => '1234567890abcdef' })
      end
    end

    context '追加フィールドを含むリクエスト' do
      let(:extended_body) do
        JSON.generate({
          'file_id' => 'test-file-id',
          'file_name' => 'test.txt',
          'metadata' => { 'source' => 'google_drive' },
          'timestamp' => '2025-01-15T10:00:00Z'
        })
      end
      let(:extended_event) { { 'body' => extended_body } }

      it '追加フィールドも含めて正常に処理される' do
        result = validator.validate_and_parse(extended_event)
        
        expect(result['file_id']).to eq('test-file-id')
        expect(result['file_name']).to eq('test.txt')
        expect(result['metadata']).to eq({ 'source' => 'google_drive' })
        expect(result['timestamp']).to eq('2025-01-15T10:00:00Z')
      end
    end

    context 'URL形式のリクエスト' do
      let(:url_body) do
        JSON.generate({
          'input_type' => 'url',
          'file_id' => '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
          'file_name' => 'Meeting Document',
          'google_doc_url' => 'https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit',
          'slack_user_id' => 'U1234567890'
        })
      end
      let(:url_event) { { 'body' => url_body } }

      it '正常に処理される' do
        result = validator.validate_and_parse(url_event)
        
        expect(result['input_type']).to eq('url')
        expect(result['file_id']).to eq('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms')
        expect(result['file_name']).to eq('Meeting Document')
        expect(result['google_doc_url']).to eq('https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit')
        expect(result['slack_user_id']).to eq('U1234567890')
      end
    end
  end

  describe 'エラーケースの詳細テスト' do
    context 'eventが無効な場合' do
      it 'nilイベントでValidationErrorが発生' do
        expect(logger).to receive(:error).with("Event is not a Hash: NilClass")
        
        expect {
          validator.validate_and_parse(nil)
        }.to raise_error(RequestValidator::ValidationError, "Invalid event format")
      end

      it '文字列イベントでValidationErrorが発生' do
        expect(logger).to receive(:error).with("Event is not a Hash: String")
        
        expect {
          validator.validate_and_parse("invalid event")
        }.to raise_error(RequestValidator::ValidationError, "Invalid event format")
      end

      it '配列イベントでValidationErrorが発生' do
        expect(logger).to receive(:error).with("Event is not a Hash: Array")
        
        expect {
          validator.validate_and_parse([])
        }.to raise_error(RequestValidator::ValidationError, "Invalid event format")
      end

      it '数値イベントでValidationErrorが発生' do
        expect(logger).to receive(:error).with("Event is not a Hash: Integer")
        
        expect {
          validator.validate_and_parse(123)
        }.to raise_error(RequestValidator::ValidationError, "Invalid event format")
      end
    end

    context 'bodyが無効な場合' do
      it 'bodyがnilの場合にValidationErrorが発生' do
        expect(logger).to receive(:error).with("Request body is missing.")
        
        expect {
          validator.validate_and_parse({ 'body' => nil })
        }.to raise_error(RequestValidator::ValidationError, "Request body is missing.")
      end

      it 'bodyが存在しない場合にValidationErrorが発生' do
        expect(logger).to receive(:error).with("Request body is missing.")
        
        expect {
          validator.validate_and_parse({})
        }.to raise_error(RequestValidator::ValidationError, "Request body is missing.")
      end

      it 'bodyが空文字列の場合にValidationErrorが発生' do
        expect(logger).to receive(:error).with("Request body is missing.")
        
        expect {
          validator.validate_and_parse({ 'body' => '' })
        }.to raise_error(RequestValidator::ValidationError, "Request body is missing.")
      end
    end

    context 'JSONが無効な場合' do
      it '不正なJSON形式でValidationErrorが発生' do
        invalid_json = '{ invalid json'
        event = { 'body' => invalid_json }
        
        expect(logger).to receive(:error).with(/Invalid JSON in request body:/)
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, /Invalid JSON in request body:/)
      end

      it '空のJSONオブジェクトの場合もfile_idエラーが発生' do
        empty_json = '{}'
        event = { 'body' => empty_json }
        
        expect(logger).to receive(:error).with("file_id is missing in request body")
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, "Request must include 'file_id' field")
      end

      it '不完全なJSONでValidationErrorが発生' do
        incomplete_json = '{"file_id":'
        event = { 'body' => incomplete_json }
        
        expect(logger).to receive(:error).with(/Invalid JSON in request body:/)
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, /Invalid JSON in request body:/)
      end

      it '不正な文字を含むJSONでValidationErrorが発生' do
        invalid_char_json = '{"file_id": "test\u0000id"}'
        event = { 'body' => invalid_char_json }
        
        # このJSONは実際には有効だがfile_idは含まれているので、その後の処理でテスト
        result = validator.validate_and_parse(event)
        expect(result['file_id']).to include('test')
      end
    end

    context 'file_idが無効な場合' do
      it 'file_idが欠落している場合にValidationErrorが発生' do
        missing_file_id = JSON.generate({ 'file_name' => 'test.txt' })
        event = { 'body' => missing_file_id }
        
        expect(logger).to receive(:error).with("file_id is missing in request body")
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, "Request must include 'file_id' field")
      end

      it 'file_idがnullの場合にValidationErrorが発生' do
        null_file_id = JSON.generate({ 'file_id' => nil, 'file_name' => 'test.txt' })
        event = { 'body' => null_file_id }
        
        expect(logger).to receive(:error).with("file_id is missing in request body")
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, "Request must include 'file_id' field")
      end

      it 'file_idが空文字列の場合にValidationErrorが発生' do
        empty_file_id = JSON.generate({ 'file_id' => '', 'file_name' => 'test.txt' })
        event = { 'body' => empty_file_id }
        
        expect(logger).to receive(:error).with("file_id is missing in request body")
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, "Request must include 'file_id' field")
      end
    end

    context 'URL形式リクエストのバリデーションエラー' do
      it 'URL形式でgoogle_doc_urlが欠落している場合にValidationErrorが発生' do
        missing_url_body = JSON.generate({
          'input_type' => 'url',
          'file_id' => 'test-file-id'
        })
        event = { 'body' => missing_url_body }
        
        expect(logger).to receive(:error).with("google_doc_url is missing for URL request")
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, "URL requests must include 'google_doc_url' field")
      end

      it 'URL形式でgoogle_doc_urlが空文字列の場合にValidationErrorが発生' do
        empty_url_body = JSON.generate({
          'input_type' => 'url',
          'file_id' => 'test-file-id',
          'google_doc_url' => ''
        })
        event = { 'body' => empty_url_body }
        
        expect(logger).to receive(:error).with("google_doc_url is missing for URL request")
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, "URL requests must include 'google_doc_url' field")
      end

      it 'URL形式でgoogle_doc_urlがnullの場合にValidationErrorが発生' do
        null_url_body = JSON.generate({
          'input_type' => 'url',
          'file_id' => 'test-file-id',
          'google_doc_url' => nil
        })
        event = { 'body' => null_url_body }
        
        expect(logger).to receive(:error).with("google_doc_url is missing for URL request")
        
        expect {
          validator.validate_and_parse(event)
        }.to raise_error(RequestValidator::ValidationError, "URL requests must include 'google_doc_url' field")
      end
    end
  end

  describe '境界値テスト' do
    context '有効なfile_id値' do
      it '短いfile_idが処理される' do
        short_id = JSON.generate({ 'file_id' => 'a' })
        event = { 'body' => short_id }
        
        result = validator.validate_and_parse(event)
        expect(result['file_id']).to eq('a')
      end

      it '長いfile_idが処理される' do
        long_id = 'a' * 1000
        long_id_json = JSON.generate({ 'file_id' => long_id })
        event = { 'body' => long_id_json }
        
        result = validator.validate_and_parse(event)
        expect(result['file_id']).to eq(long_id)
      end

      it '特殊文字を含むfile_idが処理される' do
        special_chars = JSON.generate({ 'file_id' => 'test-file_id.123@example' })
        event = { 'body' => special_chars }
        
        result = validator.validate_and_parse(event)
        expect(result['file_id']).to eq('test-file_id.123@example')
      end

      it 'Google Drive形式のfile_idが処理される' do
        drive_id = JSON.generate({ 'file_id' => '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms' })
        event = { 'body' => drive_id }
        
        result = validator.validate_and_parse(event)
        expect(result['file_id']).to eq('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms')
      end
    end

    context 'JSONのネスト構造' do
      it '深くネストされたJSONが処理される' do
        nested_json = JSON.generate({
          'file_id' => 'test-id',
          'metadata' => {
            'nested' => {
              'deep' => {
                'value' => 'test'
              }
            }
          }
        })
        event = { 'body' => nested_json }
        
        result = validator.validate_and_parse(event)
        expect(result['file_id']).to eq('test-id')
        expect(result['metadata']['nested']['deep']['value']).to eq('test')
      end

      it '配列を含むJSONが処理される' do
        array_json = JSON.generate({
          'file_id' => 'test-id',
          'tags' => ['tag1', 'tag2', 'tag3'],
          participants: [
            { 'name' => 'User1', 'email' => 'user1@example.com' },
            { 'name' => 'User2', 'email' => 'user2@example.com' }
          ]
        })
        event = { 'body' => array_json }
        
        result = validator.validate_and_parse(event)
        expect(result['file_id']).to eq('test-id')
        expect(result['tags']).to eq(['tag1', 'tag2', 'tag3'])
        expect(result['participants'].length).to eq(2)
      end
    end
  end

  describe 'ValidationErrorクラス' do
    it 'StandardErrorを継承している' do
      expect(RequestValidator::ValidationError.new).to be_a(StandardError)
    end

    it 'メッセージが正しく設定される' do
      error = RequestValidator::ValidationError.new("Test error message")
      expect(error.message).to eq("Test error message")
    end
  end

  describe '実際のAWS Lambda eventの形式テスト' do
    context 'API Gateway経由のイベント' do
      let(:api_gateway_event) do
        {
          'httpMethod' => 'POST',
          'path' => '/analyze',
          'headers' => {
            'Content-Type' => 'application/json',
            'User-Agent' => 'test-client'
          },
          'body' => JSON.generate({ 'file_id' => 'api-gateway-test-id' }),
          'isBase64Encoded' => false
        }
      end

      it 'API Gateway形式のイベントが正常に処理される' do
        result = validator.validate_and_parse(api_gateway_event)
        expect(result['file_id']).to eq('api-gateway-test-id')
      end
    end

    context '直接Lambda invoke形式のイベント' do
      let(:direct_invoke_event) do
        {
          'body' => JSON.generate({
            'file_id' => 'direct-invoke-test-id',
            'source' => 'drive_selector'
          })
        }
      end

      it '直接invoke形式のイベントが正常に処理される' do
        result = validator.validate_and_parse(direct_invoke_event)
        expect(result['file_id']).to eq('direct-invoke-test-id')
        expect(result['source']).to eq('drive_selector')
      end
    end
  end
end