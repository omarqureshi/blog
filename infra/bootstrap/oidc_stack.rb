# frozen_string_literal: true

require 'aws-cdk-lib'

# Bootstrap stack to create the OIDC Provider in AWS attached to a Github Repo
class OIDCStack < AWSCDK::Stack
  GITHUB_DOMAIN = 'token.actions.githubusercontent.com'
  GITHUB_ORG = 'omarqureshi'
  GITHUB_REPO = 'blog'
  PROVIDER_POLICY = {
    "StringLike": {
      "#{GITHUB_DOMAIN}:sub": "repo:#{GITHUB_ORG}/#{GITHUB_REPO}:*"
    },
    "StringEquals": {
      "#{GITHUB_DOMAIN}:aud": 'sts.amazonaws.com'
    }
  }.freeze!

  # Thumbprints for GitHub Actions (updated frequently,
  # but these are the current standard ones as of 2024/2025)
  GITHUB_THUMBPRINT = %w[6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd].freeze!

  def initialize(scope, id, props = nil)
    super(scope, id, props)
    #
    # 2. Create the IAM Role assumed by GitHub Actions
    role = create_role(create_provider)

    # Output the Role ARN so the user can easily copy it into their GitHub Actions workflow
    AWSCDK::CfnOutput.new(
      self,
      'OidcRoleArn',
      {
        value: role.role_arn,
        description: 'The ARN of the IAM Role to use in GitHub Actions'
      }
    )
  end

  def create_provider
    # Create the OIDC Provider for GitHub Actions
    #
    # The thumbprint is required but can be the default GitHub thumbprints.
    # Note: AWS CDK typically manages these natively if you use standard providers,
    # but we can explicitly define it for GitHub Actions.
    AWSCDK::IAM::OpenIdConnectProvider.new(
      self,
      'GitHubOIDCProvider',
      {
        url: "https://#{GITHUB_DOMAIN}",
        client_ids: ['sts.amazonaws.com'],
        thumbprints: GITHUB_THUMBPRINT
      }
    )
  end

  def create_role(provider)
    AWSCDK::IAM::Role.new(
      self,
      'GitHubActionsDeployRole', {
        role_name: 'GitHubActionsCDKRole',
        assumed_by: AWSCDK::IAM::OpenIdConnectPrincipal.new(provider, PROVIDER_POLICY),
        description: 'Role assumed by GitHub Actions to deploy the Blog CDK stack'
      }
    )

    # Grant permissions to the role Since CDK deployments require
    # provisioning arbitrary resources (S3, CloudFront, ACM, IAM Roles for
    # custom resources), AdministratorAccess is typically required for the CI/CD
    # role deploying CDK.
    role.add_managed_policy(AWSCDK::IAM::ManagedPolicy.from_aws_managed_policy_name('AdministratorAccess'))
  end
end
