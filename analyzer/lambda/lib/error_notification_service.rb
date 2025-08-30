require 'json'
require 'time'

# エラー通知サービス
# 非エンジニア向けとエンジニア向けの両方に対応したSlackエラー通知を提供
class ErrorNotificationService
  def initialize(slack_notification_service, logger)
    @slack_service = slack_notification_service
    @logger = logger
  end

  # 統合エラー通知メソッド
  # @param error [Exception] 発生したエラー
  # @param context [Hash] エラーコンテキスト情報
  # @param user_info [Hash] ユーザー情報
  def notify_error(error, context: {}, user_info: {})
    return unless @slack_service

    begin
      error_category = categorize_error(error)
      user_message = build_user_friendly_message(error, error_category, context)
      technical_message = build_technical_message(error, error_category, context)

      # 非エンジニア向けメッセージを送信
      main_result = send_main_error_notification(user_message, user_info, context)
      
      # エンジニア向け詳細情報をスレッド返信で送信
      if main_result[:success] && main_result[:timestamp]
        send_technical_details_thread(main_result[:timestamp], technical_message, context)
      end

      @logger.info("Error notification sent successfully")
      main_result
      
    rescue StandardError => notification_error
      @logger.error("Failed to send error notification: #{notification_error.message}")
      @logger.error(notification_error.backtrace.join("\n")) if notification_error.backtrace
      { success: false, error: notification_error.message }
    end
  end

  private

  # エラーのカテゴリー分類
  def categorize_error(error)
    error_class = error.class.name
    error_message = error.message.downcase

    case error_class
    when /Google::Apis::ClientError/
      case error.respond_to?(:status_code) ? error.status_code : nil
      when 404 then :file_not_found
      when 403 then :access_denied
      when 429 then :network_error # Rate limiting
      else :google_api_error
      end
    when /Google::Apis::AuthorizationError/
      :google_auth_error
    when 'RequestValidator::ValidationError'
      :invalid_request
    when /Net::.*Error/, /HTTP/, /Errno::/
      :network_error
    when /JSON::ParserError/, /JSON::JSONError/
      :json_parse_error
    when /Timeout/, /timeout/i
      :timeout_error
    else
      # メッセージベースの分類（より具体的に）
      case error_message
      when /gemini|ai|analysis/ then :gemini_api_error
      when /slack|channel|bot/ then :slack_api_error
      when /notion|database|page/ then :notion_api_error
      when /s3|bucket|object/ then :s3_error
      when /secret|credential|key/ then :secrets_error
      when /timeout|exceed.*time|time.*out/ then :timeout_error
      when /network|connection|dns/ then :network_error
      else :unknown_error
      end
    end
  end

  # 非エンジニア向けメッセージの構築
  def build_user_friendly_message(error, category, context)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S JST')
    
    case category
    when :file_not_found
      "📄 **ファイルが見つかりません**\n\n" \
      "指定されたファイルにアクセスできませんでした。\n" \
      "• ファイルが削除されていないか確認してください\n" \
      "• ファイルの共有設定を確認してください\n\n" \
      "**発生時刻:** #{timestamp}"
    when :access_denied
      "🔒 **ファイルにアクセスできません**\n\n" \
      "ファイルの読み取り権限がありません。\n" \
      "• ファイルの共有設定を確認してください\n" \
      "• 管理者にアクセス権限の確認を依頼してください\n\n" \
      "**発生時刻:** #{timestamp}"
    when :gemini_api_error
      "🤖 **AI分析でエラーが発生しました**\n\n" \
      "議事録の分析中に問題が発生しました。\n" \
      "• しばらく待ってから再実行してください\n" \
      "• 問題が継続する場合は管理者に連絡してください\n\n" \
      "**発生時刻:** #{timestamp}"
    when :slack_api_error
      "💬 **Slack通知でエラーが発生しました**\n\n" \
      "結果の通知中に問題が発生しました。\n" \
      "• 処理は正常に完了している可能性があります\n" \
      "• 管理者にSlack連携の確認を依頼してください\n\n" \
      "**発生時刻:** #{timestamp}"
    when :notion_api_error
      "📝 **Notion連携でエラーが発生しました**\n\n" \
      "Notionへの保存中に問題が発生しました。\n" \
      "• Slack通知は正常に送信されています\n" \
      "• 管理者にNotion連携の確認を依頼してください\n\n" \
      "**発生時刻:** #{timestamp}"
    when :invalid_request
      "⚠️ **リクエストに問題があります**\n\n" \
      "送信されたデータに不備があります。\n" \
      "• 正しいファイルを選択してください\n" \
      "• 再度実行してください\n\n" \
      "**発生時刻:** #{timestamp}"
    when :timeout_error
      "⏱️ **処理時間が上限に達しました**\n\n" \
      "議事録の処理に時間がかかりすぎました。\n" \
      "• ファイルサイズが大きすぎる可能性があります\n" \
      "• しばらく待ってから再実行してください\n\n" \
      "**発生時刻:** #{timestamp}"
    when :network_error
      "🌐 **ネットワークエラーが発生しました**\n\n" \
      "外部サービスとの通信に問題が発生しました。\n" \
      "• しばらく待ってから再実行してください\n" \
      "• 問題が継続する場合は管理者に連絡してください\n\n" \
      "**発生時刻:** #{timestamp}"
    else
      "❌ **予期しないエラーが発生しました**\n\n" \
      "システムで問題が発生しました。\n" \
      "• 管理者に連絡してください\n" \
      "• エラーの詳細は技術情報をご確認ください\n\n" \
      "**発生時刻:** #{timestamp}"
    end
  end

  # エンジニア向け技術詳細メッセージの構築
  def build_technical_message(error, category, context)
    # 機密情報を除去したコンテキストを作成
    safe_context = sanitize_context(context)
    
    details = {
      error_class: error.class.name,
      error_message: sanitize_error_message(error.message),
      category: category,
      timestamp: Time.now.iso8601,
      context: safe_context,
      backtrace: error.backtrace&.first(10) # 最初の10行のみ
    }

    # HTTP エラーの場合は詳細を追加
    if error.respond_to?(:status_code)
      details[:http_status] = error.status_code
    end

    # AWSリクエストIDがある場合は追加
    if context[:request_id]
      details[:aws_request_id] = context[:request_id]
    end

    "🔧 **技術詳細情報**\n\n```json\n#{JSON.pretty_generate(details)}\n```"
  end

  # コンテキスト情報から機密情報を除去
  def sanitize_context(context)
    safe_context = context.dup
    # 機密情報のキーを除去
    sensitive_keys = [:token, :key, :password, :secret, :credential, :auth]
    safe_context.reject! { |key, _| sensitive_keys.any? { |sensitive| key.to_s.downcase.include?(sensitive.to_s) } }
    safe_context
  end

  # エラーメッセージから機密情報を除去
  def sanitize_error_message(message)
    # APIキー、トークン、パスワードなどのパターンを除去
    sanitized = message.dup
    
    # 一般的な機密情報パターンを除去
    sanitized.gsub!(/[A-Za-z0-9]{32,}/, '[REDACTED_TOKEN]') # 長い英数字文字列
    sanitized.gsub!(/xoxb-[0-9]+-[0-9]+-[0-9]+-[a-z0-9]+/, '[REDACTED_SLACK_TOKEN]') # Slackトークン
    sanitized.gsub!(/AIzaSy[A-Za-z0-9_-]+/, '[REDACTED_API_KEY]') # Google APIキー
    
    sanitized
  end

  # メイン通知の送信
  def send_main_error_notification(user_message, user_info, context)
    message_text = "🚨 **エラーが発生しました**\n\n#{user_message}"
    
    # ユーザー情報を追加
    if user_info[:user_id]
      message_text += "\n\n**実行ユーザー:** <@#{user_info[:user_id]}>"
    elsif user_info[:user_email]
      message_text += "\n\n**実行ユーザー:** #{user_info[:user_email]}"
    end

    # ファイル情報を追加
    if context[:file_id]
      message_text += "\n**ファイルID:** `#{context[:file_id]}`"
    end
    
    if context[:file_name]
      message_text += "\n**ファイル名:** #{context[:file_name]}"
    end

    blocks = [
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: message_text
        }
      }
    ]

    message_payload = {
      text: "エラーが発生しました",
      blocks: blocks
    }

    @slack_service.send_slack_message(message_payload)
  end

  # 技術詳細のスレッド返信送信
  def send_technical_details_thread(thread_ts, technical_message, context)
    blocks = [
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: technical_message
        }
      }
    ]

    # CloudWatch Logs リンクを追加（リクエストIDがある場合）
    if context[:request_id]
      log_url = build_cloudwatch_logs_url(context[:request_id])
      if log_url
        blocks << {
          type: 'actions',
          elements: [
            {
              type: 'button',
              text: {
                type: 'plain_text',
                text: '📋 CloudWatch Logs'
              },
              url: log_url,
              style: 'primary'
            }
          ]
        }
      end
    end

    thread_message = {
      text: "技術詳細情報",
      blocks: blocks
    }

    @slack_service.send_thread_reply(thread_ts, thread_message)
  end

  # CloudWatch Logs URLの構築（簡素化版）
  def build_cloudwatch_logs_url(request_id)
    region = ENV['AWS_REGION'] || 'ap-northeast-1'
    function_name = ENV['AWS_LAMBDA_FUNCTION_NAME']
    
    return nil unless function_name

    # CloudWatch Logs のログストリームに直接リンク
    log_group = "/aws/lambda/#{function_name}"
    
    # シンプルなログストリーム表示URL
    "https://#{region}.console.aws.amazon.com/cloudwatch/home?region=#{region}" \
    "#logsV2:log-groups/log-group/#{URI.encode_www_form_component(log_group)}" \
    "/log-events$3FfilterPattern$3D#{URI.encode_www_form_component(request_id)}"
  rescue StandardError => e
    # URL構築に失敗した場合はログを記録してnilを返す
    @logger&.warn("Failed to build CloudWatch URL: #{e.message}")
    nil
  end
end