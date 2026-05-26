require 'aws-cdk-lib'

class OIDCStack < AWSCDK::Stack
  def initialize(scope, id, props = nil)
    super(scope, id, props)

    github_domain = 'token.actions.githubusercontent.com'
    
    # 1. Create the OIDC Provider for GitHub Actions
    # The thumbprint is required but can be the default GitHub thumbprints.
    # Note: AWS CDK typically manages these natively if you use standard providers,
    # but we can explicitly define it for GitHub Actions.
    provider = AWSCDK::AWSIAM::OpenIdConnectProvider.new(self, 'GitHubOIDCProvider', {
      url: "https://#{github_domain}",
      client_ids: ['sts.amazonaws.com'],
      # Thumbprints for GitHub Actions (updated frequently, 
      # but these are the current standard ones as of 2024/2025)
      thumbprints: ['6938fd4d98bab03faadb97b34396831e3780aea1', '1c58a3a8518e8759bf075b76b750d4f2df264fcd']
    })

    # 2. Create the IAM Role assumed by GitHub Actions
    github_org = 'omarqureshi' # Update this if your GitHub username is different
    github_repo = 'blog' # Update this if your repository name is different

    role = AWSCDK::AWSIAM::Role.new(self, 'GitHubActionsDeployRole', {
      role_name: 'GitHubActionsCDKRole',
      assumed_by: AWSCDK::AWSIAM::OpenIdConnectPrincipal.new(provider, {
        "StringLike": {
          "#{github_domain}:sub": "repo:#{github_org}/#{github_repo}:*"
        },
        "StringEquals": {
          "#{github_domain}:aud": "sts.amazonaws.com"
        }
      }),
      description: 'Role assumed by GitHub Actions to deploy the Blog CDK stack'
    })

    # 3. Grant permissions to the role
    # Since CDK deployments require provisioning arbitrary resources (S3, CloudFront, ACM, IAM Roles for custom resources),
    # AdministratorAccess is typically required for the CI/CD role deploying CDK.
    role.add_managed_policy(AWSCDK::AWSIAM::ManagedPolicy.from_aws_managed_policy_name('AdministratorAccess'))

    # Output the Role ARN so the user can easily copy it into their GitHub Actions workflow
    AWSCDK::CfnOutput.new(self, 'OidcRoleArn', {
      value: role.role_arn,
      description: 'The ARN of the IAM Role to use in GitHub Actions'
    })
  end
end
