# frozen_string_literal: true

require 'aws-sdk-dynamodb'

class DynamoDbTokenStore
  EXPIRY_BUFFER = 300 # トークン期限のバッファ（5分）

  def initialize
    @dynamodb = Aws::DynamoDB::Client.new
    @table_name = ENV['OAUTH_TOKENS_TABLE_NAME']
    
    raise 'OAUTH_TOKENS_TABLE_NAME environment variable not set' unless @table_name
  end

  # ユーザーのトークンを保存
  def save_tokens(slack_user_id, tokens)
    expires_at = Time.now.to_i + (tokens['expires_in'] || 3600)
    current_time = Time.now.to_i

    item = {
      user_id: slack_user_id,
      access_token: tokens['access_token'],
      refresh_token: tokens['refresh_token'],
      expires_at: expires_at,
      created_at: current_time,
      updated_at: current_time
    }

    # refresh_tokenがnilの場合は保存しない
    item.delete(:refresh_token) if tokens['refresh_token'].nil?

    @dynamodb.put_item(
      table_name: @table_name,
      item: item
    )
  end

  # ユーザーのトークンを取得
  def get_tokens(slack_user_id)
    begin
      response = @dynamodb.get_item(
        table_name: @table_name,
        key: { user_id: slack_user_id }
      )

      return nil unless response.item

      token_data = response.item
      
      # トークンの有効期限を確認（バッファ付き）
      if token_data['expires_at'] && token_data['expires_at'] < (Time.now.to_i + EXPIRY_BUFFER)
        return nil
      end

      {
        access_token: token_data['access_token'],
        refresh_token: token_data['refresh_token'],
        expires_at: token_data['expires_at']&.to_i
      }
    rescue Aws::DynamoDB::Errors::ServiceError => e
      puts "DynamoDB get_item error: #{e.message}"
      nil
    end
  end

  # トークンの有効期限を更新（リフレッシュ時に使用）
  def update_tokens(slack_user_id, new_tokens)
    expires_at = Time.now.to_i + (new_tokens['expires_in'] || 3600)
    current_time = Time.now.to_i

    update_expression = 'SET access_token = :access_token, expires_at = :expires_at, updated_at = :updated_at'
    expression_attribute_values = {
      ':access_token' => new_tokens['access_token'],
      ':expires_at' => expires_at,
      ':updated_at' => current_time
    }

    # refresh_tokenが含まれている場合は更新
    if new_tokens['refresh_token']
      update_expression += ', refresh_token = :refresh_token'
      expression_attribute_values[':refresh_token'] = new_tokens['refresh_token']
    end

    @dynamodb.update_item(
      table_name: @table_name,
      key: { user_id: slack_user_id },
      update_expression: update_expression,
      expression_attribute_values: expression_attribute_values
    )
  end

  # ユーザーのトークンを削除
  def delete_tokens(slack_user_id)
    @dynamodb.delete_item(
      table_name: @table_name,
      key: { user_id: slack_user_id }
    )
  end

  # ユーザーが認証済みかチェック
  def authenticated?(slack_user_id)
    tokens = get_tokens(slack_user_id)
    !tokens.nil? && !tokens[:access_token].nil?
  end
end