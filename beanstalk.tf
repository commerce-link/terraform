resource "aws_elastic_beanstalk_application" "app" {
  name        = coalesce(var.beanstalk_app_name, "${local.name_prefix}-app")
  description = "CommerceLink application"

  appversion_lifecycle {
    delete_source_from_s3 = true
    max_age_in_days       = 0
    max_count             = 50
    service_role          = aws_iam_role.beanstalk_service.arn
  }
}

resource "aws_elastic_beanstalk_environment" "app" {
  name                = coalesce(var.beanstalk_environment_name, "${local.name_prefix}-app")
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = var.beanstalk_solution_stack_name
  cname_prefix        = var.beanstalk_cname_prefix
  version_label       = var.application_version_label

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
    resource  = ""
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
    resource  = ""
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.beanstalk_service.arn
    resource  = ""
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.app.name
    resource  = ""
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.beanstalk_instance_type
    resource  = ""
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "false"
    resource  = ""
  }

  dynamic "setting" {
    for_each = var.beanstalk_assign_security_groups ? [aws_security_group.app.id] : []

    content {
      namespace = "aws:autoscaling:launchconfiguration"
      name      = "SecurityGroups"
      value     = setting.value
      resource  = ""
    }
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = tostring(var.beanstalk_min_size)
    resource  = ""
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = tostring(var.beanstalk_max_size)
    resource  = ""
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.this.id
    resource  = ""
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = local.beanstalk_instance_subnets
    resource  = ""
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = local.beanstalk_elb_subnets
    resource  = ""
  }

  dynamic "setting" {
    for_each = var.beanstalk_assign_security_groups ? [aws_security_group.alb.id] : []

    content {
      namespace = "aws:elbv2:loadbalancer"
      name      = "SecurityGroups"
      value     = setting.value
      resource  = ""
    }
  }

  dynamic "setting" {
    for_each = var.beanstalk_managed_security_group ? [aws_security_group.alb.id] : []

    content {
      namespace = "aws:elbv2:loadbalancer"
      name      = "ManagedSecurityGroup"
      value     = setting.value
      resource  = ""
    }
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "Port"
    value     = "80"
    resource  = ""
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "HealthCheckPath"
    value     = "/env"
    resource  = ""
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "DeploymentPolicy"
    value     = "Rolling"
    resource  = ""
  }

  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name      = "StreamLogs"
    value     = "true"
    resource  = ""
  }

  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name      = "RetentionInDays"
    value     = tostring(var.beanstalk_log_retention_in_days)
    resource  = ""
  }

  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name      = "DeleteOnTerminate"
    value     = "false"
    resource  = ""
  }

  dynamic "setting" {
    for_each = local.beanstalk_ssl_certificate_arn != null ? {
      ListenerEnabled    = "true"
      Protocol           = "HTTPS"
      SSLCertificateArns = local.beanstalk_ssl_certificate_arn
    } : {}

    content {
      namespace = "aws:elbv2:listener:443"
      name      = setting.key
      value     = setting.value
      resource  = ""
    }
  }

  dynamic "setting" {
    for_each = local.beanstalk_app_environment

    content {
      namespace = "aws:elasticbeanstalk:application:environment"
      name      = setting.key
      value     = setting.value
      resource  = ""
    }
  }

  lifecycle {
    ignore_changes = [version_label]
  }
}

data "aws_lb_listener" "http" {
  count = var.app_domain != null && (var.acm_certificate_arn != null || var.create_acm_certificate) ? 1 : 0

  load_balancer_arn = aws_elastic_beanstalk_environment.app.load_balancers[0]
  port              = 80
}

resource "aws_lb_listener_rule" "app_http_to_https" {
  count = var.app_domain != null && (var.acm_certificate_arn != null || var.create_acm_certificate) ? 1 : 0

  listener_arn = data.aws_lb_listener.http[0].arn
  priority     = 1

  action {
    type = "redirect"

    redirect {
      host        = "#{host}"
      path        = "/#{path}"
      port        = "443"
      protocol    = "HTTPS"
      query       = "#{query}"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = [var.app_domain]
    }
  }
}
