# frozen_string_literal: true

require 'aws-cdk-lib'

# Blog Stack
class BlogStack < AWSCDK::Stack
  DOMAIN = 'omarqureshi.net'
  HEADERS = %w[CloudFront-Viewer-Country CloudFront-Viewer-City Authorization].freeze
  USER_POOL_PROPS = {
    user_pool_name: 'BlogAdminPool',
    self_sign_up_enabled: false,
    sign_in_aliases: { email: true },
    auto_verify: { email: true },
    password_policy: {
      min_length: 8,
      require_lowercase: true,
      require_uppercase: true,
      require_digits: true,
      require_symbols: false
    }
  }.freeze

  attr_reader :zone, :certificate, :site_bucket, :logs_bucket, :analytics_table, :analytics_lambda,
              :api, :user_pool, :authorizer, :user_pool_client, :distribution

  def initialize(scope, id, props = nil)
    super(scope, id, props)
    @zone = load_zone
    @certificate = create_certificate
    @site_bucket = create_site_bucket
    @logs_bucket = create_logs_bucket
    analytics_setup
    cognito_setup
    api_gateway_setup
    @distribution = create_distribution
    add_route53_alias
    redirect_www
    deploy
  end

  private

  def analytics_setup
    @analytics_table = create_analytics_table
    @analytics_lambda = create_analytics_lambda
    analytics_table.grant_read_write_data(analytics_lambda)
  end

  def cognito_setup
    @user_pool = create_user_pool
    @authorizer = create_authorizer
    @user_pool_client = create_user_pool_client
  end

  def api_gateway_setup
    @api = create_api_gateway
    create_api_endpoints
  end

  # Lookup the existing Route53 Hosted Zone
  def load_zone
    AWSCDK::AWSRoute53::HostedZone.from_lookup(
      self,
      'HostedZone',
      {
        domain_name: DOMAIN
      }
    )
  end

  # Request an ACM Certificate
  def create_certificate
    AWSCDK::AWSCertificatemanager::Certificate.new(
      self,
      'SiteCertificate',
      {
        domain_name: DOMAIN,
        validation: AWSCDK::AWSCertificatemanager::CertificateValidation.from_dns(zone)
      }
    )
  end

  def create_site_bucket
    AWSCDK::AWSS3::Bucket.new(
      self,
      'SiteBucket',
      {
        bucket_name: DOMAIN,
        website_index_document: 'index.html',
        website_error_document: '404.html',
        public_read_access: true,
        block_public_access: AWSCDK::AWSS3::BlockPublicAccess.new(
          block_public_acls: false,
          block_public_policy: false,
          ignore_public_acls: false,
          restrict_public_buckets: false
        ),
        removal_policy: AWSCDK::RemovalPolicy::DESTROY,
        auto_delete_objects: true
      }
    )
  end

  def create_logs_bucket
    AWSCDK::AWSS3::Bucket.new(
      self,
      'CloudFrontLogsBucket',
      {
        removal_policy: AWSCDK::RemovalPolicy::DESTROY,
        auto_delete_objects: true,
        block_public_access: AWSCDK::AWSS3::BlockPublicAccess.BLOCK_ALL,
        object_ownership: AWSCDK::AWSS3::ObjectOwnership::OBJECT_WRITER
      }
    )
  end

  def create_analytics_table
    AWSCDK::AWSDynamodb::Table.new(
      self,
      'BlogAnalytics',
      {
        partition_key: { name: 'pk', type: AWSCDK::AWSDynamodb::AttributeType::STRING },
        sort_key: { name: 'sk', type: AWSCDK::AWSDynamodb::AttributeType::STRING },
        billing_mode: AWSCDK::AWSDynamodb::BillingMode::PAY_PER_REQUEST,
        removal_policy: AWSCDK::RemovalPolicy::DESTROY # Safe to destroy for blog
      }
    )
  end

  def create_analytics_lambda
    AWSCDK::AWSLambda::Function.new(
      self,
      'AnalyticsLambda',
      {
        runtime: AWSCDK::AWSLambda::Runtime.RUBY_4_0,
        handler: 'analytics.handler',
        code: AWSCDK::AWSLambda::Code.from_asset('lambda'),
        timeout: AWSCDK::Duration.seconds(10),
        memory_size: 256,
        environment: {
          'TABLE_NAME' => analytics_table.table_name
        }
      }
    )
  end

  def create_api_gateway
    AWSCDK::AWSApigateway::RestApi.new(
      self,
      'AnalyticsApi', {
        rest_api_name: 'Blog Analytics API',
        default_cors_preflight_options: {
          allow_origins: AWSCDK::AWSApigateway::Cors.ALL_ORIGINS,
          allow_methods: AWSCDK::AWSApigateway::Cors.ALL_METHODS
        }
      }
    )
  end

  def create_user_pool
    AWSCDK::AWSCognito::UserPool.new(
      self,
      'AdminUserPool',
      USER_POOL_PROPS
    )
  end

  def create_authorizer
    AWSCDK::AWSApigateway::CognitoUserPoolsAuthorizer.new(
      self,
      'AdminAuthorizer',
      {
        cognito_user_pools: [user_pool]
      }
    )
  end

  def create_user_pool_client
    user_pool.add_client(
      'AdminWebClient',
      {
        generate_secret: false,
        auth_flows: { user_password: true, user_srp: true }
      }
    )
  end

  def create_api_endpoints
    api_resource = api.root.add_resource('api')
    # POST /api/track (Public Tracking Endpoint)
    api_resource.add_resource('track').add_method(
      'POST', AWSCDK::AWSApigateway::LambdaIntegration.new(analytics_lambda)
    )
    # GET /api/analytics (Protected Dashboard Endpoint)
    api_resource.add_resource('analytics').add_method(
      'GET', AWSCDK::AWSApigateway::LambdaIntegration.new(analytics_lambda), {
        authorizer: authorizer,
        authorization_type: AWSCDK::AWSApigateway::AuthorizationType::COGNITO
      }
    )
  end

  def create_distribution
    AWSCDK::AWSCloudfront::CloudFrontWebDistribution.new(
      self,
      'SiteDistribution', {
        logging_config: {
          bucket: logs_bucket,
          include_cookies: false
        },
        origin_configs: [
          AWSCDK::AWSCloudfront::SourceConfiguration.new(
            custom_origin_source: AWSCDK::AWSCloudfront::CustomOriginConfig.new(
              domain_name: "#{api.rest_api_id}.execute-api.#{region}.amazonaws.com",
              origin_path: '/prod',
              origin_protocol_policy: AWSCDK::AWSCloudfront::OriginProtocolPolicy::HTTPS_ONLY
            ),
            behaviors: [
              AWSCDK::AWSCloudfront::Behavior.new(
                path_pattern: '/api/*',
                allowed_methods: AWSCDK::AWSCloudfront::CloudFrontAllowedMethods::ALL,
                forwarded_values: AWSCDK::AWSCloudfront::CfnDistribution::ForwardedValuesProperty.new(
                  query_string: true,
                  headers: HEADERS
                )
              )
            ]
          ),
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
            aliases: [DOMAIN],
            security_policy: AWSCDK::AWSCloudfront::SecurityPolicyProtocol::TLS_V1_2_2021,
            ssl_method: AWSCDK::AWSCloudfront::SSLMethod::SNI
          }
        )
      }
    )
  end

  def add_route53_alias
    AWSCDK::AWSRoute53::ARecord.new(
      self,
      'SiteAliasRecord',
      {
        record_name: DOMAIN,
        target: AWSCDK::AWSRoute53::RecordTarget.from_alias(AWSCDK::AWSRoute53Targets::CloudFrontTarget.new(distribution)),
        zone: zone,
        delete_existing: true
      }
    )
  end

  def deploy
    AWSCDK::AWSS3Deployment::BucketDeployment.new(
      self,
      'DeployWithInvalidation',
      {
        sources: [AWSCDK::AWSS3Deployment::Source.asset('../dist')],
        destination_bucket: site_bucket,
        distribution: distribution,
        distribution_paths: ['/*']
      }
    )
    output
  end

  def redirect_www
    AWSCDK::AWSRoute53Patterns::HttpsRedirect.new(
      self,
      'WwwRedirect',
      {
        record_names: ["www.#{DOMAIN}"],
        target_domain: DOMAIN,
        zone: zone
      }
    )
  end

  def output
    AWSCDK::CfnOutput.new(self, 'ApiEndpoint', { value: api.url })
    AWSCDK::CfnOutput.new(self, 'UserPoolId', { value: user_pool.user_pool_id })
    AWSCDK::CfnOutput.new(self, 'UserPoolClientId', { value: user_pool_client.user_pool_client_id })
  end
end
