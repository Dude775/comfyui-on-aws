#!/usr/bin/env bash
#
# test-watchdog.sh — offline logic tests for comfyui-watchdog.sh.
# Mocks nvidia-smi / curl / who / aws / shutdown so no real hardware,
# network, or cost is involved. Run:  bash test-watchdog.sh
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG="${SCRIPT_DIR}/comfyui-watchdog.sh"
PASS=0
FAIL=0

TMP="$(mktemp -d)"
MOCK="${TMP}/bin"
mkdir -p "${MOCK}"

# --- mocks ---------------------------------------------------------------
cat > "${MOCK}/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
if [ -f "$MOCK_DIR/gpu_fail" ]; then exit 1; fi
cat "$MOCK_DIR/gpu_util"
EOF

cat > "${MOCK}/curl" <<'EOF'
#!/usr/bin/env bash
[ -f "$MOCK_DIR/comfy_busy" ] && echo '{"queue_running":[{"x":1}],"queue_pending":[]}' || echo '{"queue_running":[],"queue_pending":[]}'
EOF

cat > "${MOCK}/who" <<'EOF'
#!/usr/bin/env bash
[ -f "$MOCK_DIR/ssh" ] && echo 'ubuntu   pts/0        2026-10-10 23:00 (203.0.113.4)' || true
EOF

cat > "${MOCK}/aws" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_DIR/aws_calls"
exit 0
EOF

cat > "${MOCK}/shutdown" <<'EOF'
#!/usr/bin/env bash
echo "shutdown $*" >> "$MOCK_DIR/shutdown_called"
exit 0
EOF
chmod +x "${MOCK}"/*

export MOCK_DIR="${MOCK}"      # mocks read this
export PATH="${MOCK}:${PATH}"

run() { # state_setup ...
  rm -rf "${TMP}/state" "${TMP}/output"
  mkdir -p "${TMP}/state" "${TMP}/output"
  rm -f "${MOCK}"/gpu_fail "${MOCK}"/comfy_busy "${MOCK}"/ssh "${MOCK}"/shutdown_called "${MOCK}"/aws_calls
  export STATE_DIR="${TMP}/state"
  export OUTPUT_DIR="${TMP}/output"
  export SUDO=""
  export SHUTDOWN_BIN="${MOCK}/shutdown"
  export NVIDIA_SMI="${MOCK}/nvidia-smi"
  export AWS_BIN="${MOCK}/aws"
  export CURL_BIN="${MOCK}/curl"
  export DRY_RUN=0
}

check() { # desc condition
  if eval "$2"; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; FAIL=$((FAIL+1)); fi
}

echo "== test 1: busy GPU resets counter, no shutdown =="
run
echo 8 > "${TMP}/state/idle_samples"
echo 80 > "${MOCK}/gpu_util"
bash "${WATCHDOG}" >/dev/null 2>&1
check "idle counter reset to 0" "[ \"\$(cat ${TMP}/state/idle_samples)\" = 0 ]"
check "no shutdown" "[ ! -f ${MOCK}/shutdown_called ]"

echo "== test 2: single idle sample increments, no shutdown =="
run
echo 0 > "${MOCK}/gpu_util"
bash "${WATCHDOG}" >/dev/null 2>&1
check "counter is 1" "[ \"\$(cat ${TMP}/state/idle_samples)\" = 1 ]"
check "no shutdown" "[ ! -f ${MOCK}/shutdown_called ]"

echo "== test 3: 9th idle sample -> sync then shutdown =="
run
echo 8 > "${TMP}/state/idle_samples"
echo 0 > "${MOCK}/gpu_util"
bash "${WATCHDOG}" >/dev/null 2>&1
check "shutdown called" "[ -f ${MOCK}/shutdown_called ]"
check "forced sync before shutdown" "grep -q 's3 sync' ${MOCK}/aws_calls"

echo "== test 4: non-empty ComfyUI queue blocks shutdown =="
run
echo 8 > "${TMP}/state/idle_samples"
echo 0 > "${MOCK}/gpu_util"
touch "${MOCK}/comfy_busy"
bash "${WATCHDOG}" >/dev/null 2>&1
check "no shutdown" "[ ! -f ${MOCK}/shutdown_called ]"
check "counter reset" "[ \"\$(cat ${TMP}/state/idle_samples)\" = 0 ]"

echo "== test 5: hold file blocks shutdown =="
run
echo 8 > "${TMP}/state/idle_samples"
echo 0 > "${MOCK}/gpu_util"
touch "${TMP}/state/hold"
bash "${WATCHDOG}" >/dev/null 2>&1
check "no shutdown" "[ ! -f ${MOCK}/shutdown_called ]"

echo "== test 6: active login blocks shutdown =="
run
echo 8 > "${TMP}/state/idle_samples"
echo 0 > "${MOCK}/gpu_util"
touch "${MOCK}/ssh"
bash "${WATCHDOG}" >/dev/null 2>&1
check "no shutdown" "[ ! -f ${MOCK}/shutdown_called ]"

echo "== test 7: nvidia-smi failure is fail-safe (no shutdown, exit 2) =="
run
echo 8 > "${TMP}/state/idle_samples"
touch "${MOCK}/gpu_fail"
bash "${WATCHDOG}" >/dev/null 2>&1
rc=$?
check "exit code 2" "[ $rc = 2 ]"
check "no shutdown" "[ ! -f ${MOCK}/shutdown_called ]"
check "counter untouched" "[ \"\$(cat ${TMP}/state/idle_samples)\" = 8 ]"

echo "== test 8: sync skipped within cadence, runs after =="
run
echo 0 > "${MOCK}/gpu_util"
date +%s > "${TMP}/state/last_sync_epoch"
bash "${WATCHDOG}" >/dev/null 2>&1
check "no sync within cadence" "[ ! -f ${MOCK}/aws_calls ]"
echo $(( $(date +%s) - 7200 )) > "${TMP}/state/last_sync_epoch"
bash "${WATCHDOG}" >/dev/null 2>&1
check "sync after cadence elapsed" "grep -q 's3 sync' ${MOCK}/aws_calls"

echo "== test 9: DRY_RUN logs but does not shut down =="
run
echo 8 > "${TMP}/state/idle_samples"
echo 0 > "${MOCK}/gpu_util"
DRY_RUN=1 bash "${WATCHDOG}" >/dev/null 2>&1
check "no shutdown under DRY_RUN" "[ ! -f ${MOCK}/shutdown_called ]"

echo "== test 10: config file is sourced; launch env wins over it =="
run
printf 'GPU_UTIL_THRESHOLD=9999\nIDLE_MINUTES=45\n' > "${TMP}/wd.env"
echo 0 > "${MOCK}/gpu_util"
ENV_FILE="${TMP}/wd.env" IDLE_MINUTES=7 bash "${WATCHDOG}" >"${TMP}/out.log" 2>&1
check "config file value applied (threshold=9999)" "grep -q 'threshold=9999%' ${TMP}/out.log"
check "launch env overrides file (idle_min=7)" "grep -q 'idle_min=7 ' ${TMP}/out.log"

echo
echo "RESULT: ${PASS} passed, ${FAIL} failed"
rm -rf "${TMP}"
[ "${FAIL}" -eq 0 ]
