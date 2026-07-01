# CommerceLink Production Deployment Runbook

This runbook describes how to deploy CommerceLink into a clean AWS account using
Terraform and a domain owned by the deployer.

## 1. Configure AWS Credentials

Use an AWS profile with permissions to create IAM, VPC, Elastic Beanstalk, S3,
DynamoDB, SQS, Cognito, API Gateway, EventBridge Scheduler, ElastiCache,
Route53, ACM, SES, Secrets Manager, SSM, and `iam:PassRole`.

```bash
export AWS_PROFILE=<aws-profile>
export AWS_REGION=eu-central-1

aws sts get-caller-identity
```

Confirm that the returned account ID is the clean target account.

## 2. Prepare `prod.tfvars`

Copy the example file and edit it for the target deployment:

```bash
cp examples/prod.tfvars.example prod.tfvars
```

Minimum production domain values:

```hcl
environment = "prod"
aws_region  = "eu-central-1"

app_domain = "app.example.com"
api_domain = "api.example.com"

cognito_callback_urls = [
  "https://app.example.com/login/oauth2/code/cognito"
]

cognito_logout_urls = [
  "https://app.example.com/logout-success"
]

cognito_domain_prefix = "commerce-link-example-prod"
```

The Cognito domain prefix must be globally unique within the AWS region.

## 3. Create Base Infrastructure

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

Terraform creates the network, Elastic Beanstalk environment, IAM, S3, SQS,
Cognito, API Gateway, EventBridge Scheduler, Valkey cache, optional Route53
records, optional ACM certificate, and optional SES identities.

Every application SQS queue is created with a dedicated dead-letter queue.

DynamoDB tables are not created by Terraform. They are created by the
CommerceLink application and Mongock on first application startup.

The Valkey cache is created in private subnets with TLS required, AUTH enabled,
and at-rest encryption enabled. Terraform stores the generated AUTH token in
Secrets Manager and writes the primary endpoint to SSM Parameter Store.

## 4. Configure DNS Delegation

Terraform creates a public Route53 hosted zone for the domain or subdomain the
user provides. The user then delegates that zone by adding the output NS records
at the registrar or parent DNS provider.

```hcl
route53_zone_name      = "example.com"
create_acm_certificate = false
```

Collect the name servers:

```bash
terraform output route53_zone_name_servers
```

At the domain registrar or parent DNS provider, delegate the zone:

```text
Name: example.com
Type: NS
Value: the four name servers from route53_zone_name_servers
TTL: 300
```

For a delegated subdomain such as `commerce.example.com`, set
`route53_zone_name = "commerce.example.com"` and create the NS record for that
subdomain in the parent zone.

After public DNS delegation works, set:

```hcl
create_acm_certificate = true
```

Then apply again so Terraform can validate and attach the certificate.


## 5. Build the CommerceLink App

In the CommerceLink app repository, build the production artifact using the app
repo's production dependency and profile setup.

Create a Beanstalk source bundle containing:

```text
app.jar
Procfile
```

Example `Procfile`:

```Procfile
web: java -jar app.jar
```

## 6. Publish an Elastic Beanstalk Application Version

Upload the source bundle to an S3 artifact bucket, then create an Elastic
Beanstalk application version.

```bash
aws elasticbeanstalk create-application-version \
  --region eu-central-1 \
  --application-name commerce-link-prod-app \
  --version-label <version-label> \
  --source-bundle S3Bucket=<artifact-bucket>,S3Key=<artifact-key>
```

Set the published version in `prod.tfvars`:

```hcl
application_version_label = "<version-label>"
```

Apply again:

```bash
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars
```

## 7. Create the First Cognito User

Get the user pool ID:

```bash
terraform output cognito_user_pool_id
```

Create a first admin user:

```bash
aws cognito-idp admin-create-user \
  --region eu-central-1 \
  --user-pool-id <user-pool-id> \
  --username admin@example.com \
  --user-attributes \
    Name=email,Value=admin@example.com \
    Name=name,Value="Admin User" \
    Name=email_verified,Value=true \
    Name=custom:role,Value=SUPER_ADMIN
```

The standard `name` attribute is required by the current application OAuth user
service. Without it, Cognito login can complete but the application callback can
fail and appear as a redirect loop.

Set a permanent password:

```bash
aws cognito-idp admin-set-user-password \
  --region eu-central-1 \
  --user-pool-id <user-pool-id> \
  --username admin@example.com \
  --password '<strong-password>' \
  --permanent
```

Store-scoped users also need:

```text
custom:storeId=<store-id>
```

For example, a store admin should include both `Name=name,Value="Store Admin"`
and `Name=custom:storeId,Value=<store-id>` in `--user-attributes`.

## 8. Smoke Test

Check Beanstalk:

```bash
terraform output beanstalk_endpoint_url
curl http://$(terraform output -raw beanstalk_endpoint_url)/env
```

Check DNS:

```bash
dig <app-domain>
dig <api-domain>
```

Open the app domain and log in through Cognito:

```text
https://<app-domain>
```

Check DynamoDB tables after the application has started:

```bash
aws dynamodb list-tables --region eu-central-1
```

The output should include the CommerceLink business tables plus the Mongock
metadata tables `AppMigrationsHistory` and `mongockLock`.

## 9. Operational Follow-Up

The first deployment creates the platform. Business integrations still need
operational configuration:

- Populate Secrets Manager values for suppliers, payments, shipping, invoicing, and marketplaces.
- Populate SSM parameters for OAuth tokens where providers require them.
- Verify SES identities and request SES production access if real email delivery is needed.
- Add seed store/catalog data before testing full ecommerce flows.
- Keep Terraform state private because it contains the Cognito client secret and generated Valkey AUTH token.
