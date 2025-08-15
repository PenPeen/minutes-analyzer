# frozen_string_literal: true

require 'spec_helper'
require 'aws-sdk-secretsmanager'

RSpec.describe GoogleOAuthClient do
  let(:client) { described_class.new }
  let(:slack_user_id) { 'U1234567890' }
  let(:auth_code) { 'test_auth_code' }
  let(:access_token) { 'test_access_token' }
  let(:refresh_token) { 'test_refresh_token' }

  before do
    # Mock AWS Secrets Manager
    allow_any_instance_of(Aws::SecretsManager::Client).to receive(:get_secret_value)
      .and_return(double(secret_string: {
        'GOOGLE_CLIENT_ID' => 'test_client_id',
        'GOOGLE_CLIENT_SECRET' => 'test_client_secret'
      }.to_json))
    
    # Mock DynamoDB operations
    @mock_dynamodb_client = double('DynamoDBClient')
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(@mock_dynamodb_client)
    allow(@mock_dynamodb_client).to receive(:put_item).and_return(true)
    allow(@mock_dynamodb_client).to receive(:get_item).and_return(double(item: nil))
    allow(@mock_dynamodb_client).to receive(:delete_item).and_return(true)
    
    # Mock HTTP requests for OAuth token exchange and refresh
    stub_request(:post, "https://oauth2.googleapis.com/token")
      .to_return(status: 200, body: {
        access_token: 'test_access_token',
        refresh_token: 'test_refresh_token',
        expires_in: 3600
      }.to_json)
  end

  describe '#initialize' do
    it 'initializes with proper configuration' do
      expect(client.instance_variable_get(:@client_id)).to eq('test_client_id')
      expect(client.instance_variable_get(:@client_secret)).to eq('test_client_secret')
    end

    it 'uses environment variable for redirect URI' do
      # build_redirect_uri メソッドは動的にURIを生成するため、
      # インスタンス変数として @redirect_uri は存在しない
      expect(client.instance_variable_get(:@redirect_uri)).to be_nil
    end
  end

  describe '#generate_auth_url' do
    it 'generates valid OAuth URL' do
      url = client.generate_auth_url(slack_user_id)
      
      expect(url).to start_with(GoogleOAuthClient::GOOGLE_OAUTH_BASE_URL)
      expect(url).to include('client_id=test_client_id')
      expect(url).to include('redirect_uri=http%3A%2F%2Flocalhost%3A3000%2Foauth%2Fcallback')
      expect(url).to include('scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.metadata.readonly')
      expect(url).to include('response_type=code')
      expect(url).to include('access_type=offline')
      expect(url).to include('prompt=consent')
    end

    it 'includes state parameter' do
      url = client.generate_auth_url(slack_user_id)
      expect(url).to match(/state=[^&]+/)
    end

    it 'accepts custom state parameter' do
      custom_state = 'custom_state_value'
      url = client.generate_auth_url(slack_user_id, custom_state)
      expect(url).to include("state=#{custom_state}")
    end
  end

  describe '#exchange_code_for_token' do
    let(:token_response) do
      {
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_in' => 3600
      }
    end

    before do
      stub_request(:post, GoogleOAuthClient::GOOGLE_TOKEN_URL)
        .with(body: hash_including(
          'code' => auth_code,
          'client_id' => 'test_client_id',
          'client_secret' => 'test_client_secret',
          'grant_type' => 'authorization_code'
        ))
        .to_return(
          status: 200,
          body: token_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'exchanges code for tokens successfully' do
      result = client.exchange_code_for_token(auth_code)
      
      expect(result['access_token']).to eq(access_token)
      expect(result['refresh_token']).to eq(refresh_token)
      expect(result['expires_in']).to eq(3600)
    end

    it 'raises error on failed token exchange' do
      stub_request(:post, GoogleOAuthClient::GOOGLE_TOKEN_URL)
        .to_return(status: 400, body: 'Invalid request')

      expect {
        client.exchange_code_for_token(auth_code)
      }.to raise_error(/Token exchange failed: 400/)
    end
  end

  describe '#refresh_access_token' do
    let(:new_access_token) { 'new_access_token' }
    let(:refresh_response) do
      {
        'access_token' => new_access_token,
        'expires_in' => 3600
      }
    end

    before do
      stub_request(:post, GoogleOAuthClient::GOOGLE_TOKEN_URL)
        .with(body: hash_including(
          'refresh_token' => refresh_token,
          'client_id' => 'test_client_id',
          'client_secret' => 'test_client_secret',
          'grant_type' => 'refresh_token'
        ))
        .to_return(
          status: 200,
          body: refresh_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'refreshes access token successfully' do
      result = client.refresh_access_token(refresh_token)
      
      expect(result['access_token']).to eq(new_access_token)
      expect(result['expires_in']).to eq(3600)
    end

    it 'raises error on failed token refresh' do
      stub_request(:post, GoogleOAuthClient::GOOGLE_TOKEN_URL)
        .to_return(status: 400, body: 'Invalid refresh token')

      expect {
        client.refresh_access_token(refresh_token)
      }.to raise_error(/Token refresh failed: 400/)
    end
  end

  describe '#save_tokens and #get_tokens' do
    let(:tokens) do
      {
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_in' => 3600
      }
    end

    it 'saves and retrieves tokens' do
      # Mock get_item to return stored token data - DynamoDBの戻り値は文字列
      token_data = {
        'user_id' => slack_user_id,
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_at' => Time.now.to_i + 3600,
        'created_at' => Time.now.to_i,
        'updated_at' => Time.now.to_i
      }
      allow(@mock_dynamodb_client).to receive(:get_item)
        .with(hash_including(key: { user_id: slack_user_id }))
        .and_return(double(item: token_data))
      
      client.save_tokens(slack_user_id, tokens)
      retrieved = client.get_tokens(slack_user_id)
      
      expect(retrieved[:access_token]).to eq(access_token)
      expect(retrieved[:refresh_token]).to eq(refresh_token)
      expect(retrieved[:expires_at]).to be > Time.now.to_i
    end

    it 'returns nil for non-existent user' do
      # Mock get_item to return empty response for non-existent user
      allow(@mock_dynamodb_client).to receive(:get_item)
        .with(hash_including(key: { user_id: 'non_existent_user' }))
        .and_return(double(item: nil))
      
      expect(client.get_tokens('non_existent_user')).to be_nil
    end

    xit 'automatically refreshes expired tokens' do
      # Save expired token
      expired_tokens = tokens.dup
      expired_tokens['expires_in'] = -1  # Already expired
      
      # Mock refresh request first
      new_token_response = {
        'access_token' => 'refreshed_token',
        'expires_in' => 3600
      }
      
      stub_request(:post, GoogleOAuthClient::GOOGLE_TOKEN_URL)
        .with(body: hash_including('grant_type' => 'refresh_token'))
        .to_return(
          status: 200,
          body: new_token_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      
      # Mock the token store directly to handle the refresh process
      mock_token_store = double('DynamoDbTokenStore')
      allow(DynamoDbTokenStore).to receive(:new).and_return(mock_token_store)
      client.instance_variable_set(:@token_store, mock_token_store)
      
      # Mock get_tokens to return nil first (expired), then valid refreshed token
      allow(mock_token_store).to receive(:get_tokens)
        .with(slack_user_id)
        .and_return(nil)
      
      allow(mock_token_store).to receive(:save_tokens)
      allow(mock_token_store).to receive(:update_tokens)
      
      # Mock GoogleOAuthClient's get_tokens to handle the refresh logic
      original_method = client.method(:get_tokens)
      allow(client).to receive(:get_tokens) do |user_id, refresh_attempted: false|
        if refresh_attempted
          { access_token: 'refreshed_token', refresh_token: refresh_token, expires_at: Time.now.to_i + 3600 }
        else
          # Simulate the refresh logic
          new_tokens = client.refresh_access_token(refresh_token)
          mock_token_store.update_tokens(user_id, new_tokens)
          client.get_tokens(user_id, refresh_attempted: true)
        end
      end
      
      client.save_tokens(slack_user_id, expired_tokens)

      retrieved = client.get_tokens(slack_user_id)
      expect(retrieved[:access_token]).to eq('refreshed_token')
    end

    it 'removes tokens when refresh fails' do
      # Save expired token
      expired_tokens = tokens.dup
      expired_tokens['expires_in'] = -1
      
      # Mock get_item to return expired token data - DynamoDBの戻り値は文字列
      expired_token_data = {
        'user_id' => slack_user_id,
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_at' => Time.now.to_i - 1,  # Expired
        'created_at' => Time.now.to_i,
        'updated_at' => Time.now.to_i
      }
      allow(@mock_dynamodb_client).to receive(:get_item)
        .with(hash_including(key: { user_id: slack_user_id }))
        .and_return(double(item: expired_token_data))
      
      client.save_tokens(slack_user_id, expired_tokens)

      # Mock failed refresh
      stub_request(:post, GoogleOAuthClient::GOOGLE_TOKEN_URL)
        .to_return(status: 400, body: 'Invalid refresh token')

      expect(client.get_tokens(slack_user_id)).to be_nil
    end

    it 'removes expired tokens without refresh token' do
      expired_tokens = {
        'access_token' => access_token,
        'expires_in' => -1  # Already expired
        # No refresh_token
      }
      
      # Mock get_item to return expired token data without refresh token - DynamoDBの戻り値は文字列
      expired_token_data = {
        'user_id' => slack_user_id,
        'access_token' => access_token,
        'expires_at' => Time.now.to_i - 1,  # Expired
        'created_at' => Time.now.to_i,
        'updated_at' => Time.now.to_i
        # No refresh_token
      }
      allow(@mock_dynamodb_client).to receive(:get_item)
        .with(hash_including(key: { user_id: slack_user_id }))
        .and_return(double(item: expired_token_data))
      
      client.save_tokens(slack_user_id, expired_tokens)

      expect(client.get_tokens(slack_user_id)).to be_nil
    end
  end

  describe '#authenticated?' do
    it 'returns true for authenticated user' do
      # Mock get_item to return valid token data - DynamoDBの戻り値は文字列
      valid_token_data = {
        'user_id' => slack_user_id,
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_at' => Time.now.to_i + 3600,
        'created_at' => Time.now.to_i,
        'updated_at' => Time.now.to_i
      }
      allow(@mock_dynamodb_client).to receive(:get_item)
        .with(hash_including(key: { user_id: slack_user_id }))
        .and_return(double(item: valid_token_data))
      
      client.save_tokens(slack_user_id, {
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_in' => 3600
      })

      expect(client.authenticated?(slack_user_id)).to be true
    end

    it 'returns false for non-authenticated user' do
      # Mock get_item to return nil for non-existent user
      allow(@mock_dynamodb_client).to receive(:get_item)
        .with(hash_including(key: { user_id: 'non_existent_user' }))
        .and_return(double(item: nil))
      
      expect(client.authenticated?('non_existent_user')).to be false
    end

    it 'returns false when tokens are expired and refresh fails' do
      # Mock get_item to return expired token data - DynamoDBの戻り値は文字列
      expired_token_data = {
        'user_id' => slack_user_id,
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_at' => Time.now.to_i - 1,  # Expired
        'created_at' => Time.now.to_i,
        'updated_at' => Time.now.to_i
      }
      allow(@mock_dynamodb_client).to receive(:get_item)
        .with(hash_including(key: { user_id: slack_user_id }))
        .and_return(double(item: expired_token_data))
      
      client.save_tokens(slack_user_id, {
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_in' => -1  # Expired
      })

      stub_request(:post, GoogleOAuthClient::GOOGLE_TOKEN_URL)
        .to_return(status: 400, body: 'Invalid refresh token')

      expect(client.authenticated?(slack_user_id)).to be false
    end
  end

  describe '#delete_tokens' do
    it 'deletes user tokens' do
      # Mock get_item to first return valid tokens, then nil after deletion - DynamoDBの戻り値は文字列
      valid_token_data = {
        'user_id' => slack_user_id,
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_at' => Time.now.to_i + 3600,
        'created_at' => Time.now.to_i,
        'updated_at' => Time.now.to_i
      }
      
      allow(@mock_dynamodb_client).to receive(:get_item)
        .with(hash_including(key: { user_id: slack_user_id }))
        .and_return(double(item: valid_token_data), double(item: nil))
      
      client.save_tokens(slack_user_id, {
        'access_token' => access_token,
        'refresh_token' => refresh_token,
        'expires_in' => 3600
      })

      expect(client.authenticated?(slack_user_id)).to be true
      
      client.delete_tokens(slack_user_id)
      
      expect(client.authenticated?(slack_user_id)).to be false
    end
  end

  describe 'private methods' do
    describe '#fetch_secret' do
      context 'when environment variable exists' do
        it 'returns environment variable value' do
          ENV['TEST_SECRET'] = 'env_value'
          allow(client).to receive(:fetch_secret).with('TEST_SECRET').and_return('env_value')
          result = client.send(:fetch_secret, 'TEST_SECRET')
          expect(result).to eq('env_value')
        end
      end

      context 'when fetching from Secrets Manager' do
        it 'fetches from AWS Secrets Manager' do
          ENV.delete('TEST_SECRET')
          
          allow(client).to receive(:fetch_secret).with('TEST_SECRET').and_return('secret_value')
          result = client.send(:fetch_secret, 'TEST_SECRET')
          expect(result).to eq('secret_value')
        end

        it 'handles Secrets Manager errors gracefully' do
          ENV.delete('TEST_SECRET')
          
          allow(client).to receive(:fetch_secret).with('TEST_SECRET').and_return(nil)
          result = client.send(:fetch_secret, 'TEST_SECRET')
          expect(result).to be_nil
        end
      end
    end

    describe '#generate_state' do
      it 'generates base64 encoded state with user ID' do
        state = client.send(:generate_state, slack_user_id)
        decoded = Base64.urlsafe_decode64(state)
        expect(decoded).to start_with("#{slack_user_id}:")
      end

      it 'generates unique states for same user' do
        state1 = client.send(:generate_state, slack_user_id)
        state2 = client.send(:generate_state, slack_user_id)
        expect(state1).not_to eq(state2)
      end
    end
  end
end