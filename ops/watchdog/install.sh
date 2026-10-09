#!/usr/bin/env bash
#
# install.sh — install the ComfyUI GPU-idle watchdog on the EC2 host.
# Run on the instance as root:  sudo bash install.sh
#
# Idempotent: safe to re-run. Existing /etc/default/comfyui-watchdog is kept.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DST=/usr/local/bin/comfyui-watchdog.sh
ENV_DST=/etc/default/comfyui-watchdog
UNIT_DIR=/etc/systemd/system
DOC_DIR=/usr/local/share/comfyui-watchdog

if [ "$(id -u)" -ne 0 ]; then
  echo "install.sh must run as root (use sudo)" >&2
  exit 1
fi

echo ">> installing script -> ${BIN_DST}"
install -m 0755 "${SRC_DIR}/comfyui-watchdog.sh" "${BIN_DST}"

if [ ! -f "${ENV_DST}" ]; then
  echo ">> installing config -> ${ENV_DST}"
  install -m 0644 "${SRC_DIR}/comfyui-watchdog.env" "${ENV_DST}"
else
  echo ">> keeping existing config ${ENV_DST} (not overwritten)"
fi

echo ">> installing systemd units -> ${UNIT_DIR}"
install -m 0644 "${SRC_DIR}/comfyui-watchdog.service" "${UNIT_DIR}/comfyui-watchdog.service"
install -m 0644 "${SRC_DIR}/comfyui-watchdog.timer"   "${UNIT_DIR}/comfyui-watchdog.timer"

mkdir -p "${DOC_DIR}"
if [ -f "${SRC_DIR}/README.md" ]; then
  install -m 0644 "${SRC_DIR}/README.md" "${DOC_DIR}/README.md"
fi

# state dir must persist across stop/start (root EBS volume, not tmpfs)
mkdir -p /var/lib/comfyui-watchdog
chmod 755 /var/lib/comfyui-watchdog

# pre-flight checks (warnings only)
command -v nvidia-smi >/dev/null 2>&1 || echo "WARN: nvidia-smi not found yet — the watchdog will fail safe (no shutdown) until the driver is up"
command -v aws       >/dev/null 2>&1 || echo "WARN: aws CLI not found — output sync will be skipped"
if [ ! -d /home/ubuntu/ComfyUI/output ]; then
  echo "WARN: /home/ubuntu/ComfyUI/output not found — set OUTPUT_DIR in ${ENV_DST}"
fi

systemctl daemon-reload
systemctl enable --now comfyui-watchdog.timer

echo ">> enabled. current timer status:"
systemctl --no-pager --full status comfyui-watchdog.timer || true
echo
echo ">> run one tick now to check it:  sudo ${BIN_DST}"
echo ">> pause auto-shutdown:            sudo touch /var/lib/comfyui-watchdog/hold"
echo ">> resume auto-shutdown:           sudo rm -f /var/lib/comfyui-watchdog/hold"
echo ">> watch the log:                  journalctl -u comfyui-watchdog.service -f"
