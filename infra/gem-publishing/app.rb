#!/usr/bin/env ruby
# frozen_string_literal: true

require 'aws-cdk-lib'
require_relative 'stacks/gem_publishing_stack'

app = AWSCDK::App.new

GemPublishingStack.new(
  app,
  'GemPublishingStack',
  {
    env: AWSCDK::Environment.new(
      account: ENV['CDK_DEFAULT_ACCOUNT'],
      region: ENV.fetch('CDK_DEFAULT_REGION', 'us-east-1')
    )
  }
)

app.synth
