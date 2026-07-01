resource "aws_sqs_queue" "dlq" {
  for_each = local.sqs_queues

  name                        = try(each.value.dlq_name, try(each.value.fifo_queue, false) ? "${trimsuffix(each.key, ".fifo")}-dlq.fifo" : "${each.key}-dlq")
  fifo_queue                  = try(each.value.fifo_queue, false)
  content_based_deduplication = try(each.value.content_based_deduplication, false)
  message_retention_seconds   = try(each.value.dlq_message_retention_seconds, 1209600)
}

resource "aws_sqs_queue" "app" {
  for_each = local.sqs_queues

  name                        = each.key
  fifo_queue                  = try(each.value.fifo_queue, false)
  content_based_deduplication = try(each.value.content_based_deduplication, false)
  visibility_timeout_seconds  = try(each.value.visibility_timeout_seconds, 30)
  message_retention_seconds   = try(each.value.message_retention_seconds, 345600)
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = try(each.value.max_receive_count, 3)
  })
}
