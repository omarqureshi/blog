# frozen_string_literal: true

require 'aws-cdk-lib'

# Hosts the Ruby gems we build (jsii-ruby-runtime, constructs, aws-cdk-lib and the
# per-service aws-cdk-lib gems) in a public, unauthenticated S3 bucket that serves a
# static RubyGems repository. Consumers point `gem`/Bundler at the bucket's HTTPS REST
# endpoint and need no Personal Access Token:
#
#   # Gemfile
#   source "https://aws-cdk-ruby-gems.s3.us-east-1.amazonaws.com"
#
# The publish pipeline uploads `.gem` files plus a `gem generate_index` index to this
# bucket, replacing the GitHub Packages RubyGems feed (which requires auth to read).
class GemPublishingStack < AWSCDK::Stack
  BUCKET_NAME = 'aws-cdk-ruby-gems'

  def initialize(scope, id, props = nil)
    super(scope, id, props)

    @bucket = create_gem_bucket

    AWSCDK::CfnOutput.new(self, 'GemBucketName', { value: @bucket.bucket_name })
    AWSCDK::CfnOutput.new(
      self,
      'GemSourceUrl',
      {
        value: "https://#{@bucket.bucket_name}.s3.#{region}.amazonaws.com",
        description: 'RubyGems source URL — use with `gem install --source <url>` or a Gemfile `source`'
      }
    )
  end

  private

  # A public-read bucket served over its HTTPS REST endpoint. Public access is granted
  # solely via a bucket POLICY (public ACLs stay blocked); TLS is enforced; and the
  # bucket is retained so already-published gems survive a stack teardown.
  def create_gem_bucket
    AWSCDK::S3::Bucket.new(
      self,
      'GemBucket',
      {
        bucket_name: BUCKET_NAME,
        public_read_access: true,
        block_public_access: AWSCDK::S3::BlockPublicAccess.new(
          block_public_acls: true,
          ignore_public_acls: true,
          block_public_policy: false,
          restrict_public_buckets: false
        ),
        enforce_ssl: true,
        removal_policy: AWSCDK::RemovalPolicy::RETAIN
      }
    )
  end
end
