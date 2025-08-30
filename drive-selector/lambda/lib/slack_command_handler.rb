# frozen_string_literal: true

require 'json'
require 'uri'
require_relative 'google_oauth_client'
require_relative 'google_drive_client'
require_relative 'slack_api_client'
require_relative 'slack_modal_builder'
require_relative 'lambda_invoker'

class SlackCommandHandler
  def initialize
    @oauth_client = GoogleOAuthClient.new
    @slack_client = SlackApiClient.new
    @lambda_invoker = LambdaInvoker.new
  end

  # Slackコマンドを処理
  def handle_command(params, event = nil)
    unless validate_required_params(params)
      body_content = create_error_response('必要なパラメータが不足しています', 400)
      return create_http_response(400, body_content)
    end

    command = params['command']
    user_id = params['user_id']
    team_id = params['team_id']
    trigger_id = params['trigger_id']
    text = params['text']

    puts "Command: #{command} from user: #{user_id}"

    begin
      case command
      when '/meeting-analyzer'
        handle_meeting_analyzer(user_id, team_id, trigger_id, event)
      when '/meeting-analyzer-url'
        handle_meeting_analyzer_url(user_id, team_id, text, event)
      else
        unknown_command_response(command)
      end
    rescue => e
      puts "Error processing command: #{e.message}"
      body_content = create_error_response('認証サービスにアクセスできません。しばらくしてからもう一度お試しください。', 500)
      create_http_response(500, body_content)
    end
  end

  attr_reader :oauth_client

  private

  # 必要なパラメータの検証
  def validate_required_params(params)
    ['user_id', 'command'].all? { |key| params[key] && !params[key].empty? }
  end

  # /meeting-analyzer コマンドを処理
  def handle_meeting_analyzer(user_id, team_id, trigger_id, event = nil)
    # ユーザーが認証済みか確認
    if @oauth_client.authenticated?(user_id)
      # 認証済みの場合、モーダルを開く
      open_file_selector_modal(trigger_id)
    else
      # 未認証の場合、認証URLを返す（動的リダイレクトURI使用）
      auth_url = @oauth_client.generate_auth_url(user_id, nil, event)
      body_content = create_auth_required_response(auth_url)
      create_http_response(200, body_content)
    end
  end

  # ファイル選択モーダルを開く
  def open_file_selector_modal(trigger_id)
    # 先に空のACKを返す
    response = create_empty_response

    # ACK後に非同期でモーダルを開く（Lambdaがスレッド完了を待つよう制御）
    thread = Thread.new do
      begin
        modal = SlackModalBuilder.file_selector_modal
        @slack_client.open_modal(trigger_id, modal)
      rescue => e
        puts "Failed to open modal: #{e.message}"
      end
    end

    # スレッドの完了を待機（Lambdaの早期終了を防ぐ）
    thread.join(1)

    response
  end

  # /meeting-analyzer-url コマンドを処理
  def handle_meeting_analyzer_url(user_id, team_id, text, event = nil)
    # URLが提供されているかチェック
    if text.nil? || text.strip.empty?
      body_content = create_error_response('Google ドキュメントのURLを入力してください。\n例: /meeting-analyzer-url https://docs.google.com/document/d/XXXXX')
      return create_http_response(200, body_content)
    end

    # URLからファイルIDを抽出
    file_id = extract_file_id_from_url(text.strip)
    unless file_id
      body_content = create_error_response('無効なGoogle ドキュメントURLです。正しいURLを入力してください。\n例: https://docs.google.com/document/d/XXXXX')
      return create_http_response(200, body_content)
    end

    # ユーザーが認証済みか確認
    unless @oauth_client.authenticated?(user_id)
      # 未認証の場合、認証URLを返す
      auth_url = @oauth_client.generate_auth_url(user_id, nil, event)
      body_content = create_auth_required_response(auth_url)
      return create_http_response(200, body_content)
    end

    # 認証済みの場合、ファイルの存在とアクセス権限を確認
    begin
      token_data = @oauth_client.get_valid_tokens(user_id)
      access_token = token_data['access_token']
      google_drive_client = GoogleDriveClient.new(access_token)
      
      # ファイル情報を取得してアクセス権限を確認
      file_info = google_drive_client.get_file_info(file_id)
      
      # Analyzer Lambdaにファイル情報を送信
      payload = {
        input_type: 'url',
        file_id: file_id,
        file_name: file_info['name'] || 'Google Document',
        slack_user_id: user_id,
        google_doc_url: text.strip
      }

      @lambda_invoker.invoke_analyzer(payload)

      # 成功レスポンス
      body_content = {
        'response_type' => 'in_channel',
        'text' => "📝 議事録分析を開始しました: #{file_info['name']}"
      }
      create_http_response(200, body_content)

    rescue GoogleDriveClient::AccessDeniedError => e
      puts "Access denied for file_id: #{file_id}, user_id: #{user_id}, error: #{e.message}"
      body_content = create_error_response('指定されたドキュメントへのアクセス権限がありません。ドキュメントの所有者に共有権限の付与を依頼してください。')
      create_http_response(200, body_content)
      
    rescue GoogleDriveClient::FileNotFoundError => e
      puts "File not found: #{file_id}, error: #{e.message}"
      body_content = create_error_response('指定されたドキュメントが見つかりません。URLが正しいことを確認してください。')
      create_http_response(200, body_content)
      
    rescue => e
      puts "Error processing URL command for file_id: #{file_id}, user_id: #{user_id}, error: #{e.message}"
      puts "Backtrace: #{e.backtrace.join("\n")}"
      body_content = create_error_response('ドキュメントの処理中にエラーが発生しました。しばらくしてからもう一度お試しください。')
      create_http_response(200, body_content)
    end
  end

  # Google DocsのURLからファイルIDを抽出
  def extract_file_id_from_url(url)
    return nil if url.nil? || url.strip.empty?
    
    # Google Docs URL patterns:
    # https://docs.google.com/document/d/FILE_ID/edit
    # https://docs.google.com/document/d/FILE_ID/
    # https://docs.google.com/document/d/FILE_ID
    
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

  # 認証が必要な場合のレスポンス
  def create_auth_required_response(auth_url)
    {
      'response_type' => 'ephemeral',
      'text' => 'Google Driveにアクセスするための認証が必要です。安全な接続で認証を行います。',
      'attachments' => [
        {
          'color' => 'good',
          'actions' => [
            {
              'type' => 'button',
              'text' => 'Google Driveを認証',
              'url' => auth_url,
              'style' => 'primary'
            }
          ]
        }
      ]
    }
  end

  # 成功レスポンス（空のレスポンス）
  def create_success_response
    {}
  end

  # 完全に空のレスポンス
  def create_empty_response
    {
      statusCode: 200,
      headers: { 'Content-Type' => 'text/plain' },
      body: ''
    }
  end

  # エラーレスポンス
  def create_error_response(error_message, status_code = 400)
    {
      'response_type' => 'ephemeral',
      'text' => error_message
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

  # 不明なコマンドの場合のレスポンス
  def unknown_command_response(command)
    body_content = {
      'response_type' => 'ephemeral',
      'text' => "未対応のコマンド: #{command}"
    }
    create_http_response(200, body_content)
  end
end
