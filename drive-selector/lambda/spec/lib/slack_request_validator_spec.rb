# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SlackRequestValidator do
  let(:validator) { described_class.new }
  let(:signing_secret) { 'test_signing_secret' }
  let(:timestamp) { Time.now.to_i }
  let(:body) { 'token=test&command=%2Fmeet-transcript&user_id=U1234567890' }
  let(:valid_signature) { create_slack_signature(timestamp, body, signing_secret) }

  before do
    ENV['SLACK_SIGNING_SECRET'] = signing_secret
  end

  describe '#valid_request?' do
    let(:headers) do
      {
        'x-slack-signature' => valid_signature,
        'x-slack-request-timestamp' => timestamp.to_s
      }
    end

    context 'with valid request' do
      it 'returns true for valid signature and timestamp' do
        expect(validator.valid_request?(headers, body)).to be true
      end
    end

    context 'with invalid signature' do
      it 'returns false for incorrect signature' do
        headers['x-slack-signature'] = 'v0=invalid_signature'
        expect(validator.valid_request?(headers, body)).to be false
      end

      it 'returns false for missing signature' do
        headers.delete('x-slack-signature')
        expect(validator.valid_request?(headers, body)).to be false
      end

      it 'returns false for signature with wrong version' do
        headers['x-slack-signature'] = 'v1=' + valid_signature.split('=', 2)[1]
        expect(validator.valid_request?(headers, body)).to be false
      end
    end

    context 'with invalid timestamp' do
      it 'returns false for missing timestamp' do
        headers.delete('x-slack-request-timestamp')
        expect(validator.valid_request?(headers, body)).to be false
      end

      it 'returns false for old timestamp (> 5 minutes)' do
        old_timestamp = (Time.now - 301).to_i
        headers['x-slack-request-timestamp'] = old_timestamp.to_s
        headers['x-slack-signature'] = create_slack_signature(old_timestamp, body, signing_secret)
        expect(validator.valid_request?(headers, body)).to be false
      end

      it 'returns false for future timestamp (> 5 minutes)' do
        future_timestamp = (Time.now + 301).to_i
        headers['x-slack-request-timestamp'] = future_timestamp.to_s
        headers['x-slack-signature'] = create_slack_signature(future_timestamp, body, signing_secret)
        expect(validator.valid_request?(headers, body)).to be false
      end
    end

    context 'with missing signing secret' do
      it 'returns false when SLACK_SIGNING_SECRET is not set' do
        ENV.delete('SLACK_SIGNING_SECRET')
        expect(validator.valid_request?(headers, body)).to be false
      end
    end
  end

  describe '#valid_signature?' do
    it 'returns true for valid signature' do
      expect(validator.send(:valid_signature?, valid_signature, timestamp, body)).to be true
    end

    it 'returns false for invalid signature' do
      expect(validator.send(:valid_signature?, 'v0=invalid', timestamp, body)).to be false
    end

    it 'handles timing attack safely with secure_compare' do
      # Test that secure_compare doesn't leak timing information
      start_time = Time.now
      validator.send(:secure_compare, 'a' * 64, 'b' * 64)
      time_diff_1 = Time.now - start_time

      start_time = Time.now
      validator.send(:secure_compare, 'a' * 64, 'a' * 63 + 'b')
      time_diff_2 = Time.now - start_time

      # Time difference should be minimal (timing-safe comparison)
      expect((time_diff_1 - time_diff_2).abs).to be < 0.01
    end
  end

  describe '#valid_timestamp?' do
    it 'returns true for current timestamp' do
      expect(validator.send(:valid_timestamp?, Time.now.to_i)).to be true
    end

    it 'returns true for timestamp within 5 minutes' do
      expect(validator.send(:valid_timestamp?, Time.now.to_i - 299)).to be true
      expect(validator.send(:valid_timestamp?, Time.now.to_i + 299)).to be true
    end

    it 'returns false for timestamp older than 5 minutes' do
      expect(validator.send(:valid_timestamp?, Time.now.to_i - 301)).to be false
    end

    it 'returns false for timestamp more than 5 minutes in future' do
      expect(validator.send(:valid_timestamp?, Time.now.to_i + 301)).to be false
    end

    it 'handles string timestamps' do
      expect(validator.send(:valid_timestamp?, Time.now.to_i.to_s)).to be true
    end
  end

  describe '#secure_compare' do
    it 'returns true for identical strings' do
      expect(validator.send(:secure_compare, 'identical', 'identical')).to be true
    end

    it 'returns false for different strings' do
      expect(validator.send(:secure_compare, 'different', 'strings')).to be false
    end

    it 'returns false for strings of different lengths' do
      expect(validator.send(:secure_compare, 'short', 'longer string')).to be false
    end

    it 'is timing-safe for different strings of same length' do
      # This test ensures the comparison time is consistent
      string1 = 'a' * 32
      string2 = 'b' * 32
      string3 = 'a' * 31 + 'c'

      times = []
      10.times do
        start_time = Time.now
        validator.send(:secure_compare, string1, string2)
        times << (Time.now - start_time)
      end

      times2 = []
      10.times do
        start_time = Time.now
        validator.send(:secure_compare, string1, string3)
        times2 << (Time.now - start_time)
      end

      # Standard deviation should be low (consistent timing)
      avg1 = times.sum / times.size
      avg2 = times2.sum / times2.size
      expect((avg1 - avg2).abs).to be < 0.001
    end
  end
end