require 'net/http'
require 'uri'
require 'json'
require_relative 's3_client'

class GeminiClient
  GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'.freeze

  def initialize(api_key, logger, s3_client = nil, environment = 'local')
    @api_key = api_key
    @logger = logger
    @s3_client = s3_client || S3Client.new(@logger, environment)
    @environment = environment
  end

  def analyze_meeting(transcript_text)
    uri = URI.parse("#{GEMINI_API_URL}?key=#{@api_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 900
    http.open_timeout = 900

    request = Net::HTTP::Post.new(uri.request_uri)
    request['content-type'] = 'application/json'
    request.body = build_analysis_request_body(transcript_text)

    @logger.info("Calling Gemini API for meeting analysis...")
    response = http.request(request)
    @logger.info("Gemini API response status: #{response.code}")

    handle_response(response)
  end

  def summarize(text)
    # Legacy method for backward compatibility
    analyze_meeting(text)
  end

  private

  def build_analysis_request_body(transcript_text)
    prompt = @s3_client.get_prompt
    schema = @s3_client.get_output_schema

    # Construct the full prompt with the transcript text
    full_prompt = "#{prompt}\n\n# 入力議事録:\n#{transcript_text}"

    {
      contents: [
        {
          parts: [
            { text: full_prompt }
          ]
        }
      ],
      generationConfig: {
        response_mime_type: "application/json",
        response_schema: schema,
        maxOutputTokens: 327680,
        temperature: 0.1
      }
    }.to_json
  end

  def handle_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      handle_error_response(response)
    end

    parsed_response = JSON.parse(response.body)
    content = parsed_response.dig("candidates", 0, "content", "parts", 0, "text")

    unless content
      @logger.error("Failed to extract content from Gemini response: #{parsed_response}")
      raise "Content could not be generated from API response."
    end

    # Parse the JSON response from Gemini
    begin
      analysis_result = JSON.parse(content, symbolize_names: true)
      @logger.info("Successfully parsed structured response from Gemini")
      analysis_result
    rescue JSON::ParserError => e
      @logger.error("Failed to parse Gemini response as JSON: #{e.message}")
      @logger.error("Raw content: #{content}")
      # Fallback to returning raw content if not valid JSON
      content
    end
  end

  def handle_error_response(response)
    begin
      error_body = JSON.parse(response.body)
      error_message = error_body.dig("error", "message") || "Unknown API error"
    rescue JSON::ParserError
      error_message = "Invalid JSON response"
    end

    @logger.error("Gemini API request failed with status #{response.code}: #{error_message}")

    case response.code.to_i
    when 401, 403
      raise "Authentication failed with Gemini API. Please check your API key. Details: #{error_message}"
    else
      raise "Gemini API request failed. Status: #{response.code}, Details: #{error_message}"
    end
  end
end
