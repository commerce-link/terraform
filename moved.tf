moved {
  from = aws_scheduler_schedule_group.app
  to   = aws_scheduler_schedule_group.app[0]
}