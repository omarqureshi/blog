require 'aws-cdk-lib'

class BlogStack < AWSCDK::Stack
  def initialize(scope, id, props = nil)
    super(scope, id, props)

    domain_name = 'omarqureshi.net'

    # Lookup the existing Route53 Hosted Zone
    zone = AWSCDK::AWSRoute53::HostedZone.from_lookup(self, 'HostedZone', {
      domain_name: domain_name
    })

    # Create the S3 Bucket to host the site
    site_bucket = AWSCDK::AWSS3::Bucket.new(self, 'SiteBucket', {
      bucket_name: domain_name,
      website_index_document: 'index.html',
      website_error_document: '404.html',
      public_read_access: true,
      block_public_access: AWSCDK::AWSS3::BlockPublicAccess.new(
        block_public_acls: false,
        block_public_policy: false,
        ignore_public_acls: false,
        restrict_public_buckets: false
      ),
      removal_policy: AWSCDK::RemovalPolicy::DESTROY, # NOT recommended for prod, but okay for this example
      auto_delete_objects: true
    })

    # Request an ACM Certificate
    certificate = AWSCDK::AWSCertificatemanager::Certificate.new(self, 'SiteCertificate', {
      domain_name: domain_name,
      validation: AWSCDK::AWSCertificatemanager::CertificateValidation.from_dns(zone)
    })

    # Create the CloudFront Distribution
    distribution = AWSCDK::AWSCloudfront::CloudFrontWebDistribution.new(self, 'SiteDistribution', {
      origin_configs: [
        AWSCDK::AWSCloudfront::SourceConfiguration.new(
          custom_origin_source: AWSCDK::AWSCloudfront::CustomOriginConfig.new(
            domain_name: site_bucket.bucket_website_domain_name,
            origin_protocol_policy: AWSCDK::AWSCloudfront::OriginProtocolPolicy::HTTP_ONLY
          ),
          behaviors: [AWSCDK::AWSCloudfront::Behavior.new(is_default_behavior: true)]
        )
      ],
      viewer_certificate: AWSCDK::AWSCloudfront::ViewerCertificate.from_acm_certificate(
        certificate,
        {
          aliases: [domain_name],
          security_policy: AWSCDK::AWSCloudfront::SecurityPolicyProtocol::TLS_V1_2_2021,
          ssl_method: AWSCDK::AWSCloudfront::SSLMethod::SNI
        }
      )
    })

    # Route53 Alias Record to CloudFront
    AWSCDK::AWSRoute53::ARecord.new(self, 'SiteAliasRecord', {
      record_name: domain_name,
      target: AWSCDK::AWSRoute53::RecordTarget.from_alias(
        AWSCDK::AWSRoute53Targets::CloudFrontTarget.new(distribution)
      ),
      zone: zone,
      delete_existing: true
    })

    # Deploy the static site (from Astro's 'dist' folder)
    AWSCDK::AWSS3Deployment::BucketDeployment.new(self, 'DeployWithInvalidation', {
      sources: [AWSCDK::AWSS3Deployment::Source.asset('../dist')],
      destination_bucket: site_bucket,
      distribution: distribution,
      distribution_paths: ['/*']
    })

  end
end
