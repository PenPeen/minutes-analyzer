# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/dynamodb_token_store'

RSpec.describe DynamoDbTokenStore do
  let(:table_name) { 'test-oauth-tokens' }
  let(:mock_dynamodb) { double('Aws::DynamoDB::Client') }
  let(:token_store) { DynamoDbTokenStore.new }
  let(:slack_user_id) { 'U12345678' }
  let(:tokens) do
    {
      'access_token' => 'ya29.test_access_token',
      'refresh_token' => 'refresh_token_123',
      'expires_in' => 3600
    }
  end

  before do
    ENV['OAUTH_TOKENS_TABLE_NAME'] = table_name
    allow(Aws::DynamoDB::Client).to receive(:new).and_return(mock_dynamodb)
  end

  after do
    ENV.delete('OAUTH_TOKENS_TABLE_NAME')
  end

  describe '#initialize' do
    context 'when OAUTH_TOKENS_TABLE_NAME is not set' do
      before { ENV.delete('OAUTH_TOKENS_TABLE_NAME') }

      it 'raises an error' do
        expect { DynamoDbTokenStore.new }.to raise_error('OAUTH_TOKENS_TABLE_NAME environment variable not set')
      end
    end

    context 'when OAUTH_TOKENS_TABLE_NAME is set' do
      it 'initializes successfully' do
        expect { DynamoDbTokenStore.new }.not_to raise_error
      end
    end
  end

  describe '#save_tokens' do
    it 'saves tokens to DynamoDB' do
      expected_item = {
        user_id: slack_user_id,
        access_token: tokens['access_token'],
        refresh_token: tokens['refresh_token'],
        expires_at: kind_of(Integer),
        created_at: kind_of(Integer),
        updated_at: kind_of(Integer)
      }

      expect(mock_dynamodb).to receive(:put_item).with(
        table_name: table_name,
        item: expected_item
      )

      token_store.save_tokens(slack_user_id, tokens)
    end

    context 'when refresh_token is nil' do
      let(:tokens_without_refresh) do
        {
          'access_token' => 'ya29.test_access_token',
          'refresh_token' => nil,
          'expires_in' => 3600
        }
      end

      it 'does not include refresh_token in the item' do
        expected_item = {
          user_id: slack_user_id,
          access_token: tokens_without_refresh['access_token'],
          expires_at: kind_of(Integer),
          created_at: kind_of(Integer),
          updated_at: kind_of(Integer)
        }

        expect(mock_dynamodb).to receive(:put_item).with(
          table_name: table_name,
          item: expected_item
        )

        token_store.save_tokens(slack_user_id, tokens_without_refresh)
      end
    end
  end

  describe '#get_tokens' do
    let(:current_time) { Time.now.to_i }
    let(:valid_expires_at) { current_time + 1800 } # 30 minutes from now

    context 'when tokens exist and are valid' do
      let(:dynamodb_response) do
        double('response', item: {
          'user_id' => slack_user_id,
          'access_token' => tokens['access_token'],
          'refresh_token' => tokens['refresh_token'],
          'expires_at' => valid_expires_at
        })
      end

      it 'returns the tokens' do
        expect(mock_dynamodb).to receive(:get_item).with(
          table_name: table_name,
          key: { user_id: slack_user_id }
        ).and_return(dynamodb_response)

        result = token_store.get_tokens(slack_user_id)

        expect(result).to eq({
          access_token: tokens['access_token'],
          refresh_token: tokens['refresh_token'],
          expires_at: valid_expires_at
        })
      end
    end

    context 'when tokens do not exist' do
      let(:dynamodb_response) { double('response', item: nil) }

      it 'returns nil' do
        expect(mock_dynamodb).to receive(:get_item).with(
          table_name: table_name,
          key: { user_id: slack_user_id }
        ).and_return(dynamodb_response)

        result = token_store.get_tokens(slack_user_id)
        expect(result).to be_nil
      end
    end

    context 'when tokens are expired' do
      let(:expired_expires_at) { current_time - 100 } # Expired 100 seconds ago
      let(:dynamodb_response) do
        double('response', item: {
          'user_id' => slack_user_id,
          'access_token' => tokens['access_token'],
          'refresh_token' => tokens['refresh_token'],
          'expires_at' => expired_expires_at
        })
      end

      it 'returns nil' do
        expect(mock_dynamodb).to receive(:get_item).with(
          table_name: table_name,
          key: { user_id: slack_user_id }
        ).and_return(dynamodb_response)

        result = token_store.get_tokens(slack_user_id)
        expect(result).to be_nil
      end
    end

    context 'when DynamoDB raises an error' do
      it 'returns nil and logs the error' do
        expect(mock_dynamodb).to receive(:get_item).twice.and_raise(
          Aws::DynamoDB::Errors::ServiceError.new('context', 'Test error')
        )
        expect { token_store.get_tokens(slack_user_id) }.to output(/DynamoDB get_item error/).to_stdout

        result = token_store.get_tokens(slack_user_id)
        expect(result).to be_nil
      end
    end
  end

  describe '#update_tokens' do
    let(:new_tokens) do
      {
        'access_token' => 'new_access_token',
        'refresh_token' => 'new_refresh_token',
        'expires_in' => 3600
      }
    end

    it 'updates tokens in DynamoDB' do
      expect(mock_dynamodb).to receive(:update_item).with(
        table_name: table_name,
        key: { user_id: slack_user_id },
        update_expression: 'SET access_token = :access_token, expires_at = :expires_at, updated_at = :updated_at, refresh_token = :refresh_token',
        expression_attribute_values: {
          ':access_token' => new_tokens['access_token'],
          ':expires_at' => kind_of(Integer),
          ':updated_at' => kind_of(Integer),
          ':refresh_token' => new_tokens['refresh_token']
        }
      )

      token_store.update_tokens(slack_user_id, new_tokens)
    end

    context 'when refresh_token is not provided' do
      let(:new_tokens_without_refresh) do
        {
          'access_token' => 'new_access_token',
          'expires_in' => 3600
        }
      end

      it 'does not include refresh_token in update' do
        expect(mock_dynamodb).to receive(:update_item).with(
          table_name: table_name,
          key: { user_id: slack_user_id },
          update_expression: 'SET access_token = :access_token, expires_at = :expires_at, updated_at = :updated_at',
          expression_attribute_values: {
            ':access_token' => new_tokens_without_refresh['access_token'],
            ':expires_at' => kind_of(Integer),
            ':updated_at' => kind_of(Integer)
          }
        )

        token_store.update_tokens(slack_user_id, new_tokens_without_refresh)
      end
    end
  end

  describe '#delete_tokens' do
    it 'deletes tokens from DynamoDB' do
      expect(mock_dynamodb).to receive(:delete_item).with(
        table_name: table_name,
        key: { user_id: slack_user_id }
      )

      token_store.delete_tokens(slack_user_id)
    end
  end

  describe '#authenticated?' do
    context 'when user has valid tokens' do
      before do
        allow(token_store).to receive(:get_tokens).with(slack_user_id).and_return({
          access_token: 'valid_token',
          refresh_token: 'refresh_token',
          expires_at: Time.now.to_i + 1800
        })
      end

      it 'returns true' do
        expect(token_store.authenticated?(slack_user_id)).to be true
      end
    end

    context 'when user has no tokens' do
      before do
        allow(token_store).to receive(:get_tokens).with(slack_user_id).and_return(nil)
      end

      it 'returns false' do
        expect(token_store.authenticated?(slack_user_id)).to be false
      end
    end
  end
end