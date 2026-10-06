variable "name" {
  description = "Prefix for every resource name, for example acme-prod. Bucket names also carry the account ID, so the prefix needs only to be unique within the account."
  type        = string
}

variable "audit_retention_days" {
  description = "Days the CloudTrail and Config records are kept. Object Lock holds the CloudTrail records for this long."
  type        = number
  default     = 365

  validation {
    condition     = var.audit_retention_days >= 90
    error_message = "Keep audit records at least 90 days."
  }
}

variable "log_retention_days" {
  description = "Days the CloudWatch log group keeps events. Must be a value CloudWatch Logs accepts."
  type        = number
  default     = 365
}

variable "object_lock_mode" {
  description = "GOVERNANCE or COMPLIANCE for the CloudTrail bucket. COMPLIANCE cannot be shortened by anyone, root included, so choose it only once the retention period is settled."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "data_event_bucket_arns" {
  description = "S3 buckets whose object reads and writes CloudTrail records. Management events alone say who changed the infrastructure but not who read a document."
  type        = list(string)
  default     = []
}

variable "alert_emails" {
  description = "Addresses subscribed to the alerts topic. Each must confirm the subscription AWS emails."
  type        = list(string)
  default     = []
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in US dollars. Null creates no budget."
  type        = number
  default     = null
}

variable "budget_alert_percentages" {
  description = "Percent of the budget at which an actual-spend alert fires. A forecast alert always fires at 100."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "anomaly_threshold_usd" {
  description = "Total impact in US dollars above which a cost anomaly alerts."
  type        = number
  default     = 20
}

variable "enable_cis_pack" {
  description = "Deploy the CIS AWS Foundations v1.4 Level 2 conformance pack."
  type        = bool
  default     = true
}

variable "enable_hipaa_pack" {
  description = "Deploy the HIPAA Security conformance pack."
  type        = bool
  default     = true
}

variable "additional_conformance_packs" {
  description = "Extra conformance packs: name => template body in CloudFormation format. Config accepts up to 51,200 bytes inline."
  type        = map(string)
  default     = {}
}

variable "enable_inspector" {
  description = "Enable Inspector scanning for EC2, ECR and Lambda."
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Create the AWS Backup vault and plan for resources tagged Backup=true."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Days AWS Backup keeps a daily recovery point."
  type        = number
  default     = 35
}
