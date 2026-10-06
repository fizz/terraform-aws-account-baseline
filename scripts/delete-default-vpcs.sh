#!/usr/bin/env bash
# Deletes the default VPC in every enabled region of the account your credentials
# point at. A new account has one in each region, and Security Hub flags them: they
# have public subnets, an internet gateway and a permissive default security group
# that nothing you build will use.
#
#   AWS_PROFILE=my-profile ./delete-default-vpcs.sh            # list what it would delete
#   AWS_PROFILE=my-profile ./delete-default-vpcs.sh --delete   # delete
#
# It skips a default VPC that still holds network interfaces, and says so. Delete the
# resources in it first, or leave it. It is a script and not Terraform because the
# default VPC exists before any Terraform runs.
set -euo pipefail

MODE="${1:---list}"
case "$MODE" in --list | --delete) ;; *) echo "usage: $0 [--list|--delete]" >&2; exit 2 ;; esac

# One call, in one region. Both region variables are set because tools read different
# ones, and a mismatch sends a call to the wrong endpoint.
in_region() {
  local region="$1"; shift
  AWS_REGION="$region" AWS_DEFAULT_REGION="$region" aws --region "$region" "$@"
}

account=$(AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 aws --region us-east-1 sts get-caller-identity --query Account --output text)
echo "account ${account}, mode ${MODE}"

regions=$(AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 aws --region us-east-1 ec2 describe-regions \
  --query 'Regions[].RegionName' --output text)

found=0
for region in $regions; do
  vpc=$(in_region "$region" ec2 describe-vpcs --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo None)
  [ "$vpc" = "None" ] && continue
  found=$((found + 1))

  enis=$(in_region "$region" ec2 describe-network-interfaces --filters "Name=vpc-id,Values=${vpc}" \
    --query 'length(NetworkInterfaces)' --output text)
  if [ "$enis" != "0" ]; then
    echo "${region}  ${vpc}  skipped: ${enis} network interface(s) still in it"
    continue
  fi

  if [ "$MODE" = "--list" ]; then
    echo "${region}  ${vpc}  would delete"
    continue
  fi

  for igw in $(in_region "$region" ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${vpc}" --query 'InternetGateways[].InternetGatewayId' --output text); do
    in_region "$region" ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc"
    in_region "$region" ec2 delete-internet-gateway --internet-gateway-id "$igw"
  done
  for subnet in $(in_region "$region" ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc}" \
    --query 'Subnets[].SubnetId' --output text); do
    in_region "$region" ec2 delete-subnet --subnet-id "$subnet"
  done
  in_region "$region" ec2 delete-vpc --vpc-id "$vpc"
  echo "${region}  ${vpc}  deleted"
done

echo "default VPCs found: ${found}"
