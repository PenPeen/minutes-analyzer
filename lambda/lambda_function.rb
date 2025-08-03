require_relative 'lib/lambda_handler'

def lambda_handler(event:, context:)
  handler = LambdaHandler.new
  handler.handle(event: event, context: context)
end
