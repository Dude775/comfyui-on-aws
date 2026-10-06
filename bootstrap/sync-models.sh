#!/usr/bin/env bash
# comfy-sync-models.sh - pull model weights from S3 onto instance-store NVMe and
# point ComfyUI's models/ dir at it. Runs on every boot via comfy-models.service.
set -euo pipefail

# shellcheck disable=SC1091
[ -f /etc/default/comfy-models ] && . /etc/default/comfy-models

: "${BUCKET:?BUCKET not set}"
: "${REGION:=us-east-1}"
: "${NVME_MOUNT:=/opt/dlami/nvme}"
: "${COMFY_HOME:=/home/ubuntu/ComfyUI}"

log() { echo "[sync-models] $*"; }

DEST="$NVME_MOUNT/models"
mkdir -p "$DEST"
log "syncing s3://$BUCKET/models/ -> $DEST"
aws s3 sync "s3://$BUCKET/models/" "$DEST/" --region "$REGION" --only-show-errors

# models/ must be a symlink to NVMe, never a real dir on root EBS
if [ -d "$COMFY_HOME/models" ] && [ ! -L "$COMFY_HOME/models" ]; then
  mv "$COMFY_HOME/models" "$COMFY_HOME/models.ebs-backup.$(date +%s)"
fi
ln -sfn "$DEST" "$COMFY_HOME/models"
chown -h ubuntu:ubuntu "$COMFY_HOME/models"
chown -R ubuntu:ubuntu "$DEST"

log "done: $(du -sh "$DEST" | cut -f1) of models ready"
