# The alerts topic, and the CloudTrail metric alarms that publish to it.
#
# These seven are the CIS monitoring controls that are quiet in normal operation.
# The CIS controls for IAM, security group, route table and gateway changes are left
# out on purpose: every Terraform apply trips them, so they would alarm on each
# deploy and teach everyone to ignore the topic.

resource "aws_sns_topic" "alerts" {
  name              = "${local.prefix}-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountOwner"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["SNS:Publish", "SNS:Subscribe", "SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:ListSubscriptionsByTopic", "SNS:DeleteTopic", "SNS:AddPermission", "SNS:RemovePermission"]
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "AWS:SourceOwner" = local.account_id } }
      },
      {
        Sid       = "AlertPublishers"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.amazonaws.com", "budgets.amazonaws.com", "costalerts.amazonaws.com"] }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "CloudTrailPublishes"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

locals {
  alarms = {
    root-account-use = {
      description = "The root user did something. Root is not used here."
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      threshold   = 1
    }
    console-login-without-mfa = {
      description = "An IAM user signed in to the console without MFA."
      pattern     = "{ ($.eventName = \"ConsoleLogin\") && ($.additionalEventData.MFAUsed != \"Yes\") && ($.userIdentity.type = \"IAMUser\") && ($.responseElements.ConsoleLogin = \"Success\") }"
      threshold   = 1
    }
    console-login-failures = {
      description = "Three failed console sign-ins in five minutes."
      pattern     = "{ ($.eventName = ConsoleLogin) && ($.errorMessage = \"Failed authentication\") }"
      threshold   = 3
    }
    unauthorized-api-calls = {
      description = "Ten denied API calls in five minutes."
      pattern     = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"
      threshold   = 10
    }
    kms-key-disabled-or-deleted = {
      description = "A customer-managed key was disabled or scheduled for deletion."
      pattern     = "{ ($.eventSource = kms.amazonaws.com) && (($.eventName = DisableKey) || ($.eventName = ScheduleKeyDeletion)) }"
      threshold   = 1
    }
    cloudtrail-config-change = {
      description = "A trail was changed, stopped or deleted."
      pattern     = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"
      threshold   = 1
    }
    config-change = {
      description = "The Config recorder or delivery channel was changed or stopped."
      pattern     = "{ ($.eventSource = config.amazonaws.com) && (($.eventName = StopConfigurationRecorder) || ($.eventName = DeleteDeliveryChannel) || ($.eventName = PutDeliveryChannel) || ($.eventName = PutConfigurationRecorder)) }"
      threshold   = 1
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "alarm" {
  for_each = local.alarms

  name           = "${local.prefix}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.key
    namespace = "${var.name}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "alarm" {
  for_each = local.alarms

  alarm_name          = "${local.prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "${var.name}/Security"
  metric_name         = each.key
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  depends_on = [aws_cloudwatch_log_metric_filter.alarm]
}
