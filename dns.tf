resource "aws_route53_zone" "this" {
  count = var.route53_zone_name != null ? 1 : 0

  name          = var.route53_zone_name
  force_destroy = var.route53_zone_force_destroy

  tags = {
    Name = var.route53_zone_name
  }
}

resource "aws_acm_certificate" "this" {
  count = var.create_acm_certificate && var.acm_certificate_arn == null && length(local.acm_domain_names) > 0 ? 1 : 0

  domain_name               = sort(tolist(local.acm_domain_names))[0]
  subject_alternative_names = slice(sort(tolist(local.acm_domain_names)), 1, length(local.acm_domain_names))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = var.create_acm_certificate && var.route53_zone_name != null && var.acm_certificate_arn == null ? {
    for option in aws_acm_certificate.this[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  } : {}

  allow_overwrite = true
  zone_id         = local.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_acm_certificate_validation" "this" {
  count = var.create_acm_certificate && var.acm_certificate_arn == null && length(local.acm_domain_names) > 0 ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

resource "aws_route53_record" "app" {
  count = var.route53_zone_name != null && var.app_domain != null ? 1 : 0

  zone_id = local.route53_zone_id
  name    = var.app_domain
  type    = "CNAME"
  ttl     = 300
  records = [aws_elastic_beanstalk_environment.app.endpoint_url]
}

resource "aws_route53_record" "api" {
  count = var.enable_api_gateway && var.route53_zone_name != null && var.api_domain != null && (var.acm_certificate_arn != null || var.create_acm_certificate) ? 1 : 0

  zone_id = local.route53_zone_id
  name    = var.api_domain
  type    = "CNAME"
  ttl     = 300
  records = [aws_api_gateway_domain_name.app[0].regional_domain_name]
}
