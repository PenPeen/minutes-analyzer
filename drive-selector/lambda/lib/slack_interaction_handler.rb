# frozen_string_literal: true

require 'json'

class SlackInteractionHandler
  def initialize
    # 必要に応じて依存関係を注入
  end

  # Slackインタラクションを処理
  def handle_interaction(payload)
    # ユーザー情報の検証
    user = payload['user']
    unless user && user['id']
      body_content = create_error_response('ユーザー情報が不足しています', 400)
      return create_http_response(400, body_content)
    end
    
    user_id = user['id']
    type = payload['type']
    
    puts "Interaction type: #{type} from user: #{user_id}"
    
    begin
      case type
      when 'interactive_message'
        # ボタンクリック等の処理
        actions = payload['actions'] || []
        body_content = process_button_click(actions, user_id)
        create_http_response(200, body_content)
      when 'view_submission'
        # モーダル送信の処理
        view_state = payload['view']['state'] rescue nil
        unless view_state
          body_content = create_error_response('無効なモーダルデータです', 400)
          return create_http_response(400, body_content)
        end
        
        body_content = process_modal_submission(view_state, user_id)
        create_http_response(200, body_content)
      else
        body_content = create_error_response("サポートされていないインタラクションタイプ: #{type}", 400)
        create_http_response(400, body_content)
      end
    rescue => e
      puts "Error processing interaction: #{e.message}"
      body_content = create_error_response('処理中にエラーが発生しました', 500)
      create_http_response(500, body_content)
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

  # HTTPレスポンス作成
  def create_http_response(status_code, body_content)
    {
      statusCode: status_code,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(body_content)
    }
  end
end