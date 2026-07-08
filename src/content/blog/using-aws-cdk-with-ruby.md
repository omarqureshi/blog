---
title: 'Using the AWS CDK from Ruby'
description: 'A practical getting-started guide for the native Ruby bindings of the AWS CDK — the Gemfile, the cdk.json, a first stack, a Ruby Lambda, and deploying it, with no Personal Access Token required.'
pubDate: 'Jul 9 2026'
---

The AWS CDK now speaks Ruby. Not a wrapper, not a shell-out — the same construct library every other CDK language uses, generated straight from jsii and shipped as ordinary gems. You define infrastructure in idiomatic Ruby and `cdk deploy` synthesises and deploys it exactly as it would from TypeScript.

This post walks through everything you need to stand up a project: the `Gemfile`, the `cdk.json`, and a simple first stack. It assumes you already have an AWS account and credentials configured.

Prefer to watch? Here's a walkthrough:

<iframe src="https://www.youtube-nocookie.com/embed/Tu2CkWKc954" title="Using the AWS CDK from Ruby" style="width: 100%; aspect-ratio: 16 / 9; border: 0; margin: 1.5rem 0;" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

## Prerequisites

- **Ruby ≥ 3.3** (MRI / CRuby).
- **Node.js**. The Ruby bindings talk to the jsii kernel — a small Node sidecar (`@jsii/runtime`) — over a JSON protocol. You never write Node, but it has to be on the machine.
- **The CDK CLI**, installed from npm: `npm install -g aws-cdk`.

## The gems are served over a plain URL — no PAT

The Ruby gems (`aws-cdk-lib`, `constructs`, `jsii-ruby-runtime`, and the asset helpers) are published to a standard RubyGems repository, served over CloudFront at `https://rubygems.omarqureshi.net`. That means **you point Bundler at a URL and install**

## Gemfile

```ruby
source 'https://rubygems.org'

# The AWS CDK Ruby gems (no auth required).
source 'https://rubygems.omarqureshi.net' do
  gem 'aws-cdk-lib', '>= 0.0.0.pre'
  gem 'constructs', '>= 0.0.0.pre'
  gem 'jsii-ruby-runtime', '>= 0.0.0.pre'

  # aws-cdk-lib requires these asset packages at load time:
  gem 'aws-cdk-asset-awscli-v1', '>= 0.0.0.pre'
  gem 'aws-cdk-asset-node-proxy-agent-v6', '>= 0.0.0.pre'
  gem 'aws-cdk-cloud-assembly-schema', '>= 0.0.0.pre'
end
```

During the preview these are pre-release (`0.0.0.pre.*`) versions, hence the `>= 0.0.0.pre` constraint, which tells Bundler it's allowed to resolve pre-releases. Install with a plain `bundle install`.

## cdk.json

`cdk.json` tells the CDK CLI how to run your app. For Ruby, here's an example of running `app.rb` under Bundler:

```json
{
  "app": "bundle exec ruby app.rb"
}
```

## The app entry point

```ruby
require 'aws-cdk-lib'
require_relative 'stacks/my_stack'

app = AWSCDK::App.new

MyStack.new(
  app,
  'MyStack',
  {
    env: AWSCDK::Environment.new(
      account: ENV['CDK_DEFAULT_ACCOUNT'],
      region: ENV.fetch('CDK_DEFAULT_REGION', 'us-east-1')
    )
  }
)

app.synth
```

## The naming rules

These are the conventions you'll rely on everywhere:

- **Modules** are PascalCase under the `AWSCDK` root: `AWSCDK::App`, `AWSCDK::S3`, `AWSCDK::DynamoDB`, `AWSCDK::Lambda`, `AWSCDK::APIGatewayv2`.
- **AWS acronyms are uppercased — in class names too.** This is the surprising one if you're coming from another CDK language. `RestApi` becomes `AWSCDK::APIGateway::RestAPI`; `HttpApi` becomes `AWSCDK::APIGatewayv2::HttpAPI`; `FunctionUrl` becomes `AWSCDK::Lambda::FunctionURL`. The Ruby target runs an AWS acronym list over the identifiers, so `…Api`/`…Url`/`…Arn` render as `…API`/`…URL`/`…ARN`.
- **Props** are a Ruby `Hash` with **snake_case keys** — `removal_policy:`, not `removalPolicy:`.
- **Enums** are constants under `::`: `AWSCDK::RemovalPolicy::DESTROY`.
- **"Enum-like" static constants** are method calls with a `.`: `AWSCDK::Lambda::Runtime.RUBY_4_0`, `AWSCDK::S3::BlockPublicAccess.BLOCK_ALL`.

You can play with the code by using irb and the autocompletion with

```ruby
require 'bundler/setup'
require 'aws-cdk-lib'
```

## A first stack — an S3 bucket

```ruby
require 'aws-cdk-lib'

class MyStack < AWSCDK::Stack
  def initialize(scope, id, props = nil)
    super(scope, id, props)

    AWSCDK::S3::Bucket.new(
      self,
      'MyBucket',
      {
        versioned: true,
        removal_policy: AWSCDK::RemovalPolicy::DESTROY,
        auto_delete_objects: true
      }
    )
  end
end
```

Subclass `AWSCDK::Stack`, call `super`, and instantiate constructs with `(self, 'LogicalId', props)` — the same shape as every other CDK language

## Deploy

```console
$ bundle install
$ npm install -g aws-cdk @jsii/runtime
$ cdk deploy
```

