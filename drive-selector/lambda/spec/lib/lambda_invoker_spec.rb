# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/lambda_invoker'

RSpec.describe LambdaInvoker do
  let(:lambda_client) { instance_double(Aws::Lambda::Client) }
  let(:invoker) { described_class.new }

  before do
    allow(Aws::Lambda::Client).to receive(:new).and_return(lambda_client)
  end

  describe '#invoke_analysis_lambda' do
    let(:payload) do
      {
        file_id: 'test-file-id-123',
        file_name: 'テスト議事録.txt',
        user_id: 'U123456',
        user_email: 'test@example.com',
        options: {
          detailed_analysis: true,
          save_to_notion: false
        }
      }
    end

    let(:expected_lambda_payload) do
      {
        body: JSON.generate({
          file_id: 'test-file-id-123',
          file_name: 'テスト議事録.txt',
          options: {
            detailed_analysis: true,
            save_to_notion: false
          },
          slack_user_id: 'U123456',
          slack_user_email: 'test@example.com'
        }),
        headers: {
          'Content-Type' => 'application/json'
        }
      }
    end

    context '成功した場合' do
      let(:invoke_response) do
        instance_double(
          Aws::Lambda::Types::InvocationResponse,
          status_code: 202
        )
      end

      before do
        allow(lambda_client).to receive(:invoke).and_return(invoke_response)
      end

      it 'Lambda関数を非同期で呼び出す' do
        expect(lambda_client).to receive(:invoke).with(
          function_name: 'arn:aws:lambda:ap-northeast-1:123456789012:function:minutes-analyzer-production',
          invocation_type: 'Event',
          payload: JSON.generate(expected_lambda_payload)
        )

        result = invoker.invoke_analysis_lambda(payload)
        
        expect(result[:status]).to eq('success')
        expect(result[:message]).to eq('Analysis lambda invoked successfully')
      end
    end

    context 'Lambda呼び出しが失敗した場合' do
      let(:invoke_response) do
        instance_double(
          Aws::Lambda::Types::InvocationResponse,
          status_code: 500
        )
      end

      before do
        allow(lambda_client).to receive(:invoke).and_return(invoke_response)
      end

      it 'エラーステータスを返す' do
        result = invoker.invoke_analysis_lambda(payload)
        
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('Failed to invoke lambda')
      end
    end

    context 'AWS SDK例外が発生した場合' do
      before do
        allow(lambda_client).to receive(:invoke).and_raise(
          Aws::Lambda::Errors::ServiceError.new(nil, 'Lambda service error')
        )
      end

      it 'エラーメッセージを返す' do
        result = invoker.invoke_analysis_lambda(payload)
        
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('Lambda invocation failed')
      end
    end

    context '予期しない例外が発生した場合' do
      before do
        allow(lambda_client).to receive(:invoke).and_raise(StandardError, 'Unexpected error')
      end

      it 'エラーメッセージを返す' do
        result = invoker.invoke_analysis_lambda(payload)
        
        expect(result[:status]).to eq('error')
        expect(result[:message]).to include('Unexpected error')
      end
    end
  end

  describe 'ペイロード変換' do
    context '最小限のペイロードの場合' do
      let(:minimal_payload) do
        {
          file_id: 'file-123',
          file_name: 'test.txt'
        }
      end

      it '正しい形式に変換される' do
        allow(lambda_client).to receive(:invoke).and_return(
          instance_double(Aws::Lambda::Types::InvocationResponse, status_code: 202)
        )

        expect(lambda_client).to receive(:invoke) do |args|
          payload = JSON.parse(args[:payload])
          body = JSON.parse(payload['body'])
          
          expect(body['file_id']).to eq('file-123')
          expect(body['file_name']).to eq('test.txt')
          expect(payload['headers']['Content-Type']).to eq('application/json')
        end.and_return(
          instance_double(Aws::Lambda::Types::InvocationResponse, status_code: 202)
        )

        invoker.invoke_analysis_lambda(minimal_payload)
      end
    end

    context 'オプション情報が含まれる場合' do
      let(:payload_with_options) do
        {
          file_id: 'file-456',
          file_name: 'meeting.txt',
          options: {
            detailed_analysis: true
          }
        }
      end

      it 'オプション情報が含まれる' do
        allow(lambda_client).to receive(:invoke).and_return(
          instance_double(Aws::Lambda::Types::InvocationResponse, status_code: 202)
        )

        expect(lambda_client).to receive(:invoke) do |args|
          payload = JSON.parse(args[:payload])
          body = JSON.parse(payload['body'])
          
          expect(body['options']).to eq({'detailed_analysis' => true})
        end.and_return(
          instance_double(Aws::Lambda::Types::InvocationResponse, status_code: 202)
        )

        invoker.invoke_analysis_lambda(payload_with_options)
      end
    end
  end

  describe 'ARN取得ロジック' do
    context 'デフォルトのARNパターンを使用する場合' do
      it 'STS経由でアカウントIDを取得してARNを構築する' do
        allow(lambda_client).to receive(:invoke).and_return(
          instance_double(Aws::Lambda::Types::InvocationResponse, status_code: 202)
        )

        expect(lambda_client).to receive(:invoke).with(
          hash_including(function_name: 'arn:aws:lambda:ap-northeast-1:123456789012:function:minutes-analyzer-production')
        )

        invoker.invoke_analysis_lambda({file_id: 'test', file_name: 'test.txt'})
      end
    end
  end
end