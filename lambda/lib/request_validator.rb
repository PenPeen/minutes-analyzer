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
    unless body
      @logger.error("Request body is missing.")
      raise ValidationError.new("Request body is missing.")
    end
  end
  
  def parse_and_validate_json(body)
    parsed = JSON.parse(body)
    validate_file_id(parsed)
    parsed
  rescue JSON::ParserError => e
    @logger.error("Invalid JSON in request body: #{e.message}")
    raise ValidationError.new("Invalid JSON in request body: #{e.message}")
  end
  
  def validate_file_id(parsed_body)
    unless parsed_body['file_id']
      @logger.error("file_id is missing in request body")
      raise ValidationError.new("Request must include 'file_id' field")
    end
  end
end