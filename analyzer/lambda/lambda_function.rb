# encoding: utf-8
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require_relative 'lib/lambda_handler'

def lambda_handler(event:, context:)
  handler = LambdaHandler.new
  handler.handle(event: event, context: context)
end
