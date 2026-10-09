#!/usr/bin/env bash
#
# comfyui-watchdog.sh — cost backstop for the ComfyUI / Qwen-Image-Edit EC2 box.
#
# Target host: EC2 g5.xlarge (Ubuntu) running ComfyUI.
#
# What it does, once per invocation (designed to run from a systemd timer every
# 5 minutes, but safe to run by hand):
#   1. Reads GPU utilization. If the GPU has been idle for IDLE_MINUTES
#      consecutive minutes -> sync outputs, then stop the machine.
#   2. Keeps a persistent idle counter so a reboot / timer restart does not
#      reset the clock.
#   3. Syncs OUTPUT_DIR to S3 once every SYNC_INTERVAL_MIN minutes, and always
#      once right before a shutdown.
#
# Safety guards (any of these keeps the box alive):
#   * GPU is busy (util >= GPU_UTIL_THRESHOLD)
#   * ComfyUI queue has a running or pending prompt
#   * a hold file exists (operator wants no auto-shutdown)
#   * an interactive login session is present (optional, on by default)
#   * nvidia-smi cannot be queried -> fail safe, do NOT shut down
#
# Configuration comes from /etc/default/comfyui-watchdog (sourced if present),
# then environment overrides. See print_config for the full list.
#
# Exit codes: 0 normal, 1 config/env error, 2 unable to read GPU (no action).
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (override in /etc/default/comfyui-watchdog)
# ---------------------------------------------------------------------------
: "${GPU_UTIL_THRESHOLD:=5}"          # percent; below this counts as idle
: "${IDLE_MINUTES:=45}"               # consecutive idle minutes before shutdown
: "${CHECK_INTERVAL_MIN:=5}"          # minutes between invocations (timer period)
: "${SYNC_INTERVAL_MIN:=60}"          # output -> S3 sync cadence
: "${STATE_DIR:=/var/lib/comfyui-watchdog}"
: "${LOG_PREFIX:=comfyui-watchdog}"
: "${OUTPUT_DIR:=/home/ubuntu/ComfyUI/output}"
: "${S3_BUCKET:=REPLACE_ME_BUCKET}"
: "${S3_OUTPUT_PREFIX:=outputs/}"
: "${S3_SYNC_EXTRA_ARGS:=--only-show-errors}"
: "${COMFYUI_URL:=http://127.0.0.1:8188}"
: "${HOLD_FILE:=${STATE_DIR}/hold}"
: "${COUNT_ACTIVE_SSH_AS_BUSY:=1}"     # 1 = an interactive login blocks shutdown
: "${DRY_RUN:=0}"                      # 1 = log shutdown instead of doing it
# SUDO: honor an explicit value; otherwise auto-detect (root needs none).
if [ -z "${SUDO+x}" ]; then
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
fi
: "${SHUTDOWN_BIN:=/usr/sbin/shutdown}"
: "${SHUTDOWN_DELAY:=now}"             # 'now' or '+1' (grace minute)
: "${NVIDIA_SMI:=nvidia-smi}"
: "${AWS_BIN:=aws}"
: "${CURL_BIN:=curl}"

# Derived
: "${IDLE_SAMPLES_NEEDED:=$(( IDLE_MINUTES / CHECK_INTERVAL_MIN ))}"
if [ "${IDLE_SAMPLES_NEEDED}" -lt 1 ]; then IDLE_SAMPLES_NEEDED=1; fi

IDLE_FILE="${STATE_DIR}/idle_samples"
LAST_SYNC_FILE="${STATE_DIR}/last_sync_epoch"
LOCK_FILE="${STATE_DIR}/.lock"

log() { printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${LOG_PREFIX}:" "$*" >&2; }

print_config() {
  log "config: threshold=${GPU_UTIL_THRESHOLD}% idle_min=${IDLE_MINUTES} interval_min=${CHECK_INTERVAL_MIN} samples_needed=${IDLE_SAMPLES_NEEDED}"
  log "config: output=${OUTPUT_DIR} s3=s3://${S3_BUCKET}/${S3_OUTPUT_PREFIX} sync_interval_min=${SYNC_INTERVAL_MIN}"
  log "config: comfyui=${COMFYUI_URL} state=${STATE_DIR} hold=${HOLD_FILE} ssh_busy=${COUNT_ACTIVE_SSH_AS_BUSY} dry_run=${DRY_RUN}"
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
ensure_state() {
  if [ ! -d "${STATE_DIR}" ]; then
    ${SUDO} mkdir -p "${STATE_DIR}"
    ${SUDO} chmod 755 "${STATE_DIR}"
  fi
}

read_int_file() { # file default
  local f="$1" d="$2"
  if [ -r "$f" ]; then
    local v; v="$(tr -dc '0-9' < "$f" 2>/dev/null || true)"
    [ -n "$v" ] && { printf '%s' "$v"; return; }
  fi
  printf '%s' "$d"
}

write_int_file() { # file value
  printf '%s\n' "$2" > "$1" 2>/dev/null || {
    ${SUDO} sh -c "printf '%s\n' '$2' > '$1'"
  }
}

gpu_util() {
  # -> integer percent on stdout; non-zero exit if unknown
  local out
  out="$("${NVIDIA_SMI}" --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)" || return 1
  # take the max across multiple GPUs, strip spaces
  printf '%s\n' "$out" | tr -d ' %' | sort -n | tail -n1
}

comfyui_busy() {
  # exit 0 = busy (queue non-empty), 1 = idle/unknown-as-not-busy
  local json
  json="$("${CURL_BIN}" -sf --max-time 5 "${COMFYUI_URL}/queue" 2>/dev/null)" || return 1
  [ -z "${json}" ] && return 1
  if command -v jq >/dev/null 2>&1; then
    local n
    n="$(printf '%s' "${json}" | jq '((.queue_running // []) + (.queue_pending // [])) | length' 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ] && return 0
    return 1
  fi
  # python3 fallback
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "${json}" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(1)
n=len(d.get("queue_running") or [])+len(d.get("queue_pending") or [])
sys.exit(0 if n>0 else 1)
' 2>/dev/null && return 0
  fi
  return 1
}

ssh_logins() {
  # count interactive login sessions (exclude the watchdog's own non-tty)
  who 2>/dev/null | grep -cE '\([0-9a-zA-Z._:-]+\)' || true
}

do_sync() {
  if [ ! -d "${OUTPUT_DIR}" ]; then
    log "sync: output dir ${OUTPUT_DIR} does not exist, skipping"
    return 0
  fi
  if ! command -v "${AWS_BIN}" >/dev/null 2>&1; then
    log "sync: aws CLI not found, skipping"
    return 1
  fi
  log "sync: s3://${S3_BUCKET}/${S3_OUTPUT_PREFIX} <- ${OUTPUT_DIR}"
  # shellcheck disable=SC2086  # intentional word-splitting: S3_SYNC_EXTRA_ARGS may hold several flags
  if ${AWS_BIN} s3 sync "${OUTPUT_DIR}" "s3://${S3_BUCKET}/${S3_OUTPUT_PREFIX}" ${S3_SYNC_EXTRA_ARGS}; then
    log "sync: ok"
    write_int_file "${LAST_SYNC_FILE}" "$(date +%s)"
    return 0
  fi
  log "sync: FAILED (will retry next run)"
  return 1
}

maybe_sync() { # force(0/1)
  local force="$1" now last elapsed need
  now="$(date +%s)"
  last="$(read_int_file "${LAST_SYNC_FILE}" 0)"
  need=$(( SYNC_INTERVAL_MIN * 60 ))
  elapsed=$(( now - last ))
  if [ "${force}" = "1" ] || [ "${elapsed}" -ge "${need}" ]; then
    do_sync || true
  else
    log "sync: skipped (last ${elapsed}s ago, cadence ${need}s)"
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  ensure_state
  # Serialise runs. If the lock cannot be created we still proceed (a missed
  # lock is preferable to skipping the check entirely).
  lock_ok=0
  if exec 9>"${LOCK_FILE}"; then lock_ok=1; fi
  if [ "${lock_ok}" = "1" ] && command -v flock >/dev/null 2>&1; then
    flock -n 9 || { log "another run in progress, exiting"; exit 0; }
  elif [ "${lock_ok}" = "0" ]; then
    log "warn: could not create lock ${LOCK_FILE}; continuing without lock"
  fi

  print_config

  # 1) GPU read — fail safe
  local util
  if ! util="$(gpu_util)"; then
    log "GPU read failed; not changing idle state and NOT shutting down (fail safe)"
    exit 2
  fi
  [ -n "${util}" ] || { log "GPU util empty; fail safe, exit"; exit 2; }

  local idle_samples
  idle_samples="$(read_int_file "${IDLE_FILE}" 0)"

  # 2) busy?
  local busy=0 reason=""
  if [ -f "${HOLD_FILE}" ]; then busy=1; reason="hold file present"
  elif [ "${util}" -ge "${GPU_UTIL_THRESHOLD}" ]; then busy=1; reason="gpu util ${util}%"
  elif comfyui_busy; then busy=1; reason="comfyui queue non-empty"
  elif [ "${COUNT_ACTIVE_SSH_AS_BUSY}" = "1" ] && [ "$(ssh_logins)" -gt 0 ]; then busy=1; reason="active login session"
  fi

  if [ "${busy}" = "1" ]; then
    if [ "${idle_samples}" != "0" ]; then
      log "busy (${reason}); resetting idle counter ${idle_samples}->0"
      write_int_file "${IDLE_FILE}" 0
    else
      log "busy (${reason}); idle counter stays 0"
    fi
  else
    idle_samples=$(( idle_samples + 1 ))
    write_int_file "${IDLE_FILE}" "${idle_samples}"
    log "idle: gpu=${util}% sample ${idle_samples}/${IDLE_SAMPLES_NEEDED} (~$(( idle_samples * CHECK_INTERVAL_MIN ))min)"
  fi

  # 3) hourly sync
  maybe_sync 0

  # 4) shutdown?
  if [ "${busy}" = "0" ] && [ "${idle_samples}" -ge "${IDLE_SAMPLES_NEEDED}" ]; then
    log "IDLE LIMIT reached (${idle_samples}/${IDLE_SAMPLES_NEEDED}); syncing then stopping machine"
    maybe_sync 1
    if [ "${DRY_RUN}" = "1" ]; then
      log "DRY_RUN=1: would run '${SUDO} ${SHUTDOWN_BIN} -h ${SHUTDOWN_DELAY}'"
      exit 0
    fi
    log "issuing: ${SUDO} ${SHUTDOWN_BIN} -h ${SHUTDOWN_DELAY}"
    ${SUDO} "${SHUTDOWN_BIN}" -h "${SHUTDOWN_DELAY}" || {
      log "shutdown command failed (rc=$?)"
      exit 1
    }
  fi
}

main "$@"
