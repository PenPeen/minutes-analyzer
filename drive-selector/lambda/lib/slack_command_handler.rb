# frozen_string_literal: true

require 'json'
require_relative 'google_oauth_client'
require_relative 'slack_api_client'
require_relative 'slack_modal_builder'

class SlackCommandHandler
  def initialize
    @oauth_client = GoogleOAuthClient.new
    @slack_client = SlackApiClient.new
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
    
    puts "Command: #{command} from user: #{user_id}"
    
    begin
      case command
      when '/meeting-analyzer'
        handle_meeting_analyzer(user_id, team_id, trigger_id, event)
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
    # モーダルを構築
    modal = SlackModalBuilder.file_selector_modal
    
    # Lambda環境ではThreadが期待通り動作しないため、
    # 別のLambda関数を非同期Invokeするか、
    # ACK後にモーダルを開く処理を同期的に実行
    begin
      @slack_client.open_modal(trigger_id, modal)
    rescue => e
      puts "Failed to open modal: #{e.message}"
      # エラーが発生してもACKは返す
    end
    
    # 3秒以内にACKレスポンスを返す（成功メッセージ付き）
    body_content = create_success_response
    create_http_response(200, body_content)
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

  # 成功レスポンス
  def create_success_response
    {
      'response_type' => 'ephemeral',
      'text' => ''
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