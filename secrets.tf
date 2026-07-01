resource "aws_secretsmanager_secret" "cognito_client_secret" {
  name        = "cognito-client-secret"
  description = "CommerceLink Cognito OAuth client secret."
}

resource "aws_secretsmanager_secret_version" "cognito_client_secret" {
  secret_id     = aws_secretsmanager_secret.cognito_client_secret.id
  secret_string = aws_cognito_user_pool_client.app.client_secret
}

resource "random_password" "valkey_auth_token" {
  length           = var.valkey_auth_token_length
  special          = true
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret" "valkey_auth_token" {
  name        = var.valkey_auth_secret_name
  description = "Valkey AUTH token for CommerceLink."
}

resource "aws_secretsmanager_secret_version" "valkey_auth_token" {
  secret_id     = aws_secretsmanager_secret.valkey_auth_token.id
  secret_string = random_password.valkey_auth_token.result
}
