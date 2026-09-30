locals {
  alerts_slack_enabled = var.alerts_enabled && var.alerts_slack_team_id != null && var.alerts_slack_channel_id != null
  alert_sqs_queues     = var.alerts_enabled ? local.sqs_queues : {}
  alert_actions        = var.alerts_enabled ? [aws_sns_topic.alerts[0].arn] : []
  sqs_console_url      = "https://${var.aws_region}.console.aws.amazon.com/sqs/v3/home?region=${var.aws_region}#/queues"
}

resource "aws_sns_topic" "alerts" {
  count = var.alerts_enabled ? 1 : 0

  name = "${local.name_prefix}-alerts"
}

resource "aws_cloudwatch_metric_alarm" "sqs_backlog" {
  for_each = local.alert_sqs_queues

  alarm_name          = "${local.name_prefix}-sqs-backlog-${aws_sqs_queue.app[each.key].name}"
  alarm_description   = "Queue ${aws_sqs_queue.app[each.key].name} has had more than ${var.alerts_sqs_backlog_threshold} visible messages for 5 minutes. ${local.sqs_console_url}/${urlencode(aws_sqs_queue.app[each.key].url)}"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.app[each.key].name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alerts_sqs_backlog_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alert_actions
  ok_actions          = local.alert_actions
}

resource "aws_cloudwatch_metric_alarm" "sqs_dlq" {
  for_each = local.alert_sqs_queues

  alarm_name          = "${local.name_prefix}-sqs-dlq-${aws_sqs_queue.dlq[each.key].name}"
  alarm_description   = "DLQ ${aws_sqs_queue.dlq[each.key].name} contains messages that failed processing in ${aws_sqs_queue.app[each.key].name}. The alarm returns to OK only after the DLQ is purged or redriven. ${local.sqs_console_url}/${urlencode(aws_sqs_queue.dlq[each.key].url)}"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq[each.key].name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alert_actions
  ok_actions          = local.alert_actions
}

# EnvironmentHealth: 0 Ok, 1 Info, 5 Unknown, 10 No data, 15 Warning, 20 Degraded, 25 Severe.
resource "aws_cloudwatch_metric_alarm" "environment_health" {
  count = var.alerts_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-environment-health"
  alarm_description   = "Environment ${aws_elastic_beanstalk_environment.app.name} has been Degraded or Severe for 5 minutes. https://${var.aws_region}.console.aws.amazon.com/elasticbeanstalk/home?region=${var.aws_region}#/environment/health?environmentId=${aws_elastic_beanstalk_environment.app.id}"
  namespace           = "AWS/ElasticBeanstalk"
  metric_name         = "EnvironmentHealth"
  dimensions          = { EnvironmentName = aws_elastic_beanstalk_environment.app.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 20
  treat_missing_data  = "missing"
  alarm_actions       = local.alert_actions
  ok_actions          = local.alert_actions
}

resource "aws_iam_role" "chatbot" {
  count = local.alerts_slack_enabled ? 1 : 0

  name = "${local.name_prefix}-chatbot"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "chatbot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "chatbot_notifications" {
  count = local.alerts_slack_enabled ? 1 : 0

  name = "notifications"
  role = aws_iam_role.chatbot[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:Describe*", "cloudwatch:Get*", "cloudwatch:List*"]
      Resource = "*"
    }]
  })
}

# Chatbot has no API endpoint in every region; the channel still receives from SNS topics in any region.
resource "aws_chatbot_slack_channel_configuration" "alerts" {
  count = local.alerts_slack_enabled ? 1 : 0

  region                      = var.alerts_chatbot_region
  configuration_name          = "${local.name_prefix}-alerts"
  iam_role_arn                = aws_iam_role.chatbot[0].arn
  slack_team_id               = var.alerts_slack_team_id
  slack_channel_id            = var.alerts_slack_channel_id
  sns_topic_arns              = [aws_sns_topic.alerts[0].arn]
  guardrail_policy_arns       = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchReadOnlyAccess"]
  logging_level               = "ERROR"
  user_authorization_required = false
}
