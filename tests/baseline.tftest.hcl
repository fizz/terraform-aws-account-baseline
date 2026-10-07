# Plan-level checks with a mocked provider: no credentials, no account.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      id = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  name               = "test"
  monthly_budget_usd = 500
}

run "trail_bucket_is_born_with_object_lock" {
  command = plan

  assert {
    condition     = aws_s3_bucket.cloudtrail.object_lock_enabled == true
    error_message = "The CloudTrail bucket must be created with Object Lock. It cannot be added later."
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.cloudtrail.rule[0].default_retention[0].mode == "GOVERNANCE"
    error_message = "Object Lock defaults to GOVERNANCE."
  }

  assert {
    condition     = aws_s3_bucket_object_lock_configuration.cloudtrail.rule[0].default_retention[0].days == 365
    error_message = "Default retention is 365 days."
  }
}

run "lifecycle_never_expires_before_the_lock" {
  command = plan

  variables {
    audit_retention_days = 400
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.cloudtrail.rule[0].expiration[0].days > aws_s3_bucket_object_lock_configuration.cloudtrail.rule[0].default_retention[0].days
    error_message = "Expiry shorter than the lock makes the nightly delete fail without a sign."
  }
}

run "trail_is_multi_region_and_validated" {
  command = plan

  assert {
    condition     = aws_cloudtrail.main.is_multi_region_trail && aws_cloudtrail.main.enable_log_file_validation
    error_message = "The trail must be multi-region and validate log files."
  }
}

run "data_events_only_when_buckets_are_named" {
  command = plan

  assert {
    condition     = length([for s in aws_cloudtrail.main.advanced_event_selector : s.name]) == 1
    error_message = "With no data-event buckets there is one selector, for management events."
  }
}

run "data_events_added_for_named_buckets" {
  command = plan

  variables {
    data_event_bucket_arns = ["arn:aws:s3:::example-dataset"]
  }

  assert {
    condition     = length([for s in aws_cloudtrail.main.advanced_event_selector : s.name]) == 2
    error_message = "A named bucket adds an S3 data-event selector."
  }
}

run "config_delivery_has_no_key_prefix" {
  command = plan

  assert {
    condition     = aws_config_delivery_channel.main.s3_key_prefix == null
    error_message = "A prefix containing AWSLogs/ is rejected by Config."
  }
}

run "both_packs_on_by_default" {
  command = plan

  assert {
    condition     = length(aws_config_conformance_pack.cis) == 1 && length(aws_config_conformance_pack.hipaa) == 1
    error_message = "CIS and HIPAA packs are on by default."
  }
}

run "packs_can_be_turned_off_and_extended" {
  command = plan

  variables {
    enable_cis_pack   = false
    enable_hipaa_pack = false
    additional_conformance_packs = {
      mine = "Resources:\n  Example:\n    Type: AWS::Config::ConfigRule\n"
    }
  }

  assert {
    condition     = length(aws_config_conformance_pack.cis) == 0 && length(aws_config_conformance_pack.hipaa) == 0
    error_message = "Both bundled packs must switch off."
  }

  assert {
    condition     = length(aws_config_conformance_pack.additional) == 1
    error_message = "A supplied pack is deployed."
  }
}

run "seven_quiet_alarms" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.alarm) == 7
    error_message = "There are seven alarms, and none that fires on every apply."
  }
}

run "anomaly_monitor_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_ce_anomaly_monitor.services) == 1
    error_message = "With no ARN given, the module creates the monitor."
  }
}

run "existing_anomaly_monitor_is_reused" {
  command = plan

  variables {
    anomaly_monitor_arn = "arn:aws:ce::111122223333:anomalymonitor/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(aws_ce_anomaly_monitor.services) == 0
    error_message = "A given ARN means no second monitor, which AWS would reject."
  }

  assert {
    condition     = aws_ce_anomaly_subscription.alerts.monitor_arn_list == tolist(["arn:aws:ce::111122223333:anomalymonitor/00000000-0000-0000-0000-000000000000"])
    error_message = "The subscription uses the given monitor."
  }
}

run "no_budget_when_none_given" {
  command = plan

  variables {
    monthly_budget_usd = null
  }

  assert {
    condition     = length(aws_budgets_budget.monthly) == 0
    error_message = "A null budget creates none."
  }
}

run "backup_switches_off" {
  command = plan

  variables {
    enable_backup = false
  }

  assert {
    condition     = length(aws_backup_vault.main) == 0 && length(aws_backup_plan.main) == 0
    error_message = "enable_backup = false creates no vault and no plan."
  }
}

run "short_retention_is_refused" {
  command = plan

  variables {
    audit_retention_days = 30
  }

  expect_failures = [var.audit_retention_days]
}

run "three_keys_with_different_readers" {
  command = plan

  assert {
    condition     = length(toset([aws_kms_key.audit.description, aws_kms_key.alerts.description, aws_kms_key.backup.description])) == 3
    error_message = "The audit, alerts and backup keys are separate keys."
  }
}

run "log_delivery_notices_are_off_by_default" {
  command = plan

  assert {
    condition     = aws_cloudtrail.main.sns_topic_name == null
    error_message = "CloudTrail must not publish a message per delivered log file unless asked to."
  }
}

run "log_delivery_notices_can_be_enabled" {
  command = plan

  variables {
    notify_on_log_delivery = true
  }

  assert {
    condition     = aws_cloudtrail.main.sns_topic_name == "test-alerts"
    error_message = "notify_on_log_delivery = true must publish to the alerts topic."
  }
}
