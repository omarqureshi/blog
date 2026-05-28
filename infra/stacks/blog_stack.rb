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

    # S3 Bucket for CloudFront Access Logs
    logs_bucket = AWSCDK::AWSS3::Bucket.new(self, 'CloudFrontLogsBucket', {
      removal_policy: AWSCDK::RemovalPolicy::DESTROY,
      auto_delete_objects: true,
      block_public_access: AWSCDK::AWSS3::BlockPublicAccess.BLOCK_ALL,
      object_ownership: AWSCDK::AWSS3::ObjectOwnership::OBJECT_WRITER
    })

    # Create the CloudFront Distribution with Logging
    distribution = AWSCDK::AWSCloudfront::CloudFrontWebDistribution.new(self, 'SiteDistribution', {
      logging_config: {
        bucket: logs_bucket,
        include_cookies: false
      },
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

    # Automatically redirect www.omarqureshi.net to omarqureshi.net over HTTPS
    AWSCDK::AWSRoute53Patterns::HttpsRedirect.new(self, 'WwwRedirect', {
      record_names: ["www.#{domain_name}"],
      target_domain: domain_name,
      zone: zone
    })

    # --- ANALYTICS INFRASTRUCTURE ---

    # S3 Bucket for Athena Query Results & Cache
    athena_bucket = AWSCDK::AWSS3::Bucket.new(self, 'AthenaResultsBucket', {
      removal_policy: AWSCDK::RemovalPolicy::DESTROY,
      auto_delete_objects: true,
      block_public_access: AWSCDK::AWSS3::BlockPublicAccess.BLOCK_ALL
    })

    # Saved Query to Create Athena Table
    create_table_sql = <<~SQL
      CREATE EXTERNAL TABLE IF NOT EXISTS default.cloudfront_logs (
        `date` DATE,
        time STRING,
        x_edge_location STRING,
        sc_bytes BIGINT,
        c_ip STRING,
        cs_method STRING,
        cs_host STRING,
        cs_uri_stem STRING,
        sc_status INT,
        cs_referer STRING,
        cs_user_agent STRING,
        cs_uri_query STRING,
        cs_cookie STRING,
        x_edge_result_type STRING,
        x_edge_request_id STRING,
        x_host_header STRING,
        cs_protocol STRING,
        cs_bytes BIGINT,
        time_taken FLOAT,
        x_forwarded_for STRING,
        ssl_protocol STRING,
        ssl_cipher STRING,
        x_edge_response_result_type STRING,
        cs_protocol_version STRING,
        fle_status STRING,
        fle_encrypted_fields INT,
        c_port INT,
        time_to_first_byte FLOAT,
        x_edge_detailed_result_type STRING,
        sc_content_type STRING,
        sc_content_len BIGINT,
        sc_range_start BIGINT,
        sc_range_end BIGINT
      )
      ROW FORMAT DELIMITED
      FIELDS TERMINATED BY '\\t'
      LOCATION 's3://#{logs_bucket.bucket_name}/'
      TBLPROPERTIES ('skip.header.line.count'='2');
    SQL

    AWSCDK::AWSAthena::CfnNamedQuery.new(self, 'CreateCloudFrontLogsTableQuery', {
      database: 'default',
      name: 'Create CloudFront Logs Table',
      query_string: create_table_sql
    })

    # Cognito User Pool for Admin Access
    user_pool = AWSCDK::AWSCognito::UserPool.new(self, 'AdminUserPool', {
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
    })

    user_pool_client = user_pool.add_client('AdminWebClient', {
      generate_secret: false,
      auth_flows: { user_password: true, user_srp: true }
    })

    # Lambda Function for Analytics API
    analytics_lambda = AWSCDK::AWSLambda::Function.new(self, 'AnalyticsLambda', {
      runtime: AWSCDK::AWSLambda::Runtime.RUBY_3_2,
      handler: 'analytics.handler',
      code: AWSCDK::AWSLambda::Code.from_asset('lambda'),
      timeout: AWSCDK::Duration.seconds(30),
      memory_size: 256,
      environment: {
        'ATHENA_OUTPUT_BUCKET' => "s3://#{athena_bucket.bucket_name}/",
        'ATHENA_DATABASE' => 'default',
        'CACHE_BUCKET' => athena_bucket.bucket_name,
        'CACHE_KEY' => 'cache/analytics_cache.json'
      }
    })

    # Grant Lambda permissions to query Athena and access S3
    analytics_lambda.add_to_role_policy(AWSCDK::AWSIAM::PolicyStatement.new(
      actions: ['athena:StartQueryExecution', 'athena:GetQueryExecution', 'athena:GetQueryResults'],
      resources: ['*']
    ))
    analytics_lambda.add_to_role_policy(AWSCDK::AWSIAM::PolicyStatement.new(
      actions: ['glue:GetTable', 'glue:GetDatabase', 'glue:GetPartitions'],
      resources: ['*']
    ))
    logs_bucket.grant_read(analytics_lambda)
    athena_bucket.grant_read_write(analytics_lambda)

    # API Gateway
    api = AWSCDK::AWSApigateway::RestApi.new(self, 'AnalyticsApi', {
      rest_api_name: 'Blog Analytics API',
      default_cors_preflight_options: {
        allow_origins: AWSCDK::AWSApigateway::Cors.ALL_ORIGINS,
        allow_methods: AWSCDK::AWSApigateway::Cors.ALL_METHODS
      }
    })

    # Cognito Authorizer
    authorizer = AWSCDK::AWSApigateway::CognitoUserPoolsAuthorizer.new(self, 'AdminAuthorizer', {
      cognito_user_pools: [user_pool]
    })

    # API Endpoint
    analytics_resource = api.root.add_resource('analytics')
    analytics_resource.add_method('GET', AWSCDK::AWSApigateway::LambdaIntegration.new(analytics_lambda), {
      authorizer: authorizer,
      authorization_type: AWSCDK::AWSApigateway::AuthorizationType::COGNITO
    })

    # Outputs
    AWSCDK::CfnOutput.new(self, 'ApiEndpoint', { value: api.url })
    AWSCDK::CfnOutput.new(self, 'UserPoolId', { value: user_pool.user_pool_id })
    AWSCDK::CfnOutput.new(self, 'UserPoolClientId', { value: user_pool_client.user_pool_client_id })

  end
end
