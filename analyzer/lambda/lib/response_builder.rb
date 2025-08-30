require 'json'

class ResponseBuilder
  def self.error_response(status_code, error, details = nil)
    body = { error: error }
    body[:details] = details if details
    {
      statusCode: status_code,
      body: JSON.generate(body)
    }
  end
  
  def self.success_response(analysis_result, integration_results, user_mappings = nil)
    response_body = build_response_body(analysis_result, integration_results)
    
    response = {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.generate(response_body)
    }
    
    # ユーザーマッピング結果を含める
    if user_mappings && !user_mappings.empty?
      response_body = JSON.parse(response[:body])
      response_body[:user_mappings] = user_mappings
      response[:body] = JSON.generate(response_body)
    end
    
    response
  end
  
  private
  
  def self.build_response_body(analysis_result, integration_results)
    slack_result = integration_results[:slack]
    notion_result = integration_results[:notion]
    
    response_body = {
      message: "Analysis complete.",
      analysis: deep_stringify_keys(analysis_result),
      integrations: {
        slack: slack_integration_status(slack_result),
        notion: notion_integration_status(notion_result)
      }
    }
    
    # Add integration details if available
    response_body[:slack_notification] = slack_result if slack_result
    response_body[:notion_result] = notion_result if notion_result
    
    response_body
  end
  
  def self.slack_integration_status(result)
    return 'not_sent' if result.nil?
    result[:success] ? 'sent' : 'not_sent'
  end
  
  def self.notion_integration_status(result)
    return 'not_created' if result.nil?
    result[:success] ? 'created' : 'not_created'
  end
  
  def self.deep_stringify_keys(obj)
    case obj
    when Hash
      obj.transform_keys(&:to_s).transform_values { |v| deep_stringify_keys(v) }
    when Array
      obj.map { |v| deep_stringify_keys(v) }
    else
      obj
    end
  end
end