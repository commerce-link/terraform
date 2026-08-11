variable "project_name" {
  description = "Project name used for resource names."
  type        = string
  default     = "commerce-link"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for all regional resources."
  type        = string
  default     = "eu-central-1"
}

variable "tags" {
  description = "Additional tags applied to all supported resources."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the CommerceLink VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to use."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "beanstalk_solution_stack_name" {
  description = "Elastic Beanstalk solution stack for the Java application."
  type        = string
  default     = "64bit Amazon Linux 2023 v4.12.2 running Corretto 21"
}

variable "beanstalk_instance_type" {
  description = "EC2 instance type for Elastic Beanstalk."
  type        = string
  default     = "t3.medium"
}

variable "beanstalk_min_size" {
  description = "Minimum Elastic Beanstalk autoscaling capacity."
  type        = number
  default     = 1
}

variable "beanstalk_max_size" {
  description = "Maximum Elastic Beanstalk autoscaling capacity."
  type        = number
  default     = 1
}

variable "beanstalk_cname_prefix" {
  description = "Optional Elastic Beanstalk CNAME prefix."
  type        = string
  default     = null
}

variable "application_version_label" {
  description = "Optional Elastic Beanstalk application version label to deploy."
  type        = string
  default     = null
}

variable "app_domain" {
  description = "Optional public app domain, for example app.example.com."
  type        = string
  default     = null
}

variable "api_domain" {
  description = "Optional API custom domain, for example api.example.com."
  type        = string
  default     = null
}

variable "route53_zone_name" {
  description = "Optional public Route53 hosted zone name to create, for example example.com or app.example.com. Delegate it from the registrar or parent hosted zone."
  type        = string
  default     = null
}

variable "route53_zone_force_destroy" {
  description = "Allow Terraform to destroy all records in the created Route53 hosted zone. Keep false unless intentionally cleaning up an environment."
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "Optional existing ACM certificate ARN for HTTPS on the Beanstalk ALB and API Gateway custom domain."
  type        = string
  default     = null
}

variable "create_acm_certificate" {
  description = "Create and DNS-validate an ACM certificate for app_domain and api_domain. Enable only after the Route53 zone is delegated and publicly resolvable."
  type        = bool
  default     = false
}

variable "cognito_callback_urls" {
  description = "OAuth callback URLs for the Cognito app client."
  type        = list(string)
  default     = []
}

variable "cognito_logout_urls" {
  description = "OAuth logout URLs for the Cognito app client."
  type        = list(string)
  default     = []
}

variable "cognito_domain_prefix" {
  description = "Optional Cognito hosted UI domain prefix."
  type        = string
  default     = null
}

variable "cognito_ses_source_arn" {
  description = "Optional SES identity ARN used by Cognito to send emails (DEVELOPER sending account). Null keeps the COGNITO_DEFAULT sender (~50 emails/day)."
  type        = string
  default     = null
}

variable "cognito_from_email_address" {
  description = "FROM address for Cognito emails. Only used when cognito_ses_source_arn is set."
  type        = string
  default     = null
}

variable "cognito_invite_email_subject" {
  description = "Subject of the Cognito invitation email sent on AdminCreateUser. Set to null to fall back to the AWS default (English) template."
  type        = string
  default     = "CommerceLink — Twoje konto zostało utworzone"
}

variable "cognito_invite_email_message" {
  description = "Body of the Cognito invitation email (HTML). Must contain the {username} and {####} placeholders. Only used when cognito_invite_email_subject is set."
  type        = string
  default     = <<-EOT
    <p>Witaj!</p>
    <p>Twoje konto w platformie <b>CommerceLink</b> jest gotowe.</p>
    <p>Login: <b>{username}</b><br>
    Hasło tymczasowe: <b>{####}</b></p>
    <p>Przy pierwszym logowaniu poprosimy Cię o ustawienie własnego hasła.</p>
    <p>Do zobaczenia,<br>
    Zespół CommerceLink</p>
  EOT
}

variable "cognito_invite_sms_message" {
  description = "SMS variant of the Cognito invitation message. Required by the API whenever the invite template is set; must contain {username} and {####} and fit in 140 characters."
  type        = string
  default     = "Twoj login: {username}, haslo tymczasowe: {####}"
}

variable "extra_spring_profiles" {
  description = "Additional Spring profiles appended to SPRING_PROFILES_ACTIVE after \"prod\" (e.g. [\"demo\"] enables self-service demo registration)."
  type        = list(string)
  default     = []
}

variable "cognito_resource_server_identifier" {
  description = "Optional Cognito resource server identifier for CommerceLink custom scopes."
  type        = string
  default     = null
}

variable "cognito_allowed_oauth_scopes" {
  description = "OAuth scopes for the Cognito app client."
  type        = list(string)
  default     = ["email", "openid", "profile"]
}

variable "enable_api_gateway" {
  description = "Whether to create API Gateway REST API resources."
  type        = bool
  default     = true
}

variable "api_stage_name" {
  description = "API Gateway stage name."
  type        = string
  default     = "Prod"
}

variable "ses_domain_identity" {
  description = "Optional SES domain identity to create."
  type        = string
  default     = null
}

variable "ses_email_identities" {
  description = "Optional SES email identities to create."
  type        = set(string)
  default     = []
}

variable "secret_name_prefixes" {
  description = "Secrets Manager name prefixes the application can read and manage."
  type        = list(string)
  default     = ["commerce-link/"]
}

variable "parameter_name_prefixes" {
  description = "SSM Parameter Store path prefixes the application can read and manage."
  type        = list(string)
  default     = ["/commerce-link/"]
}

variable "valkey_engine_version" {
  description = "ElastiCache Valkey engine version."
  type        = string
  default     = "9.0"
}

variable "valkey_parameter_group_family" {
  description = "ElastiCache parameter group family for Valkey."
  type        = string
  default     = "valkey9"
}

variable "valkey_node_type" {
  description = "ElastiCache Valkey node type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "valkey_node_count" {
  description = "Number of Valkey cache nodes. Use 1 for the simplest single-node deployment."
  type        = number
  default     = 1

  validation {
    condition     = var.valkey_node_count >= 1
    error_message = "valkey_node_count must be at least 1."
  }
}

variable "valkey_port" {
  description = "ElastiCache Valkey port."
  type        = number
  default     = 6379
}

variable "valkey_parameter_overrides" {
  description = "Custom Valkey parameter group values."
  type        = map(string)
  default     = {}
}

variable "valkey_endpoint_parameter_name" {
  description = "SSM Parameter Store name where Terraform writes the Valkey primary endpoint."
  type        = string
  default     = "/commercelink/redis/connection"
}

variable "valkey_endpoint_parameter_type" {
  description = "SSM parameter type for the Valkey endpoint."
  type        = string
  default     = "SecureString"

  validation {
    condition     = contains(["String", "SecureString"], var.valkey_endpoint_parameter_type)
    error_message = "valkey_endpoint_parameter_type must be String or SecureString."
  }
}

variable "valkey_auth_secret_name" {
  description = "Secrets Manager secret name for the Valkey AUTH token."
  type        = string
  default     = "commercelink/redis/auth-token"
}

variable "valkey_auth_token_length" {
  description = "Generated Valkey AUTH token length. ElastiCache requires 16 to 128 printable characters."
  type        = number
  default     = 32

  validation {
    condition     = var.valkey_auth_token_length >= 16 && var.valkey_auth_token_length <= 128
    error_message = "valkey_auth_token_length must be between 16 and 128."
  }
}

variable "force_destroy_buckets" {
  description = "Allow Terraform to destroy non-empty S3 buckets. Keep false for production."
  type        = bool
  default     = false
}

variable "marketplace_export_history_retention_days" {
  description = "Days to keep archived marketplace offer export runs under the marketplace-export-runs/ prefix."
  type        = number
  default     = 7
}

variable "scheduler_schedules" {
  description = "EventBridge Scheduler definitions targeting app SQS queues."
  type = map(object({
    queue_name          = string
    schedule_expression = string
    timezone            = optional(string, "Europe/Warsaw")
    input               = optional(string)
    enabled             = optional(bool, true)
  }))
  default = {}
}

variable "extra_app_environment" {
  description = "Additional Elastic Beanstalk application environment variables."
  type        = map(string)
  default     = {}
}
