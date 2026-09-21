resource "aws_cognito_user_pool" "app" {
  name                = coalesce(var.cognito_user_pool_name, "${local.name_prefix}-app")
  deletion_protection = "ACTIVE"
  mfa_configuration   = var.cognito_mfa_configuration

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true

    dynamic "invite_message_template" {
      for_each = var.cognito_invite_email_subject == null ? [] : [1]
      content {
        email_subject = var.cognito_invite_email_subject
        email_message = var.cognito_invite_email_message
        sms_message   = var.cognito_invite_sms_message
      }
    }
  }

  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }

  dynamic "software_token_mfa_configuration" {
    for_each = var.cognito_mfa_configuration == "OFF" ? [] : [1]
    content {
      enabled = true
    }
  }

  email_configuration {
    email_sending_account = var.cognito_ses_source_arn == null ? "COGNITO_DEFAULT" : "DEVELOPER"
    source_arn            = var.cognito_ses_source_arn
    from_email_address    = var.cognito_from_email_address
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  schema {
    name                = "role"
    attribute_data_type = "String"
    mutable             = true
    required            = false

    string_attribute_constraints {}
  }

  schema {
    name                = "storeId"
    attribute_data_type = "String"
    mutable             = true
    required            = false

    string_attribute_constraints {}
  }

  lifecycle {
    ignore_changes = [schema]
  }
}

resource "aws_cognito_resource_server" "app" {
  count = var.cognito_resource_server_identifier == null ? 0 : 1

  identifier   = var.cognito_resource_server_identifier
  name         = "${local.name_prefix}-app"
  user_pool_id = aws_cognito_user_pool.app.id

  scope {
    scope_name        = "custom:storeId"
    scope_description = "StoreID"
  }
}

resource "aws_cognito_user_pool_client" "app" {
  name         = coalesce(var.cognito_user_pool_client_name, "${local.name_prefix}-client")
  user_pool_id = aws_cognito_user_pool.app.id

  generate_secret                      = var.cognito_generate_secret ? true : null
  prevent_user_existence_errors        = "ENABLED"
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = var.cognito_allowed_oauth_scopes
  callback_urls                        = var.cognito_callback_urls
  logout_urls                          = var.cognito_logout_urls

  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_AUTH"
  ]

  access_token_validity  = 480
  id_token_validity      = 480
  refresh_token_validity = 5

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  depends_on = [aws_cognito_resource_server.app]
}

resource "aws_cognito_user_pool_domain" "app" {
  count = var.cognito_domain_prefix == null ? 0 : 1

  domain       = coalesce(var.cognito_domain_name_override, var.cognito_domain_prefix)
  user_pool_id = aws_cognito_user_pool.app.id
}
