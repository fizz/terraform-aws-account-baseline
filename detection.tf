# Detection: GuardDuty, Security Hub, Access Analyzer and Inspector.

resource "aws_guardduty_detector" "main" {
  # checkov:skip=CKV2_AWS_3:Each account runs its own detector. There is no organization to delegate to.
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_detector_feature" "s3_data_events" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ebs_malware" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

# Security Hub reads its findings for most controls from Config, so the recorder
# must be recording first.
resource "aws_securityhub_account" "main" {
  enable_default_standards = false

  depends_on = [aws_config_configuration_recorder_status.main]
}

# The broadest signal, and the one whose findings are mostly actionable.
resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

# Security Hub has no NIST 800-171 standard. 800-171 derives its controls from
# 800-53, so Rev. 5 is the closest mapping, and the one an assessor recognizes.
resource "aws_securityhub_standards_subscription" "nist_800_53" {
  standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/nist-800-53/v/5.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:${local.partition}:securityhub:${local.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${local.prefix}-account"
  type          = "ACCOUNT"
}

resource "aws_inspector2_enabler" "main" {
  count = var.enable_inspector ? 1 : 0

  account_ids    = [local.account_id]
  resource_types = ["EC2", "ECR", "LAMBDA"]
}
