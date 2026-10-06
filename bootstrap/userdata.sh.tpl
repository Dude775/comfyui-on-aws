#!/bin/bash
# First-boot bootstrap for the ComfyUI GPU node (AWS Deep Learning AMI, Ubuntu 22.04).
# Rendered by Terraform templatefile(): only ${bucket} and ${region} are substituted.
set -euo pipefail
exec > >(tee -a /var/log/comfy-bootstrap.log) 2>&1

BUCKET="${bucket}"
REGION="${region}"
COMFY_HOME=/home/ubuntu/ComfyUI
VENV=/home/ubuntu/venv
STAGE=/opt/comfy-bootstrap

echo "[bootstrap] start $(date -Is)"

apt-get update -y
apt-get install -y python3-venv git jq

# 1. Pull versioned boot assets (watchdog, units, sync script) from S3
mkdir -p "$STAGE"
aws s3 sync "s3://$BUCKET/bootstrap/" "$STAGE/" --region "$REGION" --only-show-errors
chmod +x "$STAGE"/*.sh "$STAGE"/watchdog/*.sh

# 2. ComfyUI + GGUF loader (city96 is the canonical GGUF node repo)
if [ ! -d "$COMFY_HOME" ]; then
  sudo -u ubuntu git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY_HOME"
fi
if [ ! -d "$COMFY_HOME/custom_nodes/ComfyUI-GGUF" ]; then
  sudo -u ubuntu git clone --depth 1 https://github.com/city96/ComfyUI-GGUF.git "$COMFY_HOME/custom_nodes/ComfyUI-GGUF"
fi

sudo -u ubuntu python3 -m venv "$VENV"
sudo -u ubuntu "$VENV/bin/pip" install --upgrade pip wheel
sudo -u ubuntu "$VENV/bin/pip" install torch torchvision --index-url https://download.pytorch.org/whl/cu126
sudo -u ubuntu "$VENV/bin/pip" install -r "$COMFY_HOME/requirements.txt"
sudo -u ubuntu "$VENV/bin/pip" install -r "$COMFY_HOME/custom_nodes/ComfyUI-GGUF/requirements.txt"

install -m 0644 "$STAGE/systemd/comfyui.service" /etc/systemd/system/comfyui.service
systemctl daemon-reload
systemctl enable --now comfyui.service

echo "[bootstrap] done $(date -Is)"
