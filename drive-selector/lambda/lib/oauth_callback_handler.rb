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
      # 認証コードをトークンに交換（動的リダイレクトURI使用）
      tokens = @oauth_client.exchange_code_for_token(code, event)

      # トークンを保存
      @oauth_client.save_tokens(slack_user_id, tokens)

      # 成功レスポンス（HTMLで表示）
      success_html = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>認証成功 - Meeting Analyzer</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
              background: linear-gradient(135deg, #5eb3fa 0%, #3993dd 100%);
              display: flex;
              justify-content: center;
              align-items: center;
              height: 100vh;
              margin: 0;
              padding: 20px;
            }
            .container {
              text-align: center;
              padding: 3rem;
              background: white;
              border-radius: 20px;
              box-shadow: 0 20px 60px rgba(0, 0, 0, 0.15);
              max-width: 500px;
              animation: slideIn 0.4s ease-out;
            }
            @keyframes slideIn {
              from {
                opacity: 0;
                transform: translateY(-20px);
              }
              to {
                opacity: 1;
                transform: translateY(0);
              }
            }
            .success-icon {
              width: 80px;
              height: 80px;
              margin: 0 auto 1.5rem;
              background: linear-gradient(135deg, #4ade80 0%, #22c55e 100%);
              border-radius: 50%;
              display: flex;
              align-items: center;
              justify-content: center;
              animation: pulse 1.5s ease-in-out infinite;
            }
            @keyframes pulse {
              0%, 100% {
                transform: scale(1);
              }
              50% {
                transform: scale(1.05);
              }
            }
            .checkmark {
              color: white;
              font-size: 40px;
            }
            h1 {
              color: #1e293b;
              margin-bottom: 1rem;
              font-size: 28px;
              font-weight: 600;
            }
            p {
              color: #64748b;
              margin-bottom: 2rem;
              line-height: 1.6;
              font-size: 16px;
            }
            .info-box {
              background: #f0f9ff;
              border-left: 4px solid #3b82f6;
              padding: 1rem;
              border-radius: 8px;
              margin-bottom: 2rem;
              text-align: left;
            }
            .info-box p {
              margin: 0;
              color: #1e40af;
              font-size: 14px;
            }
            .back-button {
              background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
              color: white;
              border: none;
              padding: 14px 32px;
              border-radius: 10px;
              font-size: 16px;
              font-weight: 500;
              cursor: pointer;
              transition: all 0.3s ease;
              box-shadow: 0 4px 15px rgba(59, 130, 246, 0.3);
            }
            .back-button:hover {
              transform: translateY(-2px);
              box-shadow: 0 6px 20px rgba(59, 130, 246, 0.4);
            }
            .slack-logo {
              width: 24px;
              height: 24px;
              vertical-align: middle;
              margin-right: 8px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="success-icon">
              <span class="checkmark">✓</span>
            </div>
            <h1>Google Drive 認証が完了しました</h1>
            <p>Meeting Analyzer が Google Drive にアクセスできるようになりました。</p>

            <div class="info-box">
              <p>📝 次のステップ：</p>
              <p style="margin-top: 8px;">Slack で <strong>/meeting-analyzer</strong> コマンドを実行して、<br>Google Drive から議事録を選択してください。</p>
            </div>

            <button class="back-button" onclick="redirectToSlack()">
              <svg class="slack-logo" viewBox="0 0 24 24" fill="currentColor">
                <path d="M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zM6.313 15.165a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zM8.834 6.313a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312zM18.956 8.834a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zM17.688 8.834a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.165 0a2.528 2.528 0 0 1 2.523 2.522v6.312zM15.165 18.956a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.165 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zM15.165 17.688a2.527 2.527 0 0 1-2.52-2.523 2.526 2.526 0 0 1 2.52-2.52h6.313A2.527 2.527 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.523h-6.313z"/>
              </svg>
              Slack に戻る
            </button>
          </div>
          <script>
            function redirectToSlack() {
              // Slackアプリを開く（デスクトップアプリがインストールされている場合）
              window.location.href = 'slack://open';

              // 1秒後にウィンドウを閉じる試み
              setTimeout(() => {
                if (window.opener) {
                  window.opener = null;
                }
                window.open('', '_self', '');
                window.close();
              }, 1000);
            }

            // 10秒後に自動的にSlackへリダイレクト
            setTimeout(redirectToSlack, 10000);
          </script>
        </body>
        </html>
      HTML

      {
        statusCode: 200,
        headers: {
          'Content-Type' => 'text/html; charset=utf-8'
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
    return nil if state.nil? || state.empty?

    decoded = Base64.urlsafe_decode64(state)
    parts = decoded.split(':')

    # 厳密な検証: 正確に2要素、2番目は32文字のhex文字列
    return nil unless parts.length == 2
    return nil unless parts[1].match?(/\A[a-f0-9]{32}\z/)

    parts.first
  rescue ArgumentError => e
    puts "Invalid base64 state: #{e.message}"
    nil
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
            background: linear-gradient(135deg, #94a3b8 0%, #64748b 100%);
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            padding: 20px;
          }
          .container {
            text-align: center;
            padding: 3rem;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.15);
            max-width: 500px;
            animation: slideIn 0.4s ease-out;
          }
          @keyframes slideIn {
            from {
              opacity: 0;
              transform: translateY(-20px);
            }
            to {
              opacity: 1;
              transform: translateY(0);
            }
          }
          .error-icon {
            width: 80px;
            height: 80px;
            margin: 0 auto 1.5rem;
            background: linear-gradient(135deg, #f87171 0%, #ef4444 100%);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
          }
          .error-x {
            color: white;
            font-size: 40px;
            font-weight: bold;
          }
          h1 {
            color: #1e293b;
            margin-bottom: 1rem;
            font-size: 28px;
            font-weight: 600;
          }
          p {
            color: #64748b;
            margin-bottom: 1rem;
            line-height: 1.6;
            font-size: 16px;
          }
          .error-message {
            background: #fef2f2;
            border-left: 4px solid #ef4444;
            padding: 1rem;
            border-radius: 8px;
            margin-bottom: 2rem;
            text-align: left;
          }
          .error-message p {
            margin: 0;
            color: #991b1b;
            font-size: 14px;
          }
          .retry-button {
            background: linear-gradient(135deg, #64748b 0%, #475569 100%);
            color: white;
            border: none;
            padding: 14px 32px;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(71, 85, 105, 0.3);
          }
          .retry-button:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(71, 85, 105, 0.4);
          }
          .slack-logo {
            width: 24px;
            height: 24px;
            vertical-align: middle;
            margin-right: 8px;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="error-icon">
            <span class="error-x">×</span>
          </div>
          <h1>認証に失敗しました</h1>

          <div class="error-message">
            <p>#{message}</p>
          </div>

          <p>お手数ですが、Slack に戻って再度お試しください。</p>

          <button class="retry-button" onclick="redirectToSlack()">
            <svg class="slack-logo" viewBox="0 0 24 24" fill="currentColor">
              <path d="M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zM6.313 15.165a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zM8.834 6.313a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312zM18.956 8.834a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zM17.688 8.834a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.165 0a2.528 2.528 0 0 1 2.523 2.522v6.312zM15.165 18.956a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.165 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zM15.165 17.688a2.527 2.527 0 0 1-2.52-2.523 2.526 2.526 0 0 1 2.52-2.52h6.313A2.527 2.527 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.523h-6.313z"/>
            </svg>
            Slack に戻る
          </button>
        </div>
        <script>
          function redirectToSlack() {
            // Slackアプリを開く（デスクトップアプリがインストールされている場合）
            window.location.href = 'slack://open';

            // 1秒後にウィンドウを閉じる試み
            setTimeout(() => {
              if (window.opener) {
                window.opener = null;
              }
              window.open('', '_self', '');
              window.close();
            }, 1000);
          }
        </script>
      </body>
      </html>
    HTML

    {
      statusCode: 400,
      headers: {
        'Content-Type' => 'text/html; charset=utf-8'
      },
      body: error_html
    }
  end
end
