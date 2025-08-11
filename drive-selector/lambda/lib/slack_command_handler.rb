# frozen_string_literal: true

require 'json'
require_relative 'google_oauth_client'

class SlackCommandHandler
  def initialize
    @oauth_client = GoogleOAuthClient.new
  end

  # Slackコマンドを処理
  def handle(params)
    command = params['command']
    user_id = params['user_id']
    team_id = params['team_id']
    trigger_id = params['trigger_id']
    
    puts "Command: #{command} from user: #{user_id}"
    
    case command
    when '/meet-transcript'
      handle_meet_transcript(user_id, team_id, trigger_id)
    else
      unknown_command_response(command)
    end
  end

  private

  # /meet-transcript コマンドを処理
  def handle_meet_transcript(user_id, team_id, trigger_id)
    # ユーザーが認証済みか確認
    if @oauth_client.authenticated?(user_id)
      # 認証済みの場合、モーダルを開く（T-04で実装）
      open_file_selector_modal(trigger_id)
    else
      # 未認証の場合、認証URLを返す
      auth_url = @oauth_client.generate_auth_url(user_id)
      authentication_required_response(auth_url)
    end
  end

  # ファイル選択モーダルを開く（T-04で詳細実装）
  def open_file_selector_modal(trigger_id)
    # 3秒以内にACKレスポンスを返す
    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate({
        response_type: 'ephemeral',
        text: '📂 Google Driveファイル選択画面を準備中...'
      })
    }
  end

  # 認証が必要な場合のレスポンス
  def authentication_required_response(auth_url)
    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate({
        response_type: 'ephemeral',
        blocks: [
          {
            type: 'section',
            text: {
              type: 'mrkdwn',
              text: '🔐 *Google Drive連携の認証が必要です*\n\nGoogle Driveから議事録ファイルを選択するには、まず認証を行ってください。'
            }
          },
          {
            type: 'actions',
            elements: [
              {
                type: 'button',
                text: {
                  type: 'plain_text',
                  text: '🔗 Googleアカウントで認証',
                  emoji: true
                },
                url: auth_url,
                style: 'primary'
              }
            ]
          },
          {
            type: 'context',
            elements: [
              {
                type: 'mrkdwn',
                text: '認証後、もう一度 `/meet-transcript` コマンドを実行してください。'
              }
            ]
          }
        ]
      })
    }
  end

  # 不明なコマンドの場合のレスポンス
  def unknown_command_response(command)
    {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate({
        response_type: 'ephemeral',
        text: "⚠️ 不明なコマンドです: #{command}"
      })
    }
  end
end