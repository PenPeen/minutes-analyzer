require 'json'

class RequestValidator
  class ValidationError < StandardError; end
  
  def initialize(logger)
    @logger = logger
  end
  
  def validate_and_parse(event)
    validate_event(event)
    body = event['body']
    validate_body(body)
    parse_and_validate_json(body)
  end
  
  private
  
  def validate_event(event)
    unless event.is_a?(Hash)
      @logger.error("Event is not a Hash: #{event.class}")
      raise ValidationError.new("Invalid event format")
    end
  end
  
  def validate_body(body)
    if body.nil? || body.empty?
      @logger.error("Request body is missing.")
      raise ValidationError.new("Request body is missing.")
    end
  end
  
  def parse_and_validate_json(body)
    parsed = JSON.parse(body)
    validate_required_fields(parsed)
    parsed
  rescue JSON::ParserError => e
    @logger.error("Invalid JSON in request body: #{e.message}")
    raise ValidationError.new("Invalid JSON in request body: #{e.message}")
  end
  
  def validate_required_fields(parsed_body)
    # file_idは常に必須
    validate_file_id(parsed_body)
    
    # input_typeが'url'の場合は追加バリデーション
    input_type = parsed_body['input_type']
    if input_type == 'url'
      validate_url_request(parsed_body)
    end
  end
  
  def validate_file_id(parsed_body)
    file_id = parsed_body['file_id']
    if file_id.nil? || file_id.empty?
      @logger.error("file_id is missing in request body")
      raise ValidationError.new("Request must include 'file_id' field")
    end
  end
  
  def validate_url_request(parsed_body)
    google_doc_url = parsed_body['google_doc_url']
    if google_doc_url.nil? || google_doc_url.empty?
      @logger.error("google_doc_url is missing for URL request")
      raise ValidationError.new("URL requests must include 'google_doc_url' field")
    end
  end
end