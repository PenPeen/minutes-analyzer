#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test runner to check syntax
require_relative 'handler'
puts "handler.rb loaded successfully"

require_relative 'lib/slack_command_handler'
puts "slack_command_handler.rb loaded successfully"

require_relative 'lib/slack_interaction_handler'
puts "slack_interaction_handler.rb loaded successfully"

require_relative 'lib/slack_modal_builder'
puts "slack_modal_builder.rb loaded successfully"

puts "All main files loaded successfully!"