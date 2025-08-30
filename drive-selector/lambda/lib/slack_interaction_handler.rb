# frozen_string_literal: true

require 'json'
require_relative 'slack_api_client'
require_relative 'slack_modal_builder'
require_relative 'lambda_invoker'
require_relative 'slack_options_provider'

class SlackInteractionHandler
  attr_reader :options_provider

  def initialize
    @slack_client = SlackApiClient.new
    @lambda_invoker = LambdaInvoker.new
    @options_provider = SlackOptionsProvider.new
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
      when 'block_actions'
        handle_block_action(payload)
      when 'view_closed'
        handle_view_closed(payload)
      when 'options', 'block_suggestion'
        # Google Drive検索のためのexternal_selectオプション提供
        body_content = handle_options_request(payload)
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

    # Notion保存オプションを抽出
    save_to_notion = extract_notion_option(view_state['values'])

    # 選択されたファイル情報をログ出力
    puts "Selected file: #{file_info[:file_id]}"
    puts "File name: #{file_info[:file_name]}"
    puts "Save to Notion: #{save_to_notion}"

    begin
      # チャンネルIDを取得（環境変数から）
      channel_id = ENV['SLACK_CHANNEL_ID']
      
      # チャンネルに分析開始メッセージを送信
      if channel_id
        # URL入力の場合はURLを表示、ファイル選択の場合はファイル名を表示
        if file_info[:input_type] == 'url' && file_info[:source_url]
          display_target = "<#{file_info[:source_url]}|#{file_info[:file_name]}>"
        else
          display_target = file_info[:file_name]
        end
        
        # 通知メッセージのブロックを作成
        blocks = [
          {
            type: 'section',
            text: {
              type: 'mrkdwn',
              text: "🔄 *議事録分析を開始しました*"
            }
          },
          {
            type: 'section',
            fields: [
              {
                type: 'mrkdwn',
                text: "*実行者:*\n<@#{user_id}>"
              },
              {
                type: 'mrkdwn',
                text: "*対象ファイル:*\n#{display_target}"
              }
            ]
          },
          {
            type: 'context',
            elements: [
              {
                type: 'mrkdwn',
                text: "分析が完了次第、結果を通知します"
              }
            ]
          }
        ]
        
        @slack_client.post_message(
          channel_id,
          "議事録分析を開始しました",
          blocks
        )
      else
        # チャンネルIDが設定されていない場合は、エフェメラルメッセージをユーザーに送信
        display_text = if file_info[:input_type] == 'url' && file_info[:source_url]
                        "📊 <#{file_info[:source_url]}|#{file_info[:file_name]}> の分析を開始しました..."
                       else
                        "📊 `#{file_info[:file_name]}` の分析を開始しました..."
                       end
        
        @slack_client.post_ephemeral(
          user_id,
          user_id,
          display_text
        )
      end

      # Lambda関数を呼び出し
      lambda_payload = {
        file_id: file_info[:file_id],
        file_name: file_info[:file_name],
        user_id: user_id,
        user_email: @slack_client.get_user_email(user_id),
        save_to_notion: save_to_notion,
        slack_channel_id: channel_id,
        input_type: file_info[:input_type] || 'select'
      }

      # URL入力の場合は追加情報を含める
      if file_info[:input_type] == 'url'
        lambda_payload[:source_url] = file_info[:source_url]
      end

      result = @lambda_invoker.invoke_analysis_lambda(lambda_payload)
      
      puts "Lambda invocation result: #{result.inspect}"
      
      # Lambda呼び出しが失敗した場合
      if result[:status] == 'error'
        error_message = "❌ 分析処理の開始に失敗しました: #{result[:message]}"
        
        if channel_id
          @slack_client.post_message(
            channel_id,
            error_message
          )
        else
          @slack_client.post_ephemeral(
            user_id,
            user_id,
            error_message
          )
        end
      end
    rescue => e
      puts "Failed to invoke lambda: #{e.message}"
      puts e.backtrace
      
      # エラーメッセージを送信
      error_message = "❌ 分析処理の開始に失敗しました: #{e.message}"
      
      if channel_id
        @slack_client.post_message(
          channel_id,
          error_message
        )
      else
        @slack_client.post_ephemeral(
          user_id,
          user_id,
          error_message
        )
      end
    end

    # モーダルを閉じる
    create_success_response
  end

  # モーダルから選択されたファイル情報を抽出
  def extract_selected_file(values)
    return nil unless values

    # URL入力がある場合を優先
    url_input = values.dig('url_input_block', 'url_input', 'value')
    if url_input && !url_input.strip.empty?
      file_id = extract_file_id_from_url(url_input.strip)
      return nil unless file_id

      # ファイル名をURLから取得または生成
      file_name = get_file_name_from_url(url_input.strip) || 'Google Document'
      return {
        file_id: file_id,
        file_name: file_name,
        input_type: 'url',
        source_url: url_input.strip
      }
    end

    # ファイル選択がある場合
    file_select_data = values.dig('file_select_block', 'file_select', 'selected_option')
    return nil unless file_select_data

    {
      file_id: file_select_data['value'],
      file_name: file_select_data.dig('text', 'text'),
      input_type: 'select'
    }
  rescue => e
    puts "Error extracting selected file: #{e.message}"
    nil
  end

  # Notion保存オプションを抽出
  def extract_notion_option(values)
    return false unless values

    selected_options = values.dig('options_block', 'analysis_options', 'selected_options') || []
    selected_options.any? { |opt| opt['value'] == 'save_to_notion' }
  rescue => e
    puts "Failed to extract Notion option: #{e.message}"
    false
  end


  # モーダルの送信を処理（レガシー処理）
  def handle_view_submission(payload)
    view = payload['view']
    view_state = view['state']
    user = payload['user']

    # 新しい処理に委譲
    response_data = process_modal_submission(view_state, user['id'])

    # テストがHTTPレスポンス形式を期待している場合への対応
    if response_data.is_a?(Hash) && response_data.key?('response_action')
      # バリデーションエラーでも200で返す（Slackの要求仕様）
      create_http_response(200, response_data)
    else
      create_http_response(200, response_data)
    end
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
    # ユーザーIDと検索クエリを取得
    user_id = payload['user']['id']
    value = payload['value'] || ''

    # Google Drive検索を実行
    result = @options_provider.provide_file_options(user_id, value)

    result
  end

  # モーダルを閉じた時の処理
  def handle_view_closed(payload)
    # 特に処理は不要
    ack_response
  end

  # HTTPレスポンス作成
  def create_http_response(status_code, body_content)
    {
      statusCode: status_code,
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate(body_content)
    }
  end

  # Google DocsのURLからファイルIDを抽出
  def extract_file_id_from_url(url)
    return nil if url.nil? || url.strip.empty?
    
    patterns = [
      %r{docs\.google\.com/document/d/([a-zA-Z0-9-_]+)},
      %r{drive\.google\.com/file/d/([a-zA-Z0-9-_]+)},
      %r{drive\.google\.com/open\?id=([a-zA-Z0-9-_]+)}
    ]
    
    cleaned_url = url.strip
    patterns.each do |pattern|
      match = cleaned_url.match(pattern)
      return match[1] if match && !match[1].empty?
    end
    
    nil
  end

  # URLからファイル名を取得（簡易版）
  def get_file_name_from_url(url)
    # 実際のファイル名はGoogleDriveClientで取得する
    # ここでは仮の名前を返す
    "Google Document from URL"
  end
end
