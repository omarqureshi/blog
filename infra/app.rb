#!/usr/bin/env ruby
# frozen_string_literal: true

require 'aws-cdk-lib'
require_relative 'stacks/blog_stack'

app = AWSCDK::App.new

# The domain and site name configurations
BlogStack.new(app, 'BlogStack', {
                env: AWSCDK::Environment.new(
                  account: ENV['CDK_DEFAULT_ACCOUNT'],
                  region: 'us-east-1' # us-east-1 is required for CloudFront ACM certificates
                )
              })

app.synth
