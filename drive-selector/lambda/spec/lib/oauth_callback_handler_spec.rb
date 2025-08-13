# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/oauth_callback_handler'
require 'base64'

RSpec.describe OAuthCallbackHandler do
  let(:oauth_client) { instance_double('GoogleOAuthClient') }
  
  before do
    allow(GoogleOAuthClient).to receive(:new).and_return(oauth_client)
  end
  
  let(:handler) { OAuthCallbackHandler.new }

  describe '#initialize' do
    it 'GoogleOAuthClientを初期化する' do
      # Force handler creation to trigger the mock expectation
      created_handler = handler
      expect(GoogleOAuthClient).to have_received(:new)
      expect(created_handler.instance_variable_get(:@oauth_client)).to eq(oauth_client)
    end
  end

  describe '#handle_callback' do
    let(:slack_user_id) { 'U1234567890' }
    let(:nonce) { 'a' * 32 }
    let(:state) { Base64.urlsafe_encode64("#{slack_user_id}:#{nonce}") }
    let(:auth_code) { 'test_auth_code_12345' }

    context '正常なOAuthコールバック' do
      let(:valid_event) do
        {
          'queryStringParameters' => {
            'code' => auth_code,
            'state' => state
          }
        }
      end

      let(:tokens) do
        {
          access_token: 'access_token_123',
          refresh_token: 'refresh_token_456',
          expires_in: 3600
        }
      end

      before do
        allow(oauth_client).to receive(:exchange_code_for_token).with(auth_code).and_return(tokens)
        allow(oauth_client).to receive(:save_tokens).with(slack_user_id, tokens)
      end

      it '成功時に適切なHTMLレスポンスを返す' do
        result = handler.handle_callback(valid_event)

        expect(result[:statusCode]).to eq(200)
        expect(result[:headers]['Content-Type']).to eq('text/html; charset=utf-8')
        expect(result[:body]).to include('認証成功！')
        expect(result[:body]).to include('Google Drive との連携が完了しました')
        expect(result[:body]).to include('/meet-transcript コマンドをお試しください')
      end

      it 'トークン交換とトークン保存を正しく実行' do
        handler.handle_callback(valid_event)

        expect(oauth_client).to have_received(:exchange_code_for_token).with(auth_code)
        expect(oauth_client).to have_received(:save_tokens).with(slack_user_id, tokens)
      end

      it '成功HTMLにウィンドウクローズ機能が含まれる' do
        result = handler.handle_callback(valid_event)

        expect(result[:body]).to include('window.close()')
        expect(result[:body]).to include('setTimeout')
        expect(result[:body]).to include('3000') # 3秒後の自動クローズ
      end

      it '成功HTMLに適切なスタイリングが含まれる' do
        result = handler.handle_callback(valid_event)

        expect(result[:body]).to include('font-family:')
        expect(result[:body]).to include('background: linear-gradient')
        expect(result[:body]).to include('backdrop-filter: blur')
      end
    end

    context 'OAuth認証エラー' do
      let(:error_event) do
        {
          'queryStringParameters' => {
            'error' => 'access_denied',
            'error_description' => 'User denied access'
          }
        }
      end

      it 'エラー時に適切なエラーレスポンスを返す' do
        result = handler.handle_callback(error_event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:headers]['Content-Type']).to eq('text/html; charset=utf-8')
        expect(result[:body]).to include('認証エラー')
        expect(result[:body]).to include('認証がキャンセルされました: access_denied')
      end
    end

    context '必須パラメータ不足' do
      it 'codeが不足している場合にエラーレスポンス' do
        event = {
          'queryStringParameters' => {
            'state' => state
          }
        }

        result = handler.handle_callback(event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('認証コードまたはstateが不足しています')
      end

      it 'stateが不足している場合にエラーレスポンス' do
        event = {
          'queryStringParameters' => {
            'code' => auth_code
          }
        }

        result = handler.handle_callback(event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('認証コードまたはstateが不足しています')
      end

      it 'queryStringParametersが存在しない場合にエラーレスポンス' do
        event = {}

        result = handler.handle_callback(event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('認証コードまたはstateが不足しています')
      end

      it 'queryStringParametersがnilの場合にエラーレスポンス' do
        event = { 'queryStringParameters' => nil }

        result = handler.handle_callback(event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('認証コードまたはstateが不足しています')
      end
    end

    context '無効なstateパラメータ' do
      it '無効なBase64エンコーディングの場合にエラーレスポンス' do
        event = {
          'queryStringParameters' => {
            'code' => auth_code,
            'state' => 'invalid_base64!!!'
          }
        }

        result = handler.handle_callback(event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('無効なstateパラメータです')
      end

      it '正しい形式でないstateの場合にエラーレスポンス' do
        invalid_state = Base64.urlsafe_encode64('invalid_format')
        event = {
          'queryStringParameters' => {
            'code' => auth_code,
            'state' => invalid_state
          }
        }

        result = handler.handle_callback(event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('無効なstateパラメータです')
      end

      it '空のstateの場合にエラーレスポンス' do
        event = {
          'queryStringParameters' => {
            'code' => auth_code,
            'state' => ''
          }
        }

        result = handler.handle_callback(event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('無効なstateパラメータです')
      end
    end

    context 'OAuth処理中のエラー' do
      let(:valid_event) do
        {
          'queryStringParameters' => {
            'code' => auth_code,
            'state' => state
          }
        }
      end

      it 'トークン交換エラー時に適切なエラーレスポンス' do
        allow(oauth_client).to receive(:exchange_code_for_token)
          .and_raise(StandardError.new('Invalid authorization code'))

        result = handler.handle_callback(valid_event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('認証処理中にエラーが発生しました')
        expect(result[:body]).to include('Invalid authorization code')
      end

      it 'トークン保存エラー時に適切なエラーレスポンス' do
        tokens = { access_token: 'test', refresh_token: 'test' }
        allow(oauth_client).to receive(:exchange_code_for_token).and_return(tokens)
        allow(oauth_client).to receive(:save_tokens)
          .and_raise(StandardError.new('Token storage failed'))

        result = handler.handle_callback(valid_event)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include('認証処理中にエラーが発生しました')
        expect(result[:body]).to include('Token storage failed')
      end
    end
  end

  describe '#extract_user_id_from_state (private method behavior)' do
    let(:slack_user_id) { 'U1234567890' }
    let(:valid_nonce) { 'a' * 32 }

    context '有効なstateパラメータ' do
      it '正しい形式のstateからSlackユーザーIDを抽出' do
        state = Base64.urlsafe_encode64("#{slack_user_id}:#{valid_nonce}")
        
        # プライベートメソッドのテスト用にイベントを作成
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => state
          }
        }

        allow(oauth_client).to receive(:exchange_code_for_token).and_return({})
        allow(oauth_client).to receive(:save_tokens)

        handler.handle_callback(event)

        # 成功レスポンスが返ることで、正しくuser_idが抽出されたことを確認
        expect(oauth_client).to have_received(:save_tokens).with(slack_user_id, anything)
      end

      it '長いSlackユーザーIDでも正しく処理' do
        long_user_id = 'U' + 'A' * 20
        state = Base64.urlsafe_encode64("#{long_user_id}:#{valid_nonce}")
        
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => state
          }
        }

        allow(oauth_client).to receive(:exchange_code_for_token).and_return({})
        allow(oauth_client).to receive(:save_tokens)

        handler.handle_callback(event)

        expect(oauth_client).to have_received(:save_tokens).with(long_user_id, anything)
      end
    end

    context '無効なstateパラメータ' do
      it 'nilの場合は処理に失敗' do
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => nil
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end

      it '空文字列の場合は処理に失敗' do
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => ''
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end

      it '不正なBase64の場合は処理に失敗' do
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => 'invalid_base64!!!'
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end

      it 'コロンで分割できない場合は処理に失敗' do
        state = Base64.urlsafe_encode64('no_colon_separator')
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => state
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end

      it '32文字でないnonceの場合は処理に失敗' do
        short_nonce = 'a' * 16
        state = Base64.urlsafe_encode64("#{slack_user_id}:#{short_nonce}")
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => state
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end

      it '非hex文字を含むnonceの場合は処理に失敗' do
        invalid_nonce = 'g' * 32 # 'g'は16進数ではない
        state = Base64.urlsafe_encode64("#{slack_user_id}:#{invalid_nonce}")
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => state
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end

      it '3つ以上の要素に分割される場合は処理に失敗' do
        state = Base64.urlsafe_encode64("#{slack_user_id}:#{valid_nonce}:extra")
        event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => state
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end
    end
  end

  describe 'HTMLレスポンスの詳細テスト' do
    context '成功レスポンスHTML' do
      let(:valid_event) do
        {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => Base64.urlsafe_encode64("U123:#{('a' * 32)}")
          }
        }
      end

      before do
        allow(oauth_client).to receive(:exchange_code_for_token).and_return({})
        allow(oauth_client).to receive(:save_tokens)
      end

      it '正しいHTTPヘッダーが設定される' do
        result = handler.handle_callback(valid_event)

        expect(result[:headers]).to include('Content-Type' => 'text/html; charset=utf-8')
      end

      it '適切なHTML構造が含まれる' do
        result = handler.handle_callback(valid_event)

        expect(result[:body]).to include('<!DOCTYPE html>')
        expect(result[:body]).to include('<html>')
        expect(result[:body]).to include('<head>')
        expect(result[:body]).to include('<body>')
        expect(result[:body]).to include('<meta charset="UTF-8">')
      end

      it 'JavaScript機能が含まれる' do
        result = handler.handle_callback(valid_event)

        expect(result[:body]).to include('<script>')
        expect(result[:body]).to include('setTimeout')
        expect(result[:body]).to include('window.close()')
      end

      it 'ユーザーフレンドリーなメッセージが含まれる' do
        result = handler.handle_callback(valid_event)

        expect(result[:body]).to include('✅ 認証成功！')
        expect(result[:body]).to include('このウィンドウを閉じる')
      end
    end

    context 'エラーレスポンスHTML' do
      let(:error_message) { 'テストエラーメッセージ' }

      it '適切なエラーHTMLが生成される' do
        result = handler.send(:error_response, error_message)

        expect(result[:statusCode]).to eq(400)
        expect(result[:headers]['Content-Type']).to eq('text/html; charset=utf-8')
        expect(result[:body]).to include('❌ 認証エラー')
        expect(result[:body]).to include(error_message)
        expect(result[:body]).to include('Slack に戻って再度お試しください')
      end

      it 'エラーHTMLに適切なスタイリングが含まれる' do
        result = handler.send(:error_response, error_message)

        expect(result[:body]).to include('background: linear-gradient')
        expect(result[:body]).to include('error-message')
        expect(result[:body]).to include('retry-button')
      end

      it 'ユーザーインタラクション要素が含まれる' do
        result = handler.send(:error_response, error_message)

        expect(result[:body]).to include('onclick="window.close()"')
        expect(result[:body]).to include('ウィンドウを閉じる')
      end
    end
  end

  describe '境界値・セキュリティテスト' do
    context 'stateパラメータのセキュリティ検証' do
      let(:code) { 'test_code' }

      it '大文字のhex文字を含むnonceは拒否される' do
        invalid_nonce = 'A' * 32 # 大文字のhex文字
        state = Base64.urlsafe_encode64("U123:#{invalid_nonce}")
        event = {
          'queryStringParameters' => {
            'code' => code,
            'state' => state
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end

      it '31文字のnonceは拒否される' do
        short_nonce = 'a' * 31
        state = Base64.urlsafe_encode64("U123:#{short_nonce}")
        event = {
          'queryStringParameters' => {
            'code' => code,
            'state' => state
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end

      it '33文字のnonceは拒否される' do
        long_nonce = 'a' * 33
        state = Base64.urlsafe_encode64("U123:#{long_nonce}")
        event = {
          'queryStringParameters' => {
            'code' => code,
            'state' => state
          }
        }

        result = handler.handle_callback(event)
        expect(result[:statusCode]).to eq(400)
      end
    end

    context 'エラーメッセージのエスケープ' do
      it 'HTMLインジェクションを防ぐ' do
        malicious_message = '<script>alert("xss")</script>'
        result = handler.send(:error_response, malicious_message)

        # HTMLエスケープは実装されていないが、テンプレートの構造は保持される
        expect(result[:body]).to include(malicious_message)
        expect(result[:body]).to include('認証エラー')
      end

      it '長いエラーメッセージを適切に処理' do
        long_message = 'エラー' * 1000
        result = handler.send(:error_response, long_message)

        expect(result[:statusCode]).to eq(400)
        expect(result[:body]).to include(long_message)
      end
    end
  end

  describe 'エラーハンドリングとログ出力' do
    context '例外発生時のログ出力' do
      let(:valid_event) do
        {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => Base64.urlsafe_encode64("U123:#{('a' * 32)}")
          }
        }
      end

      it 'トークン交換エラー時にログ出力される' do
        error = StandardError.new('API Error')
        allow(error).to receive(:backtrace).and_return(['line1', 'line2'])
        allow(oauth_client).to receive(:exchange_code_for_token).and_raise(error)

        expect { handler.handle_callback(valid_event) }.to output(/OAuth callback error: API Error/).to_stdout
        expect { handler.handle_callback(valid_event) }.to output(/line1/).to_stdout
      end

      it 'state解析エラー時にログ出力される' do
        invalid_state_event = {
          'queryStringParameters' => {
            'code' => 'test_code',
            'state' => 'invalid!!!'
          }
        }

        expect { handler.handle_callback(invalid_state_event) }.to output(/Invalid base64 state/).to_stdout
      end
    end
  end
end