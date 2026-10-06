terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "baseline" {
  source = "../.."

  name               = "example"
  monthly_budget_usd = 500
  alert_emails       = ["ops@example.com"]

  # Records who read each object, not only who changed the infrastructure.
  data_event_bucket_arns = ["arn:aws:s3:::example-documents"]

  # Switch the bundled packs off, or add your own.
  enable_hipaa_pack = false
}

output "alerts_topic_arn" {
  value = module.baseline.alerts_topic_arn
}
