require 'spec_helper'
require_relative '../lib/notion_user_manager'
require 'webmock/rspec'

RSpec.describe NotionUserManager do
  let(:api_key) { 'secret_test_key' }
  let(:manager) { described_class.new(api_key) }
  
  describe '#initialize' do
    it 'initializes with API key' do
      expect { manager }.not_to raise_error
    end
    
    it 'raises error without API key' do
      expect { described_class.new(nil) }.to raise_error('Notion API Key is required')
    end
  end
  
  describe '#list_all_users' do
    let(:users_response) do
      {
        'object' => 'list',
        'results' => [
          {
            'id' => 'user-1',
            'type' => 'person',
            'name' => 'User One',
            'person' => { 'email' => 'user1@example.com' },
            'avatar_url' => 'https://example.com/avatar1.png'
          },
          {
            'id' => 'user-2',
            'type' => 'person',
            'name' => 'User Two',
            'person' => { 'email' => 'user2@example.com' },
            'avatar_url' => 'https://example.com/avatar2.png'
          }
        ],
        'has_more' => false
      }
    end
    
    before do
      stub_request(:get, "https://api.notion.com/v1/users")
        .with(
          headers: {
            'Authorization' => "Bearer #{api_key}",
            'Notion-Version' => '2022-06-28'
          },
          query: hash_including({ 'page_size' => '100' })
        )
        .to_return(status: 200, body: users_response.to_json)
    end
    
    it 'returns users indexed by email' do
      users = manager.list_all_users
      expect(users['user1@example.com'][:id]).to eq('user-1')
      expect(users['user2@example.com'][:id]).to eq('user-2')
    end
    
    it 'caches the user list' do
      manager.list_all_users
      # Second call should use cache
      users = manager.list_all_users
      expect(users['user1@example.com'][:id]).to eq('user-1')
    end
    
    context 'with pagination' do
      let(:page1_response) do
        {
          'object' => 'list',
          'results' => [{ 'id' => 'user-1', 'person' => { 'email' => 'user1@example.com' } }],
          'has_more' => true,
          'next_cursor' => 'cursor123'
        }
      end
      
      let(:page2_response) do
        {
          'object' => 'list',
          'results' => [{ 'id' => 'user-2', 'person' => { 'email' => 'user2@example.com' } }],
          'has_more' => false
        }
      end
      
      before do
        stub_request(:get, "https://api.notion.com/v1/users")
          .with(query: hash_including({ 'page_size' => '100' }))
          .to_return(status: 200, body: page1_response.to_json)
          .then
          .to_return(status: 200, body: page2_response.to_json)
      end
      
      it 'handles pagination correctly' do
        users = manager.list_all_users
        expect(users.size).to eq(2)
        expect(users['user1@example.com']).not_to be_nil
        expect(users['user2@example.com']).not_to be_nil
      end
    end
  end
  
  describe '#find_user_by_email' do
    let(:email) { 'user@example.com' }
    
    before do
      stub_request(:get, "https://api.notion.com/v1/users")
        .with(query: hash_including({ 'page_size' => '100' }))
        .to_return(status: 200, body: {
          'object' => 'list',
          'results' => [
            {
              'id' => 'user-123',
              'name' => 'Test User',
              'person' => { 'email' => email }
            }
          ],
          'has_more' => false
        }.to_json)
    end
    
    it 'finds user by email' do
      user = manager.find_user_by_email(email)
      expect(user[:id]).to eq('user-123')
      expect(user[:email]).to eq(email)
    end
    
    it 'returns nil for non-existent email' do
      user = manager.find_user_by_email('notfound@example.com')
      expect(user).to be_nil
    end
    
    it 'caches individual user lookups' do
      manager.find_user_by_email(email)
      # Second call should use cache
      user = manager.find_user_by_email(email)
      expect(user[:id]).to eq('user-123')
    end
  end
  
  describe '#update_task_assignee' do
    let(:page_id) { 'page-123' }
    let(:email) { 'user@example.com' }
    
    before do
      # Mock user lookup
      stub_request(:get, "https://api.notion.com/v1/users")
        .with(query: hash_including({ 'page_size' => '100' }))
        .to_return(status: 200, body: {
          'object' => 'list',
          'results' => [
            {
              'id' => 'user-456',
              'person' => { 'email' => email }
            }
          ],
          'has_more' => false
        }.to_json)
      
      # Mock page update
      stub_request(:patch, "https://api.notion.com/v1/pages/#{page_id}")
        .with(
          body: {
            properties: {
              'assignee' => {
                people: [{ id: 'user-456' }]
              }
            }
          }.to_json
        )
        .to_return(status: 200, body: { 'object' => 'page' }.to_json)
    end
    
    it 'updates task assignee' do
      result = manager.update_task_assignee(page_id, email)
      expect(result).to be true
    end
    
    it 'returns false when user not found' do
      result = manager.update_task_assignee(page_id, 'notfound@example.com')
      expect(result).to be false
    end
  end
  
  describe '#batch_update_task_assignees' do
    let(:task_assignments) do
      {
        'page-1' => 'user1@example.com',
        'page-2' => 'user2@example.com'
      }
    end
    
    before do
      # Mock user lookups
      stub_request(:get, "https://api.notion.com/v1/users")
        .with(query: hash_including({ 'page_size' => '100' }))
        .to_return(status: 200, body: {
          'object' => 'list',
          'results' => [
            { 'id' => 'user-1', 'person' => { 'email' => 'user1@example.com' } },
            { 'id' => 'user-2', 'person' => { 'email' => 'user2@example.com' } }
          ],
          'has_more' => false
        }.to_json)
      
      # Mock page updates
      task_assignments.each do |page_id, _|
        stub_request(:patch, "https://api.notion.com/v1/pages/#{page_id}")
          .to_return(status: 200, body: { 'object' => 'page' }.to_json)
      end
    end
    
    it 'updates multiple task assignees' do
      results = manager.batch_update_task_assignees(task_assignments)
      expect(results['page-1'][:success]).to be true
      expect(results['page-2'][:success]).to be true
    end
  end
  
  describe 'UserCache' do
    let(:cache) { NotionUserManager::UserCache.new(1) } # 1 second TTL
    
    it 'stores and retrieves values' do
      cache.set('key1', 'value1')
      expect(cache.get('key1')).to eq('value1')
    end
    
    it 'expires values after TTL' do
      cache.set('key1', 'value1')
      # Mock Time.now to simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 2)
      expect(cache.get('key1')).to be_nil
    end
    
    it 'refreshes cache by removing expired entries' do
      cache.set('key1', 'value1')
      cache.set('key2', 'value2')
      # Mock Time.now to simulate time passing
      allow(Time).to receive(:now).and_return(Time.now + 2)
      cache.refresh_if_needed
      expect(cache.get('key1')).to be_nil
      expect(cache.get('key2')).to be_nil
    end
  end
end