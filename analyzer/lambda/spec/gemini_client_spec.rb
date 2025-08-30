require 'spec_helper'
require_relative '../lib/gemini_client'

RSpec.describe GeminiClient do
  let(:api_key) { 'test-api-key' }
  let(:logger) { double('logger') }
  let(:mock_s3_client) { double('S3Client') }
  let(:gemini_client) { GeminiClient.new(api_key, logger, mock_s3_client, 'local') }
  let(:test_text) { 'This is a meeting transcript to be summarized.' }
  let(:mock_http) { double('Net::HTTP') }
  let(:mock_response) { double('Net::HTTPResponse') }
  let(:prompt_text) { 'Test prompt text' }
  let(:output_schema) { { 'type' => 'object', 'properties' => {} } }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
    allow(Net::HTTP).to receive(:new).and_return(mock_http)
    allow(mock_http).to receive(:use_ssl=)
    allow(mock_http).to receive(:read_timeout=)
    allow(mock_http).to receive(:open_timeout=)
    allow(mock_http).to receive(:request).and_return(mock_response)
    allow(mock_s3_client).to receive(:get_prompt).and_return(prompt_text)
    allow(mock_s3_client).to receive(:get_output_schema).and_return(output_schema)
  end

  describe '#analyze_meeting' do
    let(:transcript_text) { "2025年1月15日\n\n新機能リリース進捗確認ミーティング\n録音済み 平岡健児氏 小田まゆか\n\nまとめ\n..." }

    context 'when API call is successful' do
      let(:analysis_result) do
        {
          'meeting_summary' => {
            'title' => 'Test Meeting',
            'date' => '2025-08-04'
          },
          'decisions' => [],
          'actions' => []
        }
      end

      let(:successful_response_body) do
        {
          candidates: [
            {
              content: {
                parts: [
                  { text: analysis_result.to_json }
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

      it 'returns the parsed analysis result' do
        result = gemini_client.analyze_meeting(transcript_text)
        expect(result).to eq(analysis_result)
      end

      it 'logs API call and response status' do
        expect(logger).to receive(:info).with('Calling Gemini API for meeting analysis...')
        expect(logger).to receive(:info).with('Gemini API response status: 200')
        expect(logger).to receive(:info).with('Successfully parsed structured response from Gemini')

        gemini_client.analyze_meeting(transcript_text)
      end

      it 'makes HTTP request with correct parameters' do
        request = double('Net::HTTP::Post')
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)

        gemini_client.analyze_meeting(transcript_text)

        expect(Net::HTTP).to have_received(:new).with('generativelanguage.googleapis.com', 443)
        expect(mock_http).to have_received(:use_ssl=).with(true)
        expect(request).to have_received(:[]=).with('content-type', 'application/json')
      end

      it 'sends correct request body with structured output' do
        request = double('Net::HTTP::Post')
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)

        gemini_client.analyze_meeting(transcript_text)

        expected_body = {
          contents: [
            {
              parts: [
                { text: "#{prompt_text}\n\n# 入力議事録:\n#{transcript_text}" }
              ]
            }
          ],
          generationConfig: {
            response_mime_type: "application/json",
            response_schema: output_schema,
            maxOutputTokens: 327680,
            temperature: 0.1
          }
        }.to_json

        expect(request).to have_received(:body=).with(expected_body)
      end

      it 'retrieves prompt and schema from S3' do
        expect(mock_s3_client).to receive(:get_prompt)
        expect(mock_s3_client).to receive(:get_output_schema)

        gemini_client.analyze_meeting(transcript_text)
      end
    end

    context 'when API response does not contain content' do
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
        expect(logger).to receive(:error).with("Failed to extract content from Gemini response: #{parsed_response}")
        expect { gemini_client.analyze_meeting(transcript_text) }.to raise_error('Content could not be generated from API response.')
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
        expect { gemini_client.analyze_meeting(transcript_text) }.to raise_error(
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
        expect { gemini_client.analyze_meeting(transcript_text) }.to raise_error(
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
        expect { gemini_client.analyze_meeting(transcript_text) }.to raise_error(
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
        expect { gemini_client.analyze_meeting(transcript_text) }.to raise_error(
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
        expect { gemini_client.analyze_meeting(transcript_text) }.to raise_error(
          'Gemini API request failed. Status: 400, Details: Unknown API error'
        )
      end
    end

    context 'when response is not valid JSON' do
      let(:non_json_response_body) do
        {
          candidates: [
            {
              content: {
                parts: [
                  { text: 'This is not JSON' }
                ]
              }
            }
          ]
        }.to_json
      end

      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(mock_response).to receive(:code).and_return('200')
        allow(mock_response).to receive(:body).and_return(non_json_response_body)
      end

      it 'logs error and returns raw content' do
        expect(logger).to receive(:error).with(/Failed to parse Gemini response as JSON/)
        expect(logger).to receive(:error).with(/Raw content/)

        result = gemini_client.analyze_meeting(transcript_text)
        expect(result).to eq('This is not JSON')
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
