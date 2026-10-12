#!/usr/bin/env bash
# teardown.sh - inventory and (optionally) delete every billable resource the stack
# created. Default is a read-only inventory; deletion needs --apply AND a typed confirm.
#
# Order matters: compute -> volumes -> bucket -> IAM. A bucket cannot be deleted while
# an instance profile still references the role that writes into it.
set -euo pipefail

REGION="${REGION:-us-east-1}"
PROJECT="${PROJECT:-comfyui-gpu}"
BUCKET="${BUCKET:-}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

log() { printf '[teardown] %s\n' "$*"; }
aws_() { aws --region "$REGION" "$@"; }

log "region=$REGION project=$PROJECT mode=$([ $APPLY = 1 ] && echo APPLY || echo inventory)"

mapfile -t INSTANCES < <(aws_ ec2 describe-instances \
  --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | sed '/^$/d')
mapfile -t VOLUMES < <(aws_ ec2 describe-volumes --filters "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' --output text | tr '\t' '\n' | sed '/^$/d')
mapfile -t EIPS < <(aws_ ec2 describe-addresses --query 'Addresses[?AssociationId==`null`].AllocationId' \
  --output text | tr '\t' '\n' | sed '/^$/d')

log "instances:        ${#INSTANCES[@]} ${INSTANCES[*]:-}"
log "detached volumes: ${#VOLUMES[@]} ${VOLUMES[*]:-}"
log "idle elastic IPs: ${#EIPS[@]} ${EIPS[*]:-}"
[ -n "$BUCKET" ] && log "bucket:           s3://$BUCKET ($(aws_ s3 ls "s3://$BUCKET" --recursive --summarize 2>/dev/null | awk '/Total Size/{print $3" bytes"}'))"

if [ "$APPLY" != 1 ]; then
  log "inventory only. re-run with --apply to delete."
  exit 0
fi

read -r -p "type the project name ($PROJECT) to DELETE everything above: " answer
[ "$answer" = "$PROJECT" ] || { log "aborted"; exit 1; }

if [ "${#INSTANCES[@]}" -gt 0 ]; then
  aws_ ec2 terminate-instances --instance-ids "${INSTANCES[@]}" >/dev/null
  aws_ ec2 wait instance-terminated --instance-ids "${INSTANCES[@]}"
  log "instances terminated (root volumes deleted with them)"
fi
for v in "${VOLUMES[@]}"; do aws_ ec2 delete-volume --volume-id "$v"; log "deleted $v"; done
for e in "${EIPS[@]}"; do aws_ ec2 release-address --allocation-id "$e"; log "released $e"; done
if [ -n "$BUCKET" ]; then
  aws_ s3 rm "s3://$BUCKET" --recursive --only-show-errors
  aws_ s3api delete-bucket --bucket "$BUCKET"
  log "bucket $BUCKET emptied and deleted"
fi
log "done. verify with: $0   (inventory should be empty)"
