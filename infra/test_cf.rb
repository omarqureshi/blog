require 'aws-cdk-lib'

class TestStack < AWSCDK::Stack
  def initialize(scope, id, props = nil)
    super(scope, id, props)

    api = AWSCDK::AWSApigateway::RestApi.new(self, 'Api')
    
    distribution = AWSCDK::AWSCloudfront::CloudFrontWebDistribution.new(self, 'Dist', {
      origin_configs: [
        AWSCDK::AWSCloudfront::SourceConfiguration.new(
          custom_origin_source: AWSCDK::AWSCloudfront::CustomOriginConfig.new(
            domain_name: "#{api.rest_api_id}.execute-api.#{self.region}.amazonaws.com",
            origin_path: "/prod",
            origin_protocol_policy: AWSCDK::AWSCloudfront::OriginProtocolPolicy::HTTPS_ONLY
          ),
          behaviors: [
            AWSCDK::AWSCloudfront::Behavior.new(
              path_pattern: '/api/*',
              forwarded_values: AWSCDK::AWSCloudfront::CfnDistribution::ForwardedValuesProperty.new(
                query_string: true,
                headers: ['CloudFront-Viewer-Country', 'CloudFront-Viewer-City']
              )
            )
          ]
        )
      ]
    })
  end
end
