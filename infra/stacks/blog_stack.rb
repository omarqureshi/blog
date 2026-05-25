require 'aws-cdk-lib'

class BlogStack < AwsCdk::Stack
  def initialize(scope, id, props = nil)
    super(scope, id, props)

    domain_name = 'omarqureshi.net'

    # Lookup the existing Route53 Hosted Zone
    zone = AwsCdk::AwsRoute53::HostedZone.from_lookup(self, 'HostedZone', {
      domain_name: domain_name
    })

    # Create the S3 Bucket to host the site
    site_bucket = AwsCdk::AwsS3::Bucket.new(self, 'SiteBucket', {
      bucket_name: domain_name,
      website_index_document: 'index.html',
      website_error_document: '404.html',
      public_read_access: true,
      block_public_access: AwsCdk::AwsS3::BlockPublicAccess.new(
        block_public_acls: false,
        block_public_policy: false,
        ignore_public_acls: false,
        restrict_public_buckets: false
      ),
      removal_policy: AwsCdk::RemovalPolicy::DESTROY, # NOT recommended for prod, but okay for this example
      auto_delete_objects: true
    })

    # Request an ACM Certificate
    certificate = AwsCdk::AwsCertificatemanager::Certificate.new(self, 'SiteCertificate', {
      domain_name: domain_name,
      validation: AwsCdk::AwsCertificatemanager::CertificateValidation.from_dns(zone)
    })

    # Create the CloudFront Distribution
    distribution = AwsCdk::AwsCloudfront::CloudFrontWebDistribution.new(self, 'SiteDistribution', {
      origin_configs: [
        AwsCdk::AwsCloudfront::SourceConfiguration.new(
          custom_origin_source: AwsCdk::AwsCloudfront::CustomOriginConfig.new(
            domain_name: site_bucket.bucket_website_domain_name,
            origin_protocol_policy: AwsCdk::AwsCloudfront::OriginProtocolPolicy::HTTP_ONLY
          ),
          behaviors: [AwsCdk::AwsCloudfront::Behavior.new(is_default_behavior: true)]
        )
      ],
      viewer_certificate: AwsCdk::AwsCloudfront::ViewerCertificate.from_acm_certificate(
        certificate,
        {
          aliases: [domain_name],
          security_policy: AwsCdk::AwsCloudfront::SecurityPolicyProtocol::TLS_V1_2_2021,
          ssl_method: AwsCdk::AwsCloudfront::SSLMethod::SNI
        }
      )
    })

    # Route53 Alias Record to CloudFront
    AwsCdk::AwsRoute53::ARecord.new(self, 'SiteAliasRecord', {
      record_name: domain_name,
      target: AwsCdk::AwsRoute53::RecordTarget.from_alias(
        AwsCdk::AwsRoute53Targets::CloudFrontTarget.new(distribution)
      ),
      zone: zone
    })

    # Deploy the static site (from Astro's 'dist' folder)
    AwsCdk::AwsS3Deployment::BucketDeployment.new(self, 'DeployWithInvalidation', {
      sources: [AwsCdk::AwsS3Deployment::Source.asset('../dist')],
      destination_bucket: site_bucket,
      distribution: distribution,
      distribution_paths: ['/*']
    })

  end
end
