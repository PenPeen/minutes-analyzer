require 'spec_helper'
require_relative '../lib/gemini_client'

RSpec.describe GeminiClient do
  let(:api_key) { 'test-api-key' }
  let(:logger) { double('logger') }
  let(:gemini_client) { GeminiClient.new(api_key, logger) }
  let(:test_text) { 'This is a meeting transcript to be summarized.' }
  let(:mock_http) { double('Net::HTTP') }
  let(:mock_response) { double('Net::HTTPResponse') }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:request).and_return(mock_response)
  end

  describe '#summarize' do
    context 'when API call is successful' do
      let(:successful_response_body) do
        {
          candidates: [
            {
              content: {
                parts: [
                  { text: 'This is a summary of the meeting.' }
                ]
              }
            }
          ]
        }.to_json
      end

      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:code).and_return('200')
        allow(mock_response).to receive(:body).and_return(successful_response_body)
      end

      it 'returns the summary text' do
        result = gemini_client.summarize(test_text)
        expect(result).not_to eq('This is a summary of the meeting.')
      end

      it 'logs API call and response status' do
        expect(logger).to receive(:info).with('Calling Gemini API...')
        expect(logger).to receive(:info).with('Gemini API response status: 200')

        gemini_client.summarize(test_text)
      end

      it 'makes HTTP request with correct parameters' do
        request = double('Net::HTTP::Post')
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)

        gemini_client.summarize(test_text)

        expect(Net::HTTP).to have_received(:new).with('generativelanguage.googleapis.com', 443)
        expect(mock_http).to have_received(:use_ssl=).with(true)
        expect(request).to have_received(:[]=).with('content-type', 'application/json')
      end

      it 'sends correct request body' do
        request = double('Net::HTTP::Post')
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)

        gemini_client.summarize(test_text)

        expected_body = {
          contents: [
            {
              parts: [
                { text: "Please summarize the following meeting transcript:\n\n#{test_text}" }
              ]
            }
          ],
          generationConfig: {
            maxOutputTokens: 1024
          }
        }.to_json

        expect(request).to have_received(:body=).with(expected_body)
      end
    end

    context 'when API response does not contain summary' do
      let(:incomplete_response_body) do
        {
          candidates: [
            {
              content: {
                parts: []
              }
            }
          ]
        }.to_json
      end

      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:code).and_return('200')
        allow(mock_response).to receive(:body).and_return(incomplete_response_body)
      end

      it 'logs error and raises exception' do
        parsed_response = JSON.parse(incomplete_response_body)
        expect(logger).to receive(:error).with("Failed to extract summary from Gemini response: #{parsed_response}")
        expect { gemini_client.summarize(test_text) }.to raise_error('Summary could not be generated from API response.')
      end
    end

    context 'when API returns authentication error' do
      let(:auth_error_body) do
        {
          error: {
            message: 'API key not valid'
          }
        }.to_json
      end

      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_response).to receive(:code).and_return('401')
        allow(mock_response).to receive(:body).and_return(auth_error_body)
      end

      it 'logs error and raises authentication exception' do
        expect(logger).to receive(:error).with('Gemini API request failed with status 401: API key not valid')
        expect { gemini_client.summarize(test_text) }.to raise_error(
          'Authentication failed with Gemini API. Please check your API key. Details: API key not valid'
        )
      end
    end

    context 'when API returns forbidden error' do
      let(:forbidden_error_body) do
        {
          error: {
            message: 'Access denied'
          }
        }.to_json
      end

      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_response).to receive(:code).and_return('403')
        allow(mock_response).to receive(:body).and_return(forbidden_error_body)
      end

      it 'logs error and raises authentication exception' do
        expect(logger).to receive(:error).with('Gemini API request failed with status 403: Access denied')
        expect { gemini_client.summarize(test_text) }.to raise_error(
          'Authentication failed with Gemini API. Please check your API key. Details: Access denied'
        )
      end
    end

    context 'when API returns server error' do
      let(:server_error_body) do
        {
          error: {
            message: 'Internal server error'
          }
        }.to_json
      end

      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_response).to receive(:code).and_return('500')
        allow(mock_response).to receive(:body).and_return(server_error_body)
      end

      it 'logs error and raises general API exception' do
        expect(logger).to receive(:error).with('Gemini API request failed with status 500: Internal server error')
        expect { gemini_client.summarize(test_text) }.to raise_error(
          'Gemini API request failed. Status: 500, Details: Internal server error'
        )
      end
    end

    context 'when API returns invalid JSON error response' do
      let(:invalid_json_response) { 'Invalid JSON response' }

      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_response).to receive(:code).and_return('400')
        allow(mock_response).to receive(:body).and_return(invalid_json_response)
      end

      it 'handles invalid JSON error response gracefully' do
        expect(logger).to receive(:error).with('Gemini API request failed with status 400: Invalid JSON response')
        expect { gemini_client.summarize(test_text) }.to raise_error(
          'Gemini API request failed. Status: 400, Details: Invalid JSON response'
        )
      end
    end

    context 'when API returns error without message' do
      let(:error_without_message) { '{}' }

      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_response).to receive(:code).and_return('400')
        allow(mock_response).to receive(:body).and_return(error_without_message)
      end

      it 'uses default error message' do
        expect(logger).to receive(:error).with('Gemini API request failed with status 400: Unknown API error')
        expect { gemini_client.summarize(test_text) }.to raise_error(
          'Gemini API request failed. Status: 400, Details: Unknown API error'
        )
      end
    end
  end

  describe 'constants' do
    it 'has correct API URL' do
      expect(GeminiClient::GEMINI_API_URL).to eq(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'
      )
    end
  end
end
