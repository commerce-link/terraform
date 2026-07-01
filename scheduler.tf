resource "aws_scheduler_schedule_group" "app" {
  name = local.name_prefix
}

resource "aws_scheduler_schedule" "app" {
  for_each = var.scheduler_schedules

  name       = each.key
  group_name = aws_scheduler_schedule_group.app.name
  state      = try(each.value.enabled, true) ? "ENABLED" : "DISABLED"

  schedule_expression          = each.value.schedule_expression
  schedule_expression_timezone = try(each.value.timezone, "Europe/Warsaw")

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.app[each.value.queue_name].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = try(each.value.input, null)
  }
}
