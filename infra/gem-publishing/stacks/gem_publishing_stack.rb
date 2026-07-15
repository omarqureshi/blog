# frozen_string_literal: true

require 'aws-cdk-lib'

# Hosts the Ruby gems we build (jsii-ruby-runtime, constructs, aws-cdk-lib and the
# per-service aws-cdk-lib gems) as a static RubyGems repository, served over a clean,
# unauthenticated custom domain via CloudFront:
#
#   # Gemfile
#   source "https://rubygems.omarqureshi.net"
#
# The gems live in a private S3 bucket (CloudFront-only access via Origin Access
# Control); consumers only ever hit CloudFront, need no Personal Access Token, and get
# TLS + edge caching for free. The publish pipeline uploads `.gem` files plus a
# `gem generate_index` index to the bucket and invalidates the CloudFront cache.
class GemPublishingStack < AWSCDK::Stack
  BUCKET_NAME = 'aws-cdk-ruby-gems'
  DOMAIN_NAME = 'rubygems.omarqureshi.net'
  HOSTED_ZONE = 'omarqureshi.net'
  RECORD_NAME = 'rubygems'

  def initialize(scope, id, props = nil)
    super(scope, id, props)

    @bucket = create_gem_bucket
    @zone = AWSCDK::Route53::HostedZone.from_lookup(self, 'Zone', { domain_name: HOSTED_ZONE })
    @certificate = create_certificate
    @distribution = create_distribution
    create_dns_records

    AWSCDK::CfnOutput.new(self, 'GemBucketName', { value: @bucket.bucket_name })
    AWSCDK::CfnOutput.new(self, 'DistributionId', { value: @distribution.distribution_id })
    AWSCDK::CfnOutput.new(
      self,
      'GemSourceUrl',
      { value: "https://#{DOMAIN_NAME}", description: 'RubyGems source URL — use in a Gemfile `source`' }
    )
  end

  private

  # Private bucket — read access is only through CloudFront (Origin Access Control);
  # writes come from the authenticated publish pipeline. TLS enforced; retained so
  # published gems survive a stack teardown.
  def create_gem_bucket
    AWSCDK::S3::Bucket.new(
      self,
      'GemBucket',
      {
        bucket_name: BUCKET_NAME,
        block_public_access: AWSCDK::S3::BlockPublicAccess.BLOCK_ALL,
        enforce_ssl: true,
        removal_policy: AWSCDK::RemovalPolicy::RETAIN
      }
    )
  end

  # DNS-validated ACM certificate for the custom domain. Must be in us-east-1 for
  # CloudFront — this stack already deploys there.
  def create_certificate
    AWSCDK::CertificateManager::Certificate.new(
      self,
      'Certificate',
      {
        domain_name: DOMAIN_NAME,
        validation: AWSCDK::CertificateManager::CertificateValidation.from_dns(@zone)
      }
    )
  end

  def create_distribution
    origin = AWSCDK::CloudFrontOrigins::S3BucketOrigin.with_origin_access_control(@bucket)

    # Directory-index behaviour for the docs site: resolve /docs, /docs/, /docs/AWSCDK,
    # /docs/AWSCDK/... to the matching index.html. Scoped strictly to /docs so the gem
    # feed (/gems/*.gem, /specs.4.8.gz, Bundler's /versions & /info/*, ...) is untouched.
    dir_index = AWSCDK::CloudFront::Function.new(
      self,
      'DirIndex',
      {
        comment: 'Append index.html to /docs directory requests',
        code: AWSCDK::CloudFront::FunctionCode.from_inline(<<~JS)
          function handler(event) {
            var request = event.request;
            var uri = request.uri;
            if (uri === '/docs' || uri.indexOf('/docs/') === 0) {
              if (uri.charAt(uri.length - 1) === '/') {
                request.uri = uri + 'index.html';
              } else {
                var last = uri.substring(uri.lastIndexOf('/') + 1);
                if (last.indexOf('.') === -1) {
                  request.uri = uri + '/index.html';
                }
              }
            }
            return request;
          }
        JS
      }
    )

    AWSCDK::CloudFront::Distribution.new(
      self,
      'Distribution',
      {
        comment: 'Public RubyGems repository for the AWS CDK Ruby bindings',
        domain_names: [DOMAIN_NAME],
        certificate: @certificate,
        default_behavior: {
          origin: origin,
          viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::REDIRECT_TO_HTTPS,
          function_associations: [
            {
              function: dir_index,
              event_type: AWSCDK::CloudFront::FunctionEventType::VIEWER_REQUEST
            }
          ],
          # .gem files are immutable (versioned names); the index files are cheap and get
          # invalidated on publish, so an optimized cache policy is safe.
          cache_policy: AWSCDK::CloudFront::CachePolicy.CACHING_OPTIMIZED
        }
      }
    )
  end

  def create_dns_records
    target = AWSCDK::Route53::RecordTarget.from_alias(
      AWSCDK::Route53Targets::CloudFrontTarget.new(@distribution)
    )
    AWSCDK::Route53::ARecord.new(self, 'AliasA', { zone: @zone, record_name: RECORD_NAME, target: target })
    AWSCDK::Route53::AaaaRecord.new(self, 'AliasAaaa', { zone: @zone, record_name: RECORD_NAME, target: target })
  end
end
