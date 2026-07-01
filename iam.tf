data "aws_iam_policy_document" "beanstalk_service_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["elasticbeanstalk.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "beanstalk_service" {
  name               = "${local.name_prefix}-beanstalk-service"
  assume_role_policy = data.aws_iam_policy_document.beanstalk_service_assume_role.json
}

resource "aws_iam_role_policy_attachment" "beanstalk_enhanced_health" {
  role       = aws_iam_role.beanstalk_service.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "beanstalk_managed_updates" {
  role       = aws_iam_role.beanstalk_service.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

data "aws_iam_policy_document" "app_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name_prefix}-app"
  assume_role_policy = data.aws_iam_policy_document.app_assume_role.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app"
  role = aws_iam_role.app.name
}

resource "aws_iam_role_policy_attachment" "app_beanstalk_web_tier" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

data "aws_iam_policy_document" "app_dynamodb" {
  statement {
    sid = "DynamoDbAppTables"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem",
      "dynamodb:CreateTable",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/*",
      "arn:${data.aws_partition.current.partition}:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/*/index/*",
    ]
  }
}

data "aws_iam_policy_document" "app" {
  statement {
    sid = "S3AppBuckets"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
    resources = concat(
      [for bucket in aws_s3_bucket.app : bucket.arn],
      [for bucket in aws_s3_bucket.app : "${bucket.arn}/*"]
    )
  }

  statement {
    sid = "SqsAppQueues"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
    ]
    resources = concat(
      [for queue in aws_sqs_queue.app : queue.arn],
      [for queue in aws_sqs_queue.dlq : queue.arn]
    )
  }

  statement {
    sid = "SesSend"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
      "ses:SendTemplatedEmail",
      "ses:SendBulkTemplatedEmail",
    ]
    resources = ["*"]
  }

  statement {
    sid = "SecretsManagerConfiguredPrefixes"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
    ]
    resources = concat(
      [aws_secretsmanager_secret.cognito_client_secret.arn],
      [aws_secretsmanager_secret.valkey_auth_token.arn],
      [
        for prefix in var.secret_name_prefixes :
        "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${prefix}*"
      ]
    )
  }

  statement {
    sid = "SsmConfiguredPrefixes"
    actions = [
      "ssm:DeleteParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:PutParameter",
    ]
    resources = concat(
      [
        for prefix in var.parameter_name_prefixes :
        "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${prefix}*"
      ],
      [aws_ssm_parameter.valkey_endpoint.arn]
    )
  }

  statement {
    sid = "SchedulerAppSchedules"
    actions = [
      "scheduler:CreateSchedule",
      "scheduler:DeleteSchedule",
      "scheduler:GetSchedule",
      "scheduler:ListSchedules",
      "scheduler:UpdateSchedule",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/*/*"]
  }
}

data "aws_iam_policy_document" "app_scheduler_pass_role" {
  statement {
    sid       = "PassSchedulerRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.scheduler.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "app" {
  name   = "${local.name_prefix}-app"
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_policy" "app_dynamodb" {
  name   = "${local.name_prefix}-app-dynamodb"
  policy = data.aws_iam_policy_document.app_dynamodb.json
}

resource "aws_iam_policy" "app_scheduler_pass_role" {
  name   = "${local.name_prefix}-eventbridge-scheduler-pass-role"
  policy = data.aws_iam_policy_document.app_scheduler_pass_role.json
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}

resource "aws_iam_role_policy_attachment" "app_dynamodb" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "app_scheduler_pass_role" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_scheduler_pass_role.arn
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name_prefix}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [for queue in aws_sqs_queue.app : queue.arn]
  }
}

resource "aws_iam_policy" "scheduler" {
  name   = "${local.name_prefix}-scheduler"
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_iam_role_policy_attachment" "scheduler" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.scheduler.arn
}
