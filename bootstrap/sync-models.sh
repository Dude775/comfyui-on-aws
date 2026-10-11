#!/usr/bin/env bash
# comfy-sync-models.sh - pull model weights from S3 onto instance-store NVMe and
# point ComfyUI's models/ dir at it. Runs on every boot via comfy-models.service.
#
# Why: the DLAMI mounts the NVMe at /opt/dlami/nvme a little AFTER early boot.
# Syncing before the mount wrote ~13 GB onto the root EBS volume and filled it to
# 100%. This script refuses to run until the mount is real.
set -euo pipefail

# shellcheck disable=SC1091
[ -f /etc/default/comfy-models ] && . /etc/default/comfy-models

: "${BUCKET:?BUCKET not set}"
: "${REGION:=us-east-1}"
: "${NVME_MOUNT:=/opt/dlami/nvme}"
: "${COMFY_HOME:=/home/ubuntu/ComfyUI}"
: "${MOUNT_WAIT_SEC:=300}"
: "${MIN_FREE_GB:=30}"

log() { echo "[sync-models] $*"; }

waited=0
until mountpoint -q "$NVME_MOUNT"; do
  if [ "$waited" -ge "$MOUNT_WAIT_SEC" ]; then
    log "ERROR: $NVME_MOUNT is not a mountpoint after ${MOUNT_WAIT_SEC}s - refusing to sync onto root disk"
    exit 1
  fi
  sleep 5; waited=$((waited + 5))
done
log "NVMe mounted at $NVME_MOUNT (waited ${waited}s)"

free_gb=$(df -BG --output=avail "$NVME_MOUNT" | tail -1 | tr -dc '0-9')
if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then
  log "ERROR: only ${free_gb}G free on $NVME_MOUNT (need ${MIN_FREE_GB}G)"
  exit 1
fi

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
