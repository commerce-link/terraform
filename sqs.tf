resource "aws_sqs_queue" "dlq" {
  for_each = local.sqs_queues

  name                        = try(var.sqs_dlq_name_overrides[each.key], each.value.dlq_name, try(each.value.fifo_queue, false) ? "${trimsuffix(each.key, ".fifo")}-dlq.fifo" : "${each.key}-dlq")
  fifo_queue                  = try(each.value.fifo_queue, false)
  content_based_deduplication = try(each.value.dlq_content_based_deduplication, false)
  message_retention_seconds   = try(each.value.dlq_message_retention_seconds, 1209600)
  max_message_size            = try(each.value.dlq_max_message_size, 262144)
  visibility_timeout_seconds  = try(each.value.dlq_visibility_timeout_seconds, 30)
}

resource "aws_sqs_queue" "app" {
  for_each = local.sqs_queues

  name                        = each.key
  fifo_queue                  = try(each.value.fifo_queue, false)
  content_based_deduplication = try(each.value.content_based_deduplication, false)
  visibility_timeout_seconds  = try(each.value.visibility_timeout_seconds, 30)
  message_retention_seconds   = try(each.value.message_retention_seconds, 345600)
  max_message_size            = try(each.value.max_message_size, 1048576)
  delay_seconds               = try(each.value.delay_seconds, 0)
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = try(each.value.max_receive_count, 3)
  })
}