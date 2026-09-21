resource "aws_scheduler_schedule_group" "app" {
  count = var.schedule_group_name == null ? 1 : 0
  name  = local.name_prefix
}

resource "aws_scheduler_schedule" "app" {
  for_each = var.scheduler_schedules

  name        = try(var.scheduler_schedule_name_overrides[each.key], each.key)
  group_name  = try(aws_scheduler_schedule_group.app[0].name, var.schedule_group_name)
  state       = try(each.value.enabled, true) ? "ENABLED" : "DISABLED"
  description = try(each.value.description, null)

  schedule_expression          = each.value.schedule_expression
  schedule_expression_timezone = try(each.value.timezone, "Poland")

  flexible_time_window {
    mode                      = try(each.value.time_window_mode, "OFF")
    maximum_window_in_minutes = try(each.value.time_window_maximum_window_in_minutes, null)
  }

  target {
    arn      = aws_sqs_queue.app[each.value.queue_name].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = try(each.value.input, null)
    retry_policy {
      maximum_event_age_in_seconds = 86400
      maximum_retry_attempts       = try(each.value.maximum_retry_attempts, 0)
    }
  }
}
