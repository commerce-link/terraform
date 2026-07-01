resource "aws_cognito_user_pool" "app" {
  name                = "${local.name_prefix}-app"
  deletion_protection = "ACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
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

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "storeId"
    attribute_data_type = "String"
    mutable             = true
    required            = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }
}

resource "aws_cognito_resource_server" "app" {
  count = var.cognito_resource_server_identifier == null ? 0 : 1

  identifier   = var.cognito_resource_server_identifier
  name         = "${local.name_prefix}-app"
  user_pool_id = aws_cognito_user_pool.app.id

  scope {
    scope_name        = "storeId"
    scope_description = "CommerceLink store identifier"
  }
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${local.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.app.id

  generate_secret                      = true
  prevent_user_existence_errors        = "ENABLED"
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = var.cognito_allowed_oauth_scopes
  callback_urls                        = var.cognito_callback_urls
  logout_urls                          = var.cognito_logout_urls

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  depends_on = [aws_cognito_resource_server.app]
}

resource "aws_cognito_user_pool_domain" "app" {
  count = var.cognito_domain_prefix == null ? 0 : 1

  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.app.id
}
