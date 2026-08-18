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

In the CommerceLink app repository, build the production artifact:

```bash
mvn clean package -DskipTests
```

Build profiles matter:
+ **Production**: build without extra Maven profiles (as above). The default
  `full` profile bundles the real supplier adapters only.
+ **Dev/test environments**: add `-Pdev` to include the Acme/AcmeB test
  suppliers. Never deploy a `-Pdev` artifact to production — use distinct
  version labels (for example `-dev-` vs `-prod-`) to keep them apart.

Create a Beanstalk source bundle containing the built jar and a `Procfile`:

```text
app.jar
Procfile
```

Example `Procfile` (the jar name must match the file inside the bundle):

```Procfile
web: java -jar app.jar
```

## 5a. Self-Service Registration Modes (optional)

Public registration at `/register` is disabled by default
(`app.registration.enabled=false`). Two ways to enable it:

**Demo environment** — full demo stores with seeded catalog, sample orders and
a TTL-based cleanup, plus a permanent demo banner:

```hcl
extra_spring_profiles = ["demo"]
```

The `demo` Spring profile sets `app.registration.enabled=true` and
`app.registration.demo=true`. The legacy `/demo/register` URL redirects to
`/register`. Expired demo stores are cleaned up hourly whenever
`app.registration.demo=true`.

**Production registration** — bare production stores and a required store name:

```hcl
extra_app_environment = {
  APP_REGISTRATION_ENABLED = "true"
}
```

Both modes share the same two-step flow: the visitor enters an e-mail address,
sets a password on the next screen, and the application signs them in without
going through the Cognito hosted UI. No invitation e-mail is sent in either
mode. The modes differ in what happens to an unconfirmed address:

+ **Demo** marks the address as verified on creation, so the panel is available
  immediately.
+ **Production** creates the account with `email_verified=false`, sends a
  Cognito verification code, and blocks every `/dashboard` page until the code
  is entered. Accounts created by an administrator keep their verified flag and
  are unaffected.

Before enabling production registration publicly:
+ The app client must allow the `aws.cognito.signin.user.admin` scope. It is in
  the default of `cognito_allowed_oauth_scopes`, but an environment that pins
  that variable in its own tfvars keeps the pinned list and silently misses it.
  Confirm after `terraform apply`:

  ```bash
  aws cognito-idp describe-user-pool-client --user-pool-id <pool> \
    --client-id <client> --query 'UserPoolClient.AllowedOAuthScopes'
  ```

  Without the scope, requesting and confirming a verification code fails with
  `NotAuthorizedException` — but only for someone who leaves the confirmation
  screen and signs in again later, because the token minted right after
  registration always carries the scope. The symptom therefore shows up days
  after the deployment, for part of the users, and locks them out for good.
+ Cognito must be able to deliver verification codes. With `COGNITO_DEFAULT`
  sending, daily limits are low; configure `cognito_ses_source_arn` and request
  SES production access for real traffic.
+ The registration rate limiter keeps its counters in instance memory and
  trusts the `X-Forwarded-For` header. With `beanstalk_max_size` above 1 the
  limits apply per instance, and header hardening is a known follow-up in the
  app repository. Keep a single instance or accept the weaker limits until
  that is addressed.

**Bot protection.** The e-mail screen carries a Cloudflare Turnstile widget.
Leaving the keys unset disables the check, so configure both before exposing
registration publicly:

```hcl
captcha_site_key   = "0x4AAA..."
captcha_secret_key = "0x4AAA..."
```

Verification is done server side and a failed call to Cloudflare rejects the
submission, so an outage at Cloudflare stops new registrations rather than
letting bots through.

## 5b. Seed Data for Dev/Demo Environments (optional)

The application does not seed S3 data outside local development (the
`local-init/s3/**` sync is a LocalStack-only bootstrap). On a fresh dev/demo
environment upload the seed files manually from the app repository:

```bash
# Taxonomy — powers the category counters on /inventory from first boot
aws s3 cp app/src/main/resources/local-init/s3/datalake/taxonomy/2026-07-13.csv \
  s3://<datalake-bucket>/taxonomy/2026-07-13.csv

# Acme/AcmeB test supplier feeds — require a -Pdev application build
aws s3 cp app/src/main/resources/local-init/s3/feeds/acme-feed.csv  s3://<feeds-bucket>/acme-feed.csv
aws s3 cp app/src/main/resources/local-init/s3/feeds/acmeb-feed.csv s3://<feeds-bucket>/acmeb-feed.csv
```

Bucket names come from `terraform output` (resources
`aws_s3_bucket.app["datalake"]` and `aws_s3_bucket.app["feeds"]`). With the
feeds in place the taxonomy also rebuilds itself in memory on every start, so
the taxonomy file upload is a belt-and-braces guarantee rather than a hard
requirement on feed-enabled environments.

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

Keep `email_verified` set to `true`. An account whose address is explicitly
unverified is sent to the e-mail confirmation screen and cannot reach any
`/dashboard` page until it confirms; the attribute being absent altogether is
treated as verified.

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
