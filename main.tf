# One account's audit, detection, cost and backup controls. See README.md.
#
# Two things here cannot be added later, which is why they are created first:
#   - S3 Object Lock is settable only when a bucket is created. The CloudTrail bucket
#     is born with it. There is no API to switch it on afterwards.
#   - Audit history. A trail switched on in November cannot answer a question about
#     September.

data "aws_caller_identity" "current" {}
# The region comes from the availability zones data source. Its `id` is the region
# name on provider 5 and 6. `aws_region` has no spelling that works on both: 6 deprecates
# `name` and `id`, and 5 has no `region`.
data "aws_availability_zones" "available" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_availability_zones.available.id
  partition  = data.aws_partition.current.partition
  prefix     = var.name

  trail_name      = "${local.prefix}-trail"
  trail_arn       = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"
  trail_log_group = "/aws/cloudtrail/${local.prefix}"
}
