# frozen_string_literal: true

require 'json'

class SlackInteractionHandler
  def initialize
    # 必要に応じて依存関係を注入
  end

  # Slackインタラクションを処理
  def handle(payload)
    type = payload['type']
    
    puts "Interaction type: #{type}"
    puts "Payload: #{JSON.pretty_generate(payload)}"
    
    case type
    when 'block_actions'
      handle_block_action(payload)
    when 'view_submission'
      handle_view_submission(payload)
    when 'view_closed'
      handle_view_closed(payload)
    when 'options'
      handle_options_request(payload)
    else
      # 不明なインタラクションタイプ
      default_response
    end
  end

  private

  # ブロックアクション（ボタンクリックなど）を処理
  def handle_block_action(payload)
    # ACKレスポンスを返す
    ack_response
  end

  # モーダルの送信を処理（T-04で詳細実装）
  def handle_view_submission(payload)
    view = payload['view']
    values = view['state']['values']
    user_id = payload['user']['id']
    
    # 選択されたファイル情報を取得
    # T-06で既存Lambdaへの連携を実装
    
    # 成功レスポンス
    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate({
        response_action: 'clear'
      })
    }
  end

  # モーダルが閉じられた時の処理
  def handle_view_closed(payload)
    # 特に処理は不要、ACKレスポンスのみ
    ack_response
  end

  # external_selectのオプションリクエストを処理（T-05で詳細実装）
  def handle_options_request(payload)
    # Google Drive検索を実行してオプションを返す
    # T-05で実装予定
    
    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate({
        options: [
          {
            text: {
              type: 'plain_text',
              text: '📄 サンプルファイル.txt'
            },
            value: 'sample_file_id'
          }
        ]
      })
    }
  end

  # ACKレスポンス
  def ack_response
    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: ''
    }
  end

  # デフォルトレスポンス
  def default_response
    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate({})
    }
  end
end