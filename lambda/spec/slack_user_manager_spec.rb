require 'spec_helper'
require_relative '../lib/slack_user_manager'
require 'webmock/rspec'

RSpec.describe SlackUserManager do
  let(:bot_token) { 'xoxb-test-token' }
  let(:manager) { described_class.new(bot_token) }
  
  describe '#initialize' do
    it 'initializes with bot token' do
      expect { manager }.not_to raise_error
    end
    
    it 'raises error without bot token' do
      expect { described_class.new(nil) }.to raise_error('Slack Bot Token is required')
    end
  end
  
  describe '#lookup_user_by_email' do
    let(:email) { 'user@example.com' }
    let(:user_response) do
      {
        'ok' => true,
        'user' => {
          'id' => 'U12345',
          'name' => 'testuser',
          'real_name' => 'Test User',
          'profile' => {
            'display_name' => 'Test',
            'email' => email
          },
          'is_bot' => false,
          'is_admin' => false
        }
      }
    end
    
    before do
      stub_request(:post, "https://slack.com/api/users.lookupByEmail")
        .with(
          headers: { 'Authorization' => "Bearer #{bot_token}" },
          body: { email: email }.to_json
        )
        .to_return(status: 200, body: user_response.to_json)
    end
    
    it 'returns user information' do
      user = manager.lookup_user_by_email(email)
      expect(user[:id]).to eq('U12345')
      expect(user[:name]).to eq('testuser')
      expect(user[:email]).to eq(email)
    end
    
    it 'caches user information' do
      manager.lookup_user_by_email(email)
      # Second call should not make HTTP request (cached)
      user = manager.lookup_user_by_email(email)
      expect(user[:id]).to eq('U12345')
    end
    
    context 'when user not found' do
      before do
        stub_request(:post, "https://slack.com/api/users.lookupByEmail")
          .to_return(status: 200, body: { 'ok' => false, 'error' => 'users_not_found' }.to_json)
      end
      
      it 'returns nil' do
        user = manager.lookup_user_by_email('notfound@example.com')
        expect(user).to be_nil
      end
    end
    
    context 'when rate limited' do
      before do
        stub_request(:post, "https://slack.com/api/users.lookupByEmail")
          .to_return(
            { status: 429, headers: { 'Retry-After' => '1' }, body: { 'ok' => false, 'error' => 'rate_limited' }.to_json },
            { status: 200, body: user_response.to_json }
          )
        
        # Mock sleep to avoid actual waiting
        allow_any_instance_of(SlackUserManager::RateLimiter).to receive(:sleep)
      end
      
      it 'retries after rate limit' do
        user = manager.lookup_user_by_email(email)
        expect(user[:id]).to eq('U12345')
      end
    end
  end
  
  describe '#generate_mention' do
    it 'generates mention format from user ID' do
      mention = manager.generate_mention('U12345')
      expect(mention).to eq('<@U12345>')
    end
    
    it 'returns nil for nil user ID' do
      mention = manager.generate_mention(nil)
      expect(mention).to be_nil
    end
  end
  
  describe '#generate_mention_from_email' do
    let(:email) { 'user@example.com' }
    
    before do
      stub_request(:post, "https://slack.com/api/users.lookupByEmail")
        .to_return(status: 200, body: {
          'ok' => true,
          'user' => {
            'id' => 'U12345',
            'name' => 'testuser',
            'profile' => { 'email' => email }
          }
        }.to_json)
    end
    
    it 'generates mention from email address' do
      mention = manager.generate_mention_from_email(email)
      expect(mention).to eq('<@U12345>')
    end
  end
  
  describe '#batch_lookup_users' do
    let(:emails) { ['user1@example.com', 'user2@example.com'] }
    
    before do
      emails.each_with_index do |email, i|
        stub_request(:post, "https://slack.com/api/users.lookupByEmail")
          .with(body: { email: email }.to_json)
          .to_return(status: 200, body: {
            'ok' => true,
            'user' => {
              'id' => "U1234#{i}",
              'name' => "user#{i}",
              'profile' => { 'email' => email }
            }
          }.to_json)
      end
    end
    
    it 'looks up multiple users' do
      results = manager.batch_lookup_users(emails)
      expect(results.keys).to match_array(emails)
      expect(results['user1@example.com'][:id]).to eq('U12340')
      expect(results['user2@example.com'][:id]).to eq('U12341')
    end
  end
  
  describe '#list_all_users' do
    let(:users_response) do
      {
        'ok' => true,
        'members' => [
          { 'id' => 'U1', 'name' => 'user1' },
          { 'id' => 'U2', 'name' => 'user2' }
        ],
        'response_metadata' => { 'next_cursor' => '' }
      }
    end
    
    before do
      stub_request(:post, "https://slack.com/api/users.list")
        .to_return(status: 200, body: users_response.to_json)
    end
    
    it 'returns all users' do
      users = manager.list_all_users
      expect(users.size).to eq(2)
      expect(users.first['id']).to eq('U1')
    end
  end
  
  describe 'RateLimiter' do
    let(:rate_limiter) { SlackUserManager::RateLimiter.new(2) }
    
    it 'throttles requests' do
      # Mock sleep to avoid actual waiting
      allow(rate_limiter).to receive(:sleep)
      
      # First 2 requests should pass
      2.times { rate_limiter.throttle }
      
      # 3rd request should trigger throttling
      expect(rate_limiter).to receive(:sleep).at_least(:once)
      rate_limiter.throttle
    end
  end
end