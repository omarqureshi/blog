#!/usr/bin/env ruby
# frozen_string_literal: true

require 'aws-cdk-lib'
require_relative 'oidc_stack'

app = AWSCDK::App.new

# The OIDC stack to bootstrap GitHub Actions authentication
OIDCStack.new(app, 'OIDCStack', {
                env: AWSCDK::Environment.new(
                  account: ENV['CDK_DEFAULT_ACCOUNT'],
                  region: 'us-east-1'
                )
              })

app.synth
