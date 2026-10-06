output "audit_key_arn" {
  description = "ARN of the audit key."
  value       = aws_kms_key.audit.arn
}

output "cloudtrail_bucket" {
  description = "Name of the CloudTrail bucket."
  value       = aws_s3_bucket.cloudtrail.id
}

output "config_bucket" {
  description = "Name of the Config bucket."
  value       = aws_s3_bucket.config.id
}

output "alerts_topic_arn" {
  description = "ARN of the alerts topic."
  value       = aws_sns_topic.alerts.arn
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault."
  value       = one(aws_backup_vault.main[*].name)
}
