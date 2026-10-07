#!/usr/bin/env bash
# preflight.sh - run BEFORE starting the GPU node. Fails if anything would make
# the session cost real money or fail halfway.
set -euo pipefail
REGION="${REGION:-us-east-1}"
fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fail=1; }

echo "== identity"
arn=$(aws sts get-caller-identity --query Arn --output text)
case "$arn" in *":root") bad "running as ROOT - use an IAM user";; *) ok "IAM principal";; esac

echo "== G/VT vCPU quota (on-demand, L-DB2E81BA)"
q=$(aws service-quotas get-service-quota --region "$REGION" --service-code ec2 --quota-code L-DB2E81BA \
  --query 'Quota.Value' --output text 2>/dev/null || echo 0)
awk "BEGIN{exit !($q >= 4)}" && ok "quota=$q vCPU" || bad "quota=$q vCPU (g5.xlarge needs 4)"

echo "== my public IP is allowed"
ip=$(curl -fsS https://checkip.amazonaws.com | tr -d '\n')
if aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=${PROJECT:-comfyui-gpu}-sg" \
  --query 'SecurityGroups[].IpPermissions[].IpRanges[].CidrIp' --output text | tr '\t' '\n' | grep -qx "$ip/32"; then
  ok "current IP is in the SG"
else
  bad "current IP not in SG - update allowed_cidrs and terraform apply"
fi

exit $fail
