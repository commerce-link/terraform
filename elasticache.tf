resource "aws_elasticache_subnet_group" "valkey" {
  name        = "${local.name_prefix}-valkey-subnets"
  description = "Private subnets for CommerceLink Valkey cache"
  subnet_ids  = aws_subnet.private[*].id
}

resource "aws_elasticache_parameter_group" "valkey" {
  name        = "${local.name_prefix}-valkey-params"
  family      = var.valkey_parameter_group_family
  description = "CommerceLink Valkey parameters"

  dynamic "parameter" {
    for_each = var.valkey_parameter_overrides

    content {
      name  = parameter.key
      value = parameter.value
    }
  }
}

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id       = "${local.name_prefix}-valkey"
  description                = "CommerceLink Valkey cache"
  engine                     = "valkey"
  engine_version             = var.valkey_engine_version
  node_type                  = var.valkey_node_type
  port                       = var.valkey_port
  num_cache_clusters         = var.valkey_node_count
  automatic_failover_enabled = var.valkey_node_count > 1
  multi_az_enabled           = var.valkey_node_count > 1
  subnet_group_name          = aws_elasticache_subnet_group.valkey.name
  security_group_ids         = [aws_security_group.valkey.id]
  parameter_group_name       = aws_elasticache_parameter_group.valkey.name
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token                 = random_password.valkey_auth_token.result
  at_rest_encryption_enabled = true
  auto_minor_version_upgrade = true
  snapshot_retention_limit   = 0
  apply_immediately          = true
}

resource "aws_ssm_parameter" "valkey_endpoint" {
  name        = var.valkey_endpoint_parameter_name
  description = "Valkey connection properties for CommerceLink."
  type        = var.valkey_endpoint_parameter_type
  value = jsonencode({
    host = aws_elasticache_replication_group.valkey.primary_endpoint_address
    port = var.valkey_port
  })
}
