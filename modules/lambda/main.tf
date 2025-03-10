module "label" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=0.21.0"
  context = var.label_context
}

resource "aws_lambda_function" "autospotting" {
  function_name    = "autospotting-lambda-${module.label.id}"
  filename         = var.lambda_zipname
  source_code_hash = var.lambda_zipname == null ? null : filebase64sha256(var.lambda_zipname)
  s3_bucket        = var.lambda_zipname == null ? var.lambda_s3_bucket : null
  s3_key           = var.lambda_zipname == null ? var.lambda_s3_key : null
  role             = aws_iam_role.autospotting_role.arn
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  handler          = "AutoSpotting"
  memory_size      = var.lambda_memory_size
  tags             = merge(var.lambda_tags, module.label.tags)

  environment {
    variables = {
      ALLOWED_INSTANCE_TYPES          = var.autospotting_allowed_instance_types
      BIDDING_POLICY                  = var.autospotting_bidding_policy
      CRON_SCHEDULE                   = var.autospotting_cron_schedule
      CRON_SCHEDULE_STATE             = var.autospotting_cron_schedule_state
      CRON_TIMEZONE                   = var.autospotting_cron_timezone
      DISALLOWED_INSTANCE_TYPES       = var.autospotting_disallowed_instance_types
      INSTANCE_TERMINATION_METHOD     = var.autospotting_instance_termination_method
      LICENSE                         = var.autospotting_license
      MIN_ON_DEMAND_NUMBER            = var.autospotting_min_on_demand_number
      MIN_ON_DEMAND_PERCENTAGE        = var.autospotting_min_on_demand_percentage
      ON_DEMAND_PRICE_MULTIPLIER      = var.autospotting_on_demand_price_multiplier
      PATCH_BEANSTALK_USERDATA        = var.autospotting_patch_beanswalk_userdata
      REGIONS                         = join(",", var.autospotting_regions_enabled)
      SPOT_PRICE_BUFFER_PERCENTAGE    = var.autospotting_spot_price_buffer_percentage
      SPOT_PRODUCT_DESCRIPTION        = var.autospotting_spot_product_description
      SPOT_PRODUCT_PREMIUM            = var.autospotting_spot_product_premium
      SQS_QUEUE_URL                   = aws_sqs_queue.autospotting_fifo_queue.id
      TAG_FILTERING_MODE              = var.autospotting_tag_filtering_mode
      TAG_FILTERS                     = var.autospotting_tag_filters
      TERMINATION_NOTIFICATION_ACTION = var.autospotting_termination_notification_action
    }
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "autospotting_role" {
  name                  = "autospotting-role-${module.label.id}"
  path                  = "/lambda/"
  assume_role_policy    = data.aws_iam_policy_document.lambda_policy.json
  force_detach_policies = true
}

data "aws_iam_policy_document" "autospotting_policy" {
  statement {
    actions = [
      "autoscaling:AttachInstances",
      "autoscaling:CompleteLifecycleAction",
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeLifecycleHooks",
      "autoscaling:DescribeTags",
      "autoscaling:DetachInstances",
      "autoscaling:ResumeProcesses",
      "autoscaling:SuspendProcesses",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
      "cloudformation:Describe*",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeRegions",
      "ec2:DescribeSpotPriceHistory",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "iam:CreateServiceLinkedRole",
      "iam:PassRole",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.autospotting_fifo_queue.arn]
  }
}

resource "aws_iam_role_policy" "autospotting_policy" {
  name   = "policy_for_${module.label.id}"
  role   = aws_iam_role.autospotting_role.id
  policy = data.aws_iam_policy_document.autospotting_policy.json
}

resource "aws_sqs_queue" "autospotting_fifo_queue" {
  name                        = var.sqs_fifo_queue_name
  content_based_deduplication = true
  fifo_queue                  = true
  message_retention_seconds   = 600
  visibility_timeout_seconds  = 300
}

resource "aws_lambda_event_source_mapping" "autospotting_lambda_event_source_mapping" {
  event_source_arn = aws_sqs_queue.autospotting_fifo_queue.arn
  function_name    = aws_lambda_function.autospotting.arn
  depends_on       = [aws_iam_role_policy.autospotting_policy]
}