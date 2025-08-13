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
  def handle_interaction(payload)
    # ユーザー情報の検証
    user = payload['user']
    return create_error_response('ユーザー情報が不足しています', 400) unless user && user['id']
    
    user_id = user['id']
    type = payload['type']
    
    puts "Interaction type: #{type} from user: #{user_id}"
    
    begin
      case type
      when 'interactive_message'
        # ボタンクリック等の処理
        actions = payload['actions'] || []
        process_button_click(actions, user_id)
      when 'view_submission'
        # モーダル送信の処理
        view_state = payload['view']['state'] rescue nil
        return create_error_response('無効なモーダルデータです', 400) unless view_state
        
        process_modal_submission(view_state, user_id)
      when 'block_actions'
        handle_block_action(payload)
      when 'view_closed'
        handle_view_closed(payload)
      when 'options'
        handle_options_request(payload)
      else
        create_error_response("サポートされていないインタラクションタイプ: #{type}", 400)
      end
    rescue => e
      puts "Error processing interaction: #{e.message}"
      create_error_response('処理中にエラーが発生しました', 500)
    end
  end

  private

  # ボタンクリック処理
  def process_button_click(actions, user_id)
    return { 'response_type' => 'ephemeral', 'text' => 'アクションが指定されていません' } if actions.empty?
    
    action = actions.first
    action_name = action['name']
    
    case action_name
    when 'file_search'
      {
        'response_type' => 'ephemeral',
        'text' => 'ファイル検索機能は現在開発中です（T-05で実装予定）'
      }
    else
      {
        'response_type' => 'ephemeral',
        'text' => "未対応のアクション: #{action_name}"
      }
    end
  end

  # ブロックアクション（ボタンクリックなど）を処理
  def handle_block_action(payload)
    # ACKレスポンスを返す
    ack_response
  end

  # モーダル送信処理
  def process_modal_submission(view_state, user_id)
    # ファイル選択情報を抽出
    file_info = extract_selected_file(view_state['values'])
    
    unless file_info
      return create_validation_error('file_select' => 'ファイルを選択してください')
    end
    
    # 選択されたファイル情報をログ出力
    puts "Selected file: #{file_info[:file_id]}"
    puts "File name: #{file_info[:file_name]}"
    puts "Custom filename: #{file_info[:custom_filename] || '(none)'}"
    
    # 非同期で処理を実行
    Thread.new do
      begin
        # 処理中メッセージを送信
        @slack_client.post_ephemeral(
          user_id,
          user_id,
          "📊 `#{file_info[:file_name]}` の分析を開始しました..."
        )
        
        # Lambda関数を呼び出し（T-06で実装）
        @lambda_invoker.invoke_analysis_lambda({
          file_id: file_info[:file_id],
          file_name: file_info[:custom_filename] || file_info[:file_name],
          user_id: user_id,
          user_email: @slack_client.get_user_email(user_id)
        })
      rescue => e
        puts "Failed to invoke lambda: #{e.message}"
        @slack_client.post_ephemeral(
          user_id,
          user_id,
          "❌ 分析処理の開始に失敗しました: #{e.message}"
        )
      end
    end
    
    # T-06で既存Lambda連携を実装予定
    create_success_response
  end

  # モーダルから選択されたファイル情報を抽出
  def extract_selected_file(values)
    return nil unless values
    
    file_select_data = values.dig('file_select_block', 'file_select', 'selected_option')
    return nil unless file_select_data
    
    custom_filename = values.dig('filename_block', 'filename_override', 'value')
    custom_filename = nil if custom_filename && custom_filename.empty?
    
    {
      file_id: file_select_data['value'],
      file_name: file_select_data.dig('text', 'text'),
      custom_filename: custom_filename
    }
  rescue
    nil
  end

  # モーダルの送信を処理（レガシー処理）
  def handle_view_submission(payload)
    view = payload['view']
    values = view['state']['values']
    user = payload['user']
    
    # 新しい処理に委譲
    process_modal_submission(values, user['id'])
  end

  # バリデーションエラーレスポンス
  def create_validation_error(errors)
    {
      'response_action' => 'errors',
      'errors' => errors
    }
  end

  # 成功レスポンス
  def create_success_response
    {
      'response_action' => 'clear'
    }
  end

  # エラーレスポンス
  def create_error_response(message, status_code)
    {
      'response_type' => 'ephemeral',
      'text' => message
    }
  end

  # ACKレスポンス
  def ack_response
    {
      statusCode: 200,
      headers: { 'Content-Type' => 'application/json' },
      body: ''
    }
  end

  # options リクエストを処理
  def handle_options_request(payload)
    # T-05で実装予定：Google Drive検索のためのexternal_selectオプション提供
    {
      'options' => []
    }
  end

  # モーダルを閉じた時の処理
  def handle_view_closed(payload)
    # 特に処理は不要
    ack_response
  end
end