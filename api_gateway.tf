resource "aws_api_gateway_rest_api" "app" {
  count = var.enable_api_gateway ? 1 : 0

  name                         = local.name_prefix
  disable_execute_api_endpoint = var.api_domain != null && (var.acm_certificate_arn != null || var.create_acm_certificate)
  binary_media_types           = ["text/csv"]

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "proxy" {
  count = var.enable_api_gateway ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.app[0].id
  parent_id   = aws_api_gateway_rest_api.app[0].root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  count = var.enable_api_gateway ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.app[0].id
  resource_id   = aws_api_gateway_resource.proxy[0].id
  http_method   = "ANY"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy" {
  count = var.enable_api_gateway ? 1 : 0

  rest_api_id             = aws_api_gateway_rest_api.app[0].id
  resource_id             = aws_api_gateway_resource.proxy[0].id
  http_method             = aws_api_gateway_method.proxy[0].http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "http://${aws_elastic_beanstalk_environment.app.endpoint_url}/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_deployment" "app" {
  count = var.enable_api_gateway ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.app[0].id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy[0].id,
      aws_api_gateway_method.proxy[0].id,
      aws_api_gateway_integration.proxy[0].id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "app" {
  count = var.enable_api_gateway ? 1 : 0

  deployment_id = aws_api_gateway_deployment.app[0].id
  rest_api_id   = aws_api_gateway_rest_api.app[0].id
  stage_name    = var.api_stage_name
}

resource "aws_api_gateway_domain_name" "app" {
  count = var.enable_api_gateway && var.api_domain != null && (var.acm_certificate_arn != null || var.create_acm_certificate) ? 1 : 0

  domain_name              = var.api_domain
  regional_certificate_arn = local.acm_certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "app" {
  count = var.enable_api_gateway && var.api_domain != null && (var.acm_certificate_arn != null || var.create_acm_certificate) ? 1 : 0

  api_id      = aws_api_gateway_rest_api.app[0].id
  stage_name  = aws_api_gateway_stage.app[0].stage_name
  domain_name = aws_api_gateway_domain_name.app[0].domain_name
}
