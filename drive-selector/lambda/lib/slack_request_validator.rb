# frozen_string_literal: true

require 'openssl'
require 'aws-sdk-secretsmanager'

class SlackRequestValidator
  VERSION = 'v0'
  MAX_TIME_DIFF = 60 * 5 # 5分以内のリクエストのみ許可

  def initialize
    @signing_secret = fetch_signing_secret
  end

  # Slackからのリクエストを検証
  def valid_request?(body, headers)
    timestamp = headers['x-slack-request-timestamp']
    signature = headers['x-slack-signature']
    
    # 必要なヘッダーが存在するか確認
    return false unless timestamp && signature
    
    # タイムスタンプが古すぎないか確認（リプレイ攻撃対策）
    return false unless valid_timestamp?(timestamp)
    
    # 署名を検証
    expected_signature = calculate_signature(timestamp, body)
    secure_compare(signature, expected_signature)
  end

  private

  # Slack Signing Secretを取得
  def fetch_signing_secret
    # 環境変数から取得を試みる
    return ENV['SLACK_SIGNING_SECRET'] if ENV['SLACK_SIGNING_SECRET']
    
    # Secrets Managerから取得
    secrets_client = Aws::SecretsManager::Client.new
    secret_id = ENV['SECRETS_MANAGER_SECRET_ID'] || 'drive-selector-secrets'
    
    begin
      response = secrets_client.get_secret_value(secret_id: secret_id)
      secrets = JSON.parse(response.secret_string)
      secrets['SLACK_SIGNING_SECRET']
    rescue => e
      puts "Failed to fetch signing secret: #{e.message}"
      raise "Signing secret not available"
    end
  end

  # タイムスタンプの有効性を確認
  def valid_timestamp?(timestamp)
    time_diff = (Time.now.to_i - timestamp.to_i).abs
    time_diff <= MAX_TIME_DIFF
  end

  # 署名を計算
  def calculate_signature(timestamp, body)
    sig_basestring = "#{VERSION}:#{timestamp}:#{body}"
    digest = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest::SHA256.new,
      @signing_secret,
      sig_basestring
    )
    "#{VERSION}=#{digest}"
  end

  # タイミング攻撃を防ぐための安全な文字列比較
  def secure_compare(a, b)
    return false unless a.bytesize == b.bytesize
    
    l = a.unpack('C*')
    r = 0
    b.each_byte.with_index { |byte, i| r |= byte ^ l[i] }
    r == 0
  end
end