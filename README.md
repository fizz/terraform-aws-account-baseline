# terraform-aws-account-baseline

The audit, detection, cost and backup controls a new AWS account needs on its first day, in one module.

A new account has no memory. CloudTrail's default event history covers 90 days and nobody can prove it was not edited. Config is not recording, so there is no answer to "what did this security group look like in March". Nothing tells you the bill doubled until the invoice. Each fix is a few lines. The reason this module exists is the order they must go in, and the failures that look like success.

## Usage

```hcl
module "baseline" {
  source  = "fizz/account-baseline/aws"
  version = "~> 0.1"

  name               = "acme-prod"
  monthly_budget_usd = 1000
  alert_emails       = ["ops@example.com"]

  # Who read the documents, not only who changed the infrastructure.
  data_event_bucket_arns = [aws_s3_bucket.documents.arn]
}
```

That creates everything in the table below. Each alert address gets an email from AWS and must confirm it.

| Area | What you get |
|---|---|
| Audit | A multi-region CloudTrail trail with log file validation, in an Object Lock bucket, delivered to CloudWatch Logs |
| Configuration | A Config recorder, and the CIS AWS Foundations v1.4 Level 2 and HIPAA Security conformance packs |
| Detection | GuardDuty, Security Hub with three standards, IAM Access Analyzer, Inspector |
| Account settings | S3 public access blocked account-wide, EBS encryption by default, a password policy |
| Alarms | Seven CloudTrail metric alarms and an alerts topic |
| Cost | A monthly budget and anomaly detection, to the same topic |
| Backup | A daily and a monthly recovery point for every resource tagged `Backup=true` |

## What is hard to get right

**Object Lock exists only at bucket creation.** There is no API that turns it on later. The trail bucket has to be born with it, which is why this is the first thing the module creates. The default mode is `GOVERNANCE`. `COMPLIANCE` cannot be shortened by anyone, root included, so a wrong retention period becomes permanent. Switch to it once the period is settled.

**The lifecycle rule must expire objects after the lock does.** If expiry is shorter than the retention, S3 refuses the delete every night. The rule then fails with no visible sign. The module sets expiry to retention plus one day.

**Config's delivery channel rejects a key prefix that contains `AWSLogs/`.** It writes to `AWSLogs/<account>/Config/` by itself. The module sets no prefix, and the bucket policy grants exactly that path.

**A recorder that exists is not a recorder that records.** Config shows as set up and captures nothing until the recorder status is enabled. The module sets it, and Security Hub waits on it, because most Security Hub controls read from Config.

**The CloudTrail alarms are the seven that stay quiet.** The CIS benchmark also asks for alarms on IAM, security group, route table and gateway changes. Every Terraform apply trips those, so they alarm on each deploy until everyone ignores the topic. They are left out on purpose.

**Management events alone answer half the question.** They say who changed the infrastructure. Data events on the buckets you name in `data_event_bucket_arns` say who read a document.

## Costs

Config, GuardDuty, Security Hub and Inspector bill by usage, and the conformance packs add a charge per rule evaluation. Check Cost Explorer after the first week. Turn off `enable_cis_pack`, `enable_hipaa_pack` or `enable_inspector` if you do not need them. Set `monthly_budget_usd = null` for no budget.

## Main inputs

| Name | Default | Notes |
|---|---|---|
| `audit_retention_days` | `365` | At least 90. Sets Object Lock retention and Config expiry. |
| `object_lock_mode` | `GOVERNANCE` | `COMPLIANCE` is permanent. |
| `monthly_budget_usd` | `null` | No budget when null. |
| `additional_conformance_packs` | `{}` | Name to template body. Config accepts 51,200 bytes inline. |
| `enable_backup` | `true` | Vault, plan and selection. |

## Notes

- Tested on AWS provider 5.100 and 6.0, with `terraform test` and a mocked provider, so the tests need no credentials. It has been planned against a live account and not yet applied to one. Apply it to a test account first.
- The bundled conformance pack templates are AWS's published samples under the Apache License 2.0. See `packs/README.md`.
- Cost allocation tags appear in Cost Explorer only after the management account activates them, and AWS does not backfill. [terraform-aws-organization-baseline](https://github.com/fizz/terraform-aws-organization-baseline) does the activation.
- The module changes account-wide settings: the S3 public access block, EBS default encryption and the password policy. Apply it to accounts where that is what you want.
