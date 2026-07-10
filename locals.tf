locals {
  name_prefix = "${var.project_name}-${var.environment}"
  az_names    = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  route53_zone_id = (
    try(aws_route53_zone.this[0].zone_id, null)
  )
  acm_domain_names = toset(compact([
    var.app_domain,
    var.api_domain,
  ]))
  acm_certificate_arn = (
    var.acm_certificate_arn != null
    ? var.acm_certificate_arn
    : try(aws_acm_certificate_validation.this[0].certificate_arn, null)
  )

  tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  app_buckets = toset([
    "feeds",
    "pricelists",
    "stores",
    "datalake",
  ])

  app_environment = merge(
    {
      SERVER_PORT                     = "5000"
      SERVER_FORWARD_HEADERS_STRATEGY = "native"
      SPRING_PROFILES_ACTIVE          = join(",", concat(["prod"], var.extra_spring_profiles))
      APPLICATION_ENV                 = "prod"
      AMAZON_AWS_REGION               = var.aws_region
      SQS_PRICELIST_QUEUE_ARN         = aws_sqs_queue.app["catalog-pricelist-queue"].arn
      EVENTBRIDGE_SCHEDULER_ROLE_ARN  = aws_iam_role.scheduler.arn
      VALKEY_ENDPOINT_PARAMETER_NAME  = aws_ssm_parameter.valkey_endpoint.name
      VALKEY_AUTH_SECRET_NAME         = aws_secretsmanager_secret.valkey_auth_token.name
      SQS_FEED_IMPORT_QUEUE_ARN       = aws_sqs_queue.app["supplier-feed-import-queue"].arn
    },
    var.app_domain == null ? {} : {
      APP_DOMAIN = "https://${var.app_domain}"
    },
    var.api_domain == null ? {} : {
      API_DOMAIN = "https://${var.api_domain}"
    },
    {
      S3_BUCKET_FEEDS                                                  = aws_s3_bucket.app["feeds"].bucket
      S3_BUCKET_PRICELISTS                                             = aws_s3_bucket.app["pricelists"].bucket
      S3_BUCKET_STORES                                                 = aws_s3_bucket.app["stores"].bucket
      S3_BUCKET_DATALAKE                                               = aws_s3_bucket.app["datalake"].bucket
      SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_COGNITO_CLIENT_ID     = aws_cognito_user_pool_client.app.id
      SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_COGNITO_CLIENT_SECRET = aws_cognito_user_pool_client.app.client_secret
      SPRING_SECURITY_OAUTH2_CLIENT_PROVIDER_COGNITO_ISSUER_URI        = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.app.id}"
      COGNITO_USER_POOL_ID                                             = aws_cognito_user_pool.app.id
    },
    var.cognito_domain_prefix == null ? {} : {
      COGNITO_DOMAIN = "https://${var.cognito_domain_prefix}.auth.${var.aws_region}.amazoncognito.com"
    },
    length(var.cognito_callback_urls) == 0 ? {} : {
      SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_COGNITO_REDIRECT_URI = var.cognito_callback_urls[0]
    },
    length(var.cognito_logout_urls) == 0 ? {} : {
      COGNITO_LOGOUT_REDIRECT_URI = var.cognito_logout_urls[0]
    },
    var.app_domain == null ? {} : {
      APP_CORS = "https://${var.app_domain}"
    },
    var.extra_app_environment
  )

  sqs_queues = {
    "basket-cleanup-queue" = {
      visibility_timeout_seconds = 30
      message_retention_seconds  = 345600
    }
    "catalog-pricelist-queue" = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 3600
    }
    "marketplace-offer-export-queue" = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 7200
    }
    "marketplace-order-lifecycle-queue" = {
      visibility_timeout_seconds    = 30
      message_retention_seconds     = 345600
      dlq_name                      = "marketplace-order-lifecycle-dlq"
      dlq_message_retention_seconds = 604800
      max_receive_count             = 3
    }
    "marketplace-orders-import-queue" = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 3600
    }
    "order-fulfilment-queue.fifo" = {
      fifo_queue                 = true
      visibility_timeout_seconds = 30
      message_retention_seconds  = 345600
    }
    "order-goods-out-queue.fifo" = {
      fifo_queue                 = true
      visibility_timeout_seconds = 30
      message_retention_seconds  = 345600
      dlq_name                   = "order-goods-out-dlq.fifo"
      max_receive_count          = 1
    }
    "order-invoicing-queue.fifo" = {
      fifo_queue                    = true
      visibility_timeout_seconds    = 30
      message_retention_seconds     = 345600
      dlq_name                      = "order-invoicing-dlq.fifo"
      dlq_message_retention_seconds = 604800
      max_receive_count             = 1
    }
    "order-lifecycle-queue" = {
      visibility_timeout_seconds = 30
      message_retention_seconds  = 345600
    }
    "order-notifications-queue" = {
      visibility_timeout_seconds = 30
      message_retention_seconds  = 345600
    }
    "product-cleanup-queue" = {
      visibility_timeout_seconds = 120
      message_retention_seconds  = 43200
    }
    "product-pim-request-queue" = {
      visibility_timeout_seconds = 30
      message_retention_seconds  = 345600
    }
    "rma-lifecycle-queue" = {
      visibility_timeout_seconds = 30
      message_retention_seconds  = 345600
    }
    "supplier-daily-price-snapshot-queue" = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 43200
    }
    "supplier-feed-import-queue" = {
      visibility_timeout_seconds = 30
      message_retention_seconds  = 43200
    }
    "supplier-rolling-price-aggregate-queue" = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 43200
    }
    "supplier-taxonomy-queue" = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 43200
    }
  }

}
