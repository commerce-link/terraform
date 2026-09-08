resource "aws_s3_bucket" "app" {
  for_each = local.app_buckets

  bucket        = "${local.name_prefix}-${each.key}-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_public_access_block" "app" {
  for_each = aws_s3_bucket.app

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  for_each = aws_s3_bucket.app

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "app" {
  for_each = aws_s3_bucket.app

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "marketplace_export_runs" {
  bucket     = aws_s3_bucket.app["stores"].id
  depends_on = [aws_s3_bucket_versioning.app]

  rule {
    id     = "marketplace-export-runs-expiration"
    status = "Enabled"

    filter {
      prefix = "marketplace-export-runs/"
    }

    expiration {
      days = var.marketplace_export_history_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.marketplace_export_history_retention_days
    }
  }

  rule {
    id     = "marketplace-export-runs-delete-markers"
    status = "Enabled"

    filter {
      prefix = "marketplace-export-runs/"
    }

    expiration {
      expired_object_delete_marker = true
    }
  }
}
