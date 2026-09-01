resource "aws_cloudwatch_metric_alarm" "marketplace_order_lifecycle_dlq" {
  alarm_name          = "${var.environment}-marketplace-order-lifecycle-dlq-not-empty"
  alarm_description   = "A marketplace order or return decision failed 3 times and landed in the DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    # aws_sqs_queue.dlq is for_each'd over local.sqs_queues, so it is keyed by the
    # main queue's key (not by dlq_name). The resulting queue's .name attribute is
    # the actual DLQ name, derived from dlq_name.
    QueueName = aws_sqs_queue.dlq["marketplace-order-lifecycle-queue"].name
  }
}
