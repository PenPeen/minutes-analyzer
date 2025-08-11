# frozen_string_literal: true

require 'json'
require 'base64'
require_relative 'google_oauth_client'

class OAuthCallbackHandler
  def initialize
    @oauth_client = GoogleOAuthClient.new
  end

  # OAuth コールバックを処理
  def handle_callback(event)
    # クエリパラメータから認証コードとstateを取得
    query_params = event['queryStringParameters'] || {}
    code = query_params['code']
    state = query_params['state']
    error = query_params['error']

    # エラーチェック
    if error
      return error_response("認証がキャンセルされました: #{error}")
    end

    unless code && state
      return error_response('認証コードまたはstateが不足しています')
    end

    # stateからSlackユーザーIDを抽出
    slack_user_id = extract_user_id_from_state(state)
    unless slack_user_id
      return error_response('無効なstateパラメータです')
    end

    begin
      # 認証コードをトークンに交換
      tokens = @oauth_client.exchange_code_for_token(code)
      
      # トークンを保存
      @oauth_client.save_tokens(slack_user_id, tokens)
      
      # 成功レスポンス（HTMLで表示）
      success_html = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>認証成功</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
              background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
              color: white;
              display: flex;
              justify-content: center;
              align-items: center;
              height: 100vh;
              margin: 0;
            }
            .container {
              text-align: center;
              padding: 2rem;
              background: rgba(255, 255, 255, 0.1);
              border-radius: 10px;
              backdrop-filter: blur(10px);
            }
            h1 { margin-bottom: 1rem; }
            p { margin-bottom: 2rem; }
            .close-button {
              background: white;
              color: #667eea;
              border: none;
              padding: 12px 24px;
              border-radius: 6px;
              font-size: 16px;
              cursor: pointer;
              transition: transform 0.2s;
            }
            .close-button:hover {
              transform: scale(1.05);
            }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>✅ 認証成功！</h1>
            <p>Google Drive との連携が完了しました。<br>Slack に戻って /meet-transcript コマンドをお試しください。</p>
            <button class="close-button" onclick="window.close()">このウィンドウを閉じる</button>
          </div>
          <script>
            // 3秒後に自動的にウィンドウを閉じる
            setTimeout(() => {
              window.close();
            }, 3000);
          </script>
        </body>
        </html>
      HTML

      {
        statusCode: 200,
        headers: {
          'Content-Type': 'text/html; charset=utf-8'
        },
        body: success_html
      }
    rescue => e
      puts "OAuth callback error: #{e.message}"
      puts e.backtrace
      error_response("認証処理中にエラーが発生しました: #{e.message}")
    end
  end

  private

  # stateからSlackユーザーIDを抽出
  def extract_user_id_from_state(state)
    decoded = Base64.urlsafe_decode64(state)
    parts = decoded.split(':')
    parts.first if parts.length >= 2
  rescue => e
    puts "State decode error: #{e.message}"
    nil
  end

  # エラーレスポンスを生成
  def error_response(message)
    error_html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>認証エラー</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
          }
          .container {
            text-align: center;
            padding: 2rem;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            backdrop-filter: blur(10px);
            max-width: 500px;
          }
          h1 { margin-bottom: 1rem; }
          p { margin-bottom: 2rem; }
          .error-message {
            background: rgba(255, 255, 255, 0.2);
            padding: 1rem;
            border-radius: 6px;
            margin-bottom: 2rem;
          }
          .retry-button {
            background: white;
            color: #f5576c;
            border: none;
            padding: 12px 24px;
            border-radius: 6px;
            font-size: 16px;
            cursor: pointer;
            transition: transform 0.2s;
            text-decoration: none;
            display: inline-block;
          }
          .retry-button:hover {
            transform: scale(1.05);
          }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>❌ 認証エラー</h1>
          <div class="error-message">
            <p>#{message}</p>
          </div>
          <p>Slack に戻って再度お試しください。</p>
          <button class="retry-button" onclick="window.close()">ウィンドウを閉じる</button>
        </div>
      </body>
      </html>
    HTML

    {
      statusCode: 400,
      headers: {
        'Content-Type': 'text/html; charset=utf-8'
      },
      body: error_html
    }
  end
end