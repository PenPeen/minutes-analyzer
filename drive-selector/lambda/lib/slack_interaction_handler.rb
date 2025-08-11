# frozen_string_literal: true

require 'json'
require_relative 'slack_api_client'
require_relative 'slack_modal_builder'
require_relative 'lambda_invoker'

class SlackInteractionHandler
  def initialize
    @slack_client = SlackApiClient.new
    @lambda_invoker = LambdaInvoker.new
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

  # モーダルの送信を処理
  def handle_view_submission(payload)
    view = payload['view']
    values = view['state']['values']
    user = payload['user']
    
    # 選択されたファイル情報を取得
    file_select = values['file_select_block']['file_select']['selected_option']
    custom_title = values['custom_title_block']['custom_title']['value'] rescue nil
    options = values['options_block']['analysis_options']['selected_options'] || []
    
    # ファイルが選択されていない場合はエラー
    unless file_select
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.generate({
          response_action: 'errors',
          errors: {
            file_select_block: 'ファイルを選択してください'
          }
        })
      }
    end
    
    file_id = file_select['value']
    file_name = file_select['text']['text']
    
    # オプションを解析
    detailed_analysis = options.any? { |opt| opt['value'] == 'detailed_analysis' }
    save_to_notion = options.any? { |opt| opt['value'] == 'save_to_notion' }
    
    # 非同期で処理を実行
    Thread.new do
      begin
        # 処理中メッセージを送信
        @slack_client.post_ephemeral(
          user['id'],
          user['id'],
          "📊 `#{file_name}` の分析を開始しました..."
        )
        
        # Lambda関数を呼び出し（T-06で実装）
        @lambda_invoker.invoke_analysis_lambda({
          file_id: file_id,
          file_name: custom_title || file_name,
          user_id: user['id'],
          user_email: @slack_client.get_user_email(user['id']),
          options: {
            detailed_analysis: detailed_analysis,
            save_to_notion: save_to_notion
          }
        })
      rescue => e
        puts "Failed to invoke lambda: #{e.message}"
        @slack_client.post_ephemeral(
          user['id'],
          user['id'],
          "❌ 分析処理の開始に失敗しました: #{e.message}"
        )
      end
    end
    
    # モーダルを閉じる
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