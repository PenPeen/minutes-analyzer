require 'net/http'
require 'uri'
require 'json'

class GeminiClient
  GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'.freeze

  def initialize(api_key, logger)
    @api_key = api_key
    @logger = logger
  end

  def summarize(text)
    uri = URI.parse("#{GEMINI_API_URL}?key=#{@api_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri)
    request['content-type'] = 'application/json'
    request.body = build_request_body(text)

    @logger.info("Calling Gemini API...")
    response = http.request(request)
    @logger.info("Gemini API response status: #{response.code}")

    handle_response(response)
  end

  private

  def build_request_body(text)
    {
      contents: [
        {
          parts: [
            { text: "Please summarize the following meeting transcript:\n\n#{text}" }
          ]
        }
      ],
      generationConfig: {
        maxOutputTokens: 1024
      }
    }.to_json
  end

  def handle_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      handle_error_response(response)
    end

    parsed_response = JSON.parse(response.body)
    summary = parsed_response.dig("candidates", 0, "content", "parts", 0, "text")

    unless summary
      @logger.error("Failed to extract summary from Gemini response: #{parsed_response}")
      raise "Summary could not be generated from API response."
    end

    summary
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
