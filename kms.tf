# Three keys, because they have different readers. One key would let anyone who can
# restore a backup also decrypt the audit trail, which defeats the point of a key
# policy.
#
#   audit    CloudTrail, the Config bucket and the CloudTrail log group. Readers are
#            auditors.
#   alerts   The alerts topic. Readers are the people subscribed to it.
#   backup   AWS Backup recovery points. Readers are whoever restores.
#
# A customer-managed key gives three things that SSE-S3 cannot. S3 permission alone is
# not read permission, because `s3:GetObject` without `kms:Decrypt` returns ciphertext.
# Every `Decrypt` is a CloudTrail event that names the caller. Scheduling the key for
# deletion makes everything it wrote unreadable without touching an object.

locals {
  key_admin_statement = {
    Sid       = "AccountAdministration"
    Effect    = "Allow"
    Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
    Action    = "kms:*"
    Resource  = "*"
  }
}

# --- audit ------------------------------------------------------------------

resource "aws_kms_key" "audit" {
  description             = "${local.prefix} audit trail and Config"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.key_admin_statement,
      {
        Sid       = "CloudTrailEncrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceArn" = local.trail_arn }
          StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/*" }
        }
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.trail_log_group}*" }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "audit" {
  name          = "alias/${local.prefix}-audit"
  target_key_id = aws_kms_key.audit.key_id
}

# --- alerts -----------------------------------------------------------------

resource "aws_kms_key" "alerts" {
  description             = "${local.prefix} alerts topic"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      local.key_admin_statement,
      {
        # Alarms, budgets and anomaly alerts publish to the topic. Publishing to an
        # encrypted topic needs these two actions.
        Sid       = "AlertPublishers"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.amazonaws.com", "budgets.amazonaws.com", "costalerts.amazonaws.com"] }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "CloudTrailPublishes"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
    ]
  })
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${local.prefix}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

# --- backup -----------------------------------------------------------------

# AWS Backup reaches this key through the backup role's own grants. The key policy
# needs only the account administration statement.
resource "aws_kms_key" "backup" {
  description             = "${local.prefix} backup recovery points"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [local.key_admin_statement]
  })
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${local.prefix}-backup"
  target_key_id = aws_kms_key.backup.key_id
}
