output "audit_key_arn" {
  description = "ARN of the key that encrypts the trail, Config and the trail log group."
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

output "alerts_key_arn" {
  description = "ARN of the key that encrypts the alerts topic."
  value       = aws_kms_key.alerts.arn
}

output "backup_key_arn" {
  description = "ARN of the key that encrypts the backup vault."
  value       = aws_kms_key.backup.arn
}
