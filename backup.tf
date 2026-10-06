# AWS Backup. Tag a resource Backup=true and it gets a daily recovery point kept
# for backup_retention_days and a monthly one kept for a year.

resource "aws_backup_vault" "main" {
  count = var.enable_backup ? 1 : 0

  name        = "${local.prefix}-vault"
  kms_key_arn = aws_kms_key.backup.arn
}

resource "aws_iam_role" "backup" {
  count = var.enable_backup ? 1 : 0

  name = "${local.prefix}-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = var.enable_backup ? toset([
    "arn:${local.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:${local.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ]) : toset([])

  role       = aws_iam_role.backup[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "backup_key" {
  count = var.enable_backup ? 1 : 0

  name = "use-backup-key"
  role = aws_iam_role.backup[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:ReEncrypt*"]
        Resource = aws_kms_key.backup.arn
      },
      {
        Effect    = "Allow"
        Action    = "kms:CreateGrant"
        Resource  = aws_kms_key.backup.arn
        Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } }
      },
    ]
  })
}

resource "aws_backup_plan" "main" {
  count = var.enable_backup ? 1 : 0

  name = "${local.prefix}-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = "cron(0 5 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  rule {
    rule_name         = "monthly"
    target_vault_name = aws_backup_vault.main[0].name
    schedule          = "cron(0 6 1 * ? *)"

    lifecycle {
      delete_after = 365
    }
  }
}

resource "aws_backup_selection" "tagged" {
  count = var.enable_backup ? 1 : 0

  name         = "tagged-backup-true"
  plan_id      = aws_backup_plan.main[0].id
  iam_role_arn = aws_iam_role.backup[0].arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}
