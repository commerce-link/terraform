data "aws_api_gateway_api_key" "app" {
  count = var.api_gateway_api_key_id == null ? 0 : 1

  id = var.api_gateway_api_key_id
}

resource "aws_api_gateway_rest_api" "app" {
  count = var.enable_api_gateway ? 1 : 0

  name                         = coalesce(var.api_gateway_rest_api_name, local.name_prefix)
  disable_execute_api_endpoint = var.api_domain != null && (var.acm_certificate_arn != null || var.create_acm_certificate)
  binary_media_types           = ["text/csv"]

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# PIM routes exist on production and are left unmanaged on purpose.
locals {
  api_gateway_backend = "http://${aws_elastic_beanstalk_environment.app.endpoint_url}"

  api_gateway_cors_allow_headers = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  api_gateway_cors_allow_methods = "'OPTIONS,POST'"
  api_gateway_cors_allow_origin  = "'*'"

  api_gateway_resources = {
    store = {
      parent    = "root"
      path_part = "Store"
      depth     = 1
    }
    store_id = {
      parent    = "store"
      path_part = "{storeId}"
      depth     = 2
    }
    store_checkout = {
      parent    = "store_id"
      path_part = "Checkout"
      depth     = 3
    }
    store_checkout_delivery_options = {
      parent    = "store_checkout"
      path_part = "DeliveryOptions"
      depth     = 4
    }
    store_catalog = {
      parent    = "store_id"
      path_part = "Catalog"
      depth     = 3
    }
    store_catalog_id = {
      parent    = "store_catalog"
      path_part = "{catalogId}"
      depth     = 4
    }
    store_catalog_proxy = {
      parent    = "store_catalog_id"
      path_part = "{proxy+}"
      depth     = 5
    }
    store_reporting = {
      parent    = "store_id"
      path_part = "Reporting"
      depth     = 3
    }
    store_reporting_google = {
      parent    = "store_reporting"
      path_part = "Google"
      depth     = 4
    }
    store_reporting_google_conversions = {
      parent    = "store_reporting_google"
      path_part = "Conversions"
      depth     = 5
    }
    store_reporting_google_conversions_token = {
      parent    = "store_reporting_google_conversions"
      path_part = "{token}"
      depth     = 6
    }
    store_webhooks = {
      parent    = "store_id"
      path_part = "Webhooks"
      depth     = 3
    }
    store_webhooks_proxy = {
      parent    = "store_webhooks"
      path_part = "{proxy+}"
      depth     = 4
    }
    store_basket = {
      parent    = "store_id"
      path_part = "Basket"
      depth     = 3
    }
    global = {
      parent    = "root"
      path_part = "Global"
      depth     = 1
    }
    global_inventory = {
      parent    = "global"
      path_part = "Inventory"
      depth     = 2
    }
    global_inventory_proxy = {
      parent    = "global_inventory"
      path_part = "{proxy+}"
      depth     = 3
    }
  }

  api_gateway_methods = {
    global_inventory_proxy_any = {
      resource_key     = "global_inventory_proxy"
      http_method      = "ANY"
      api_key_required = var.api_gateway_api_key_required
      request_parameters = {
        "method.request.path.proxy" = true
      }
      integration = {
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri_path                = "/Global/Inventory/{proxy}"
        request_parameters = {
          "integration.request.path.proxy" = "method.request.path.proxy"
        }
        request_templates    = {}
        passthrough_behavior = "WHEN_NO_MATCH"
        timeout_milliseconds = 29000
      }
    }

    store_checkout_options = {
      resource_key       = "store_checkout"
      http_method        = "OPTIONS"
      api_key_required   = false
      request_parameters = {}
      integration = {
        type                    = "MOCK"
        integration_http_method = null
        uri_path                = null
        request_parameters      = {}
        request_templates = {
          "application/json" = "{\"statusCode\": 200}"
        }
        passthrough_behavior = "WHEN_NO_MATCH"
        timeout_milliseconds = 29000
      }
    }

    store_checkout_post = {
      resource_key     = "store_checkout"
      http_method      = "POST"
      api_key_required = false
      request_parameters = {
        "method.request.path.storeId" = true
      }
      integration = {
        type                    = "HTTP"
        integration_http_method = "POST"
        uri_path                = "/Store/{storeId}/Checkout"
        request_parameters = {
          "integration.request.path.storeId" = "method.request.path.storeId"
        }
        request_templates    = {}
        passthrough_behavior = "WHEN_NO_MATCH"
        timeout_milliseconds = 29000
      }
    }

    store_checkout_delivery_options_get = {
      resource_key     = "store_checkout_delivery_options"
      http_method      = "GET"
      api_key_required = false
      request_parameters = {
        "method.request.path.storeId" = true
      }
      integration = {
        type                    = "HTTP_PROXY"
        integration_http_method = "GET"
        uri_path                = "/Store/{storeId}/Checkout/DeliveryOptions"
        request_parameters = {
          "integration.request.path.storeId" = "method.request.path.storeId"
        }
        request_templates    = {}
        passthrough_behavior = "WHEN_NO_MATCH"
        timeout_milliseconds = 10000
      }
    }

    store_catalog_proxy_any = {
      resource_key     = "store_catalog_proxy"
      http_method      = "ANY"
      api_key_required = var.api_gateway_api_key_required
      request_parameters = {
        "method.request.path.catalogId" = true
        "method.request.path.proxy"     = true
        "method.request.path.storeId"   = true
      }
      integration = {
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri_path                = "/Store/{storeId}/Catalog/{catalogId}/{proxy}"
        request_parameters = merge(
          {
            "integration.request.path.catalogId" = "method.request.path.catalogId"
            "integration.request.path.proxy"     = "method.request.path.proxy"
            "integration.request.path.storeId"   = "method.request.path.storeId"
          },
          {
            for header in compact([var.api_gateway_catalog_id_header]) :
            "integration.request.header.API_GATEWAY_ID" => "'${header}'"
          }
        )
        request_templates    = {}
        passthrough_behavior = "WHEN_NO_TEMPLATES"
        timeout_milliseconds = 29000
      }
    }

    store_webhooks_proxy_post = {
      resource_key     = "store_webhooks_proxy"
      http_method      = "POST"
      api_key_required = false
      request_parameters = {
        "method.request.path.proxy"   = true
        "method.request.path.storeId" = true
      }
      integration = {
        type                    = "HTTP_PROXY"
        integration_http_method = "POST"
        uri_path                = "/Store/{storeId}/Webhooks/{proxy}"
        request_parameters = {
          "integration.request.path.proxy"   = "method.request.path.proxy"
          "integration.request.path.storeId" = "method.request.path.storeId"
        }
        request_templates    = {}
        passthrough_behavior = "WHEN_NO_MATCH"
        timeout_milliseconds = 29000
      }
    }

    store_reporting_google_conversions_token_get = {
      resource_key     = "store_reporting_google_conversions_token"
      http_method      = "GET"
      api_key_required = false
      request_parameters = {
        "method.request.path.storeId" = true
        "method.request.path.token"   = true
      }
      integration = {
        type                    = "HTTP_PROXY"
        integration_http_method = "GET"
        uri_path                = "/Store/{storeId}/Reporting/Google/Conversions/{token}"
        request_parameters = {
          "integration.request.path.storeId" = "method.request.path.storeId"
          "integration.request.path.token"   = "method.request.path.token"
        }
        request_templates    = {}
        passthrough_behavior = "WHEN_NO_MATCH"
        timeout_milliseconds = 29000
      }
    }

    store_basket_options = {
      resource_key       = "store_basket"
      http_method        = "OPTIONS"
      api_key_required   = false
      request_parameters = {}
      integration = {
        type                    = "MOCK"
        integration_http_method = null
        uri_path                = null
        request_parameters      = {}
        request_templates = {
          "application/json" = "{\"statusCode\": 200}"
        }
        passthrough_behavior = "WHEN_NO_MATCH"
        timeout_milliseconds = 29000
      }
    }

    store_basket_post = {
      resource_key     = "store_basket"
      http_method      = "POST"
      api_key_required = false
      request_parameters = {
        "method.request.path.storeId" = true
      }
      integration = {
        type                    = "HTTP"
        integration_http_method = "POST"
        uri_path                = "/Store/{storeId}/Basket"
        request_parameters = {
          "integration.request.path.storeId" = "method.request.path.storeId"
        }
        request_templates    = {}
        passthrough_behavior = "WHEN_NO_MATCH"
        timeout_milliseconds = 29000
      }
    }
  }

  api_gateway_method_responses = {
    store_checkout_options = {
      status_code = "200"
      response_models = {
        "application/json" = "Empty"
      }
      response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = false
        "method.response.header.Access-Control-Allow-Methods" = false
        "method.response.header.Access-Control-Allow-Origin"  = false
      }
    }
    store_checkout_post = {
      status_code = "200"
      response_models = {
        "application/json" = "Empty"
      }
      response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = false
      }
    }
    store_basket_options = {
      status_code = "200"
      response_models = {
        "application/json" = "Empty"
      }
      response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = false
        "method.response.header.Access-Control-Allow-Methods" = false
        "method.response.header.Access-Control-Allow-Origin"  = false
      }
    }
    store_basket_post = {
      status_code = "200"
      response_models = {
        "application/json" = "Empty"
      }
      response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = false
      }
    }
  }

  api_gateway_integration_responses = {
    store_checkout_options = {
      status_code = "200"
      response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = local.api_gateway_cors_allow_headers
        "method.response.header.Access-Control-Allow-Methods" = local.api_gateway_cors_allow_methods
        "method.response.header.Access-Control-Allow-Origin"  = local.api_gateway_cors_allow_origin
      }
      response_templates = {}
    }
    store_checkout_post = {
      status_code = "200"
      response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = local.api_gateway_cors_allow_origin
      }
      response_templates = {
        "application/json" = null
      }
    }
    store_basket_options = {
      status_code = "200"
      response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = local.api_gateway_cors_allow_headers
        "method.response.header.Access-Control-Allow-Methods" = local.api_gateway_cors_allow_methods
        "method.response.header.Access-Control-Allow-Origin"  = local.api_gateway_cors_allow_origin
      }
      response_templates = {}
    }
    store_basket_post = {
      status_code = "200"
      response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = local.api_gateway_cors_allow_origin
      }
      response_templates = {
        "application/json" = null
      }
    }
  }
}

resource "aws_api_gateway_resource" "level1" {
  for_each = {
    for key, value in local.api_gateway_resources : key => value
    if var.enable_api_gateway && value.depth == 1
  }

  rest_api_id = aws_api_gateway_rest_api.app[0].id
  parent_id   = aws_api_gateway_rest_api.app[0].root_resource_id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level2" {
  for_each = {
    for key, value in local.api_gateway_resources : key => value
    if var.enable_api_gateway && value.depth == 2
  }

  rest_api_id = aws_api_gateway_rest_api.app[0].id
  parent_id   = aws_api_gateway_resource.level1[each.value.parent].id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level3" {
  for_each = {
    for key, value in local.api_gateway_resources : key => value
    if var.enable_api_gateway && value.depth == 3
  }

  rest_api_id = aws_api_gateway_rest_api.app[0].id
  parent_id   = aws_api_gateway_resource.level2[each.value.parent].id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level4" {
  for_each = {
    for key, value in local.api_gateway_resources : key => value
    if var.enable_api_gateway && value.depth == 4
  }

  rest_api_id = aws_api_gateway_rest_api.app[0].id
  parent_id   = aws_api_gateway_resource.level3[each.value.parent].id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level5" {
  for_each = {
    for key, value in local.api_gateway_resources : key => value
    if var.enable_api_gateway && value.depth == 5
  }

  rest_api_id = aws_api_gateway_rest_api.app[0].id
  parent_id   = aws_api_gateway_resource.level4[each.value.parent].id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "level6" {
  for_each = {
    for key, value in local.api_gateway_resources : key => value
    if var.enable_api_gateway && value.depth == 6
  }

  rest_api_id = aws_api_gateway_rest_api.app[0].id
  parent_id   = aws_api_gateway_resource.level5[each.value.parent].id
  path_part   = each.value.path_part
}

locals {
  api_gateway_resource_ids = merge(
    { for key, resource in aws_api_gateway_resource.level1 : key => resource.id },
    { for key, resource in aws_api_gateway_resource.level2 : key => resource.id },
    { for key, resource in aws_api_gateway_resource.level3 : key => resource.id },
    { for key, resource in aws_api_gateway_resource.level4 : key => resource.id },
    { for key, resource in aws_api_gateway_resource.level5 : key => resource.id },
    { for key, resource in aws_api_gateway_resource.level6 : key => resource.id },
  )
}

resource "aws_api_gateway_method" "this" {
  for_each = {
    for key, value in local.api_gateway_methods : key => value
    if var.enable_api_gateway
  }

  rest_api_id        = aws_api_gateway_rest_api.app[0].id
  resource_id        = local.api_gateway_resource_ids[each.value.resource_key]
  http_method        = each.value.http_method
  authorization      = "NONE"
  api_key_required   = each.value.api_key_required
  request_parameters = each.value.request_parameters
}

resource "aws_api_gateway_integration" "this" {
  for_each = {
    for key, value in local.api_gateway_methods : key => value
    if var.enable_api_gateway
  }

  rest_api_id             = aws_api_gateway_rest_api.app[0].id
  resource_id             = local.api_gateway_resource_ids[each.value.resource_key]
  http_method             = aws_api_gateway_method.this[each.key].http_method
  type                    = each.value.integration.type
  integration_http_method = each.value.integration.integration_http_method
  uri                     = each.value.integration.uri_path == null ? null : "${local.api_gateway_backend}${each.value.integration.uri_path}"
  request_parameters      = each.value.integration.request_parameters
  request_templates       = each.value.integration.request_templates
  passthrough_behavior    = each.value.integration.passthrough_behavior
  timeout_milliseconds    = each.value.integration.timeout_milliseconds
}

resource "aws_api_gateway_method_response" "this" {
  for_each = {
    for key, value in local.api_gateway_method_responses : key => value
    if var.enable_api_gateway
  }

  rest_api_id         = aws_api_gateway_rest_api.app[0].id
  resource_id         = local.api_gateway_resource_ids[local.api_gateway_methods[each.key].resource_key]
  http_method         = aws_api_gateway_method.this[each.key].http_method
  status_code         = each.value.status_code
  response_models     = each.value.response_models
  response_parameters = each.value.response_parameters
}

resource "aws_api_gateway_integration_response" "this" {
  for_each = {
    for key, value in local.api_gateway_integration_responses : key => value
    if var.enable_api_gateway
  }

  rest_api_id         = aws_api_gateway_rest_api.app[0].id
  resource_id         = local.api_gateway_resource_ids[local.api_gateway_methods[each.key].resource_key]
  http_method         = aws_api_gateway_method.this[each.key].http_method
  status_code         = each.value.status_code
  response_parameters = each.value.response_parameters
  response_templates  = each.value.response_templates

  lifecycle {
    ignore_changes = [response_templates]
  }

  depends_on = [
    aws_api_gateway_integration.this,
    aws_api_gateway_method_response.this,
  ]
}

resource "aws_api_gateway_deployment" "app" {
  count = var.enable_api_gateway && var.enabled_api_gateway_deployment ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.app[0].id

  triggers = {
    redeployment = sha1(jsonencode({
      resources             = values(local.api_gateway_resource_ids)
      methods               = [for method in aws_api_gateway_method.this : method.id]
      integrations          = [for integration in aws_api_gateway_integration.this : integration.id]
      method_responses      = [for response in aws_api_gateway_method_response.this : response.id]
      integration_responses = [for response in aws_api_gateway_integration_response.this : response.id]
    }))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "app" {
  count = var.enable_api_gateway ? 1 : 0

  deployment_id = var.enabled_api_gateway_deployment ? aws_api_gateway_deployment.app[0].id : var.api_gateway_deployment_id
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
