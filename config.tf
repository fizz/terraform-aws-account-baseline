# AWS Config: the configuration baseline, and the two conformance packs.

resource "aws_s3_bucket" "config" {
  # checkov:skip=CKV2_AWS_62:Nothing consumes events from the Config bucket.
  bucket = "${local.prefix}-config-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.audit.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    id     = "age-out"
    status = "Enabled"
    filter {}

    expiration {
      days = var.audit_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.config]
}

resource "aws_s3_bucket_logging" "config" {
  bucket        = aws_s3_bucket.config.id
  target_bucket = aws_s3_bucket.cloudtrail_access_logs.id
  target_prefix = "config/"

  depends_on = [aws_s3_bucket_policy.cloudtrail_access_logs]
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.config.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "ConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/${local.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.config]
}

resource "aws_iam_role" "config" {
  name = "${local.prefix}-config"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_delivery" {
  name = "deliver-to-bucket"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/AWSLogs/${local.account_id}/Config/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = aws_kms_key.audit.arn
      },
    ]
  })
}

resource "aws_config_configuration_recorder" "main" {
  name     = "${local.prefix}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${local.prefix}-delivery"
  s3_bucket_name = aws_s3_bucket.config.id
  # No s3_key_prefix. Config writes to AWSLogs/<account>/Config/ on its own, and a
  # prefix that contains AWSLogs/ is rejected with InvalidS3KeyPrefixException. The
  # bucket policy already grants exactly that path.

  depends_on = [aws_config_configuration_recorder.main, aws_s3_bucket_policy.config]
}

# A recorder that exists and is not recording is the usual silent failure: Config
# shows as set up and captures nothing.
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# Pack templates are AWS's published samples, unmodified. See packs/README.md.
resource "aws_config_conformance_pack" "cis" {
  count = var.enable_cis_pack ? 1 : 0

  name          = "${local.prefix}-cis-aws-v1-4-level2"
  template_body = file("${path.module}/packs/Operational-Best-Practices-for-CIS-AWS-v1.4-Level2.yaml")

  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_conformance_pack" "hipaa" {
  count = var.enable_hipaa_pack ? 1 : 0

  name          = "${local.prefix}-hipaa-security"
  template_body = file("${path.module}/packs/Operational-Best-Practices-for-HIPAA-Security.yaml")

  depends_on = [aws_config_configuration_recorder_status.main]
}

# Packs you supply: name => CloudFormation-format template body. Config accepts up to
# 51,200 bytes inline.
resource "aws_config_conformance_pack" "additional" {
  for_each = var.additional_conformance_packs

  name          = "${local.prefix}-${each.key}"
  template_body = each.value

  depends_on = [aws_config_configuration_recorder_status.main]
}
