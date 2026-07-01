resource "aws_ses_domain_identity" "app" {
  count = var.ses_domain_identity == null ? 0 : 1

  domain = var.ses_domain_identity
}

resource "aws_ses_email_identity" "app" {
  for_each = var.ses_email_identities

  email = each.key
}
