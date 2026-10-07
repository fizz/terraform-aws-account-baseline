# Cost controls: a monthly budget and anomaly detection, both to the alerts topic.
#
# Cost tags appear in Cost Explorer only after the management account activates
# them, and AWS does not backfill a tag that was not active when the cost was
# incurred. terraform-aws-organization-baseline does the activation.

resource "aws_budgets_budget" "monthly" {
  count = var.monthly_budget_usd == null ? 0 : 1

  name         = "${local.prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Gross spend. Credits and refunds would hide the real run rate.
  cost_types {
    include_credit = false
    include_refund = false
  }

  dynamic "notification" {
    for_each = toset(var.budget_alert_percentages)

    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
    }
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.alerts]
}

# AWS allows one SERVICE-dimension monitor per account and creates Default-Services-Monitor
# itself in new accounts, so creating a second fails with "Limit exceeded". Pass that
# monitor's ARN as anomaly_monitor_arn to subscribe to it instead.
resource "aws_ce_anomaly_monitor" "services" {
  count = var.anomaly_monitor_arn == null ? 1 : 0

  name              = "${local.prefix}-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

moved {
  from = aws_ce_anomaly_monitor.services
  to   = aws_ce_anomaly_monitor.services[0]
}

locals {
  anomaly_monitor_arn = var.anomaly_monitor_arn != null ? var.anomaly_monitor_arn : aws_ce_anomaly_monitor.services[0].arn
}

resource "aws_ce_anomaly_subscription" "alerts" {
  name             = "${local.prefix}-anomalies"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [local.anomaly_monitor_arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.alerts.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }

  depends_on = [aws_sns_topic_policy.alerts]
}
