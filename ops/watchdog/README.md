# ComfyUI watchdog (GPU idle → auto-shutdown, output → S3)

Cost backstop for the ComfyUI / Qwen-Image-Edit EC2 box (`i-0123456789abcdef0`,
g5.xlarge, us-east-1). 

It only ever *stops* the machine — it never starts it. Starting is always a deliberate operator action.

## Behaviour

Every 5 minutes (systemd timer), on the instance:

1. Read GPU utilization (`nvidia-smi`).
2. If the GPU has been idle (< 5%) for **45 consecutive minutes**, sync the
   output folder to S3 and then stop the machine (`shutdown -h now`).
3. Otherwise reset the idle counter. The counter is persisted, so a reboot or
   timer restart does not reset the 45-minute clock.
4. Sync `OUTPUT_DIR` → S3 **once an hour**, and always once right before a
   shutdown, so no generated image is lost.

### What keeps the box alive (safety guards)

- GPU utilization ≥ threshold.
- ComfyUI queue has a **running or pending** prompt (`/queue`).
- The **hold file** exists (`/var/lib/comfyui-watchdog/hold`).
- An interactive SSH login is present (configurable; avoids killing a session
  mid-work).
- `nvidia-smi` cannot be read → **fail safe**: no state change, no shutdown.

## Files

| File | Goes to |
|------|---------|
| `comfyui-watchdog.sh` | `/usr/local/bin/comfyui-watchdog.sh` |
| `comfyui-watchdog.env` | `/etc/default/comfyui-watchdog` |
| `comfyui-watchdog.service` | `/etc/systemd/system/` |
| `comfyui-watchdog.timer` | `/etc/systemd/system/` |
| `install.sh` | run once on the instance (`sudo bash install.sh`) |
| `test-watchdog.sh` | dev only — offline logic tests |

## Install (on the instance, as root)

```bash
sudo bash install.sh
```

Idempotent; an existing `/etc/default/comfyui-watchdog` is never overwritten.
The installer enables the timer and runs one tick. It lives on the root EBS
volume, so it survives stop/start.

> If the launch flow re-runs cloud-init `user-data` on every boot, add these
> files + `install.sh` to that user-data instead, so a rebuilt root is covered.

## Prerequisites

1. **Instance-Initiated Shutdown Behavior = `stop`** (the EC2 default). Verify:
   `aws ec2 describe-instance-attribute --instance-id i-0123456789abcdef0 --attribute instanceInitiatedShutdownBehavior`
   If it says `terminate`, change it to `stop` first.
2. **S3 write permission** for the instance (IAM instance profile or
   credentials) on `s3://REPLACE_ME_BUCKET/outputs/`. Without it the sync
   logs a warning and retries; shutdown still works.
3. `OUTPUT_DIR` matches the real ComfyUI output folder
   (default `/home/ubuntu/ComfyUI/output`).

## Config

Edit `/etc/default/comfyui-watchdog` (all values overridable), then
`sudo systemctl restart comfyui-watchdog.timer`. Common knobs:

- `IDLE_MINUTES` (default 45), `GPU_UTIL_THRESHOLD` (default 5).
- `S3_BUCKET` / `S3_OUTPUT_PREFIX`, `OUTPUT_DIR`, `SYNC_INTERVAL_MIN` (60).
- `COUNT_ACTIVE_SSH_AS_BUSY` (1) — set 0 for strictest cost control.
- `DRY_RUN` (0) — **set 1 for the first deployment** to watch it decide
  without actually shutting down.

## Operations

```bash
journalctl -u comfyui-watchdog.service -f     # live log
sudo /usr/local/bin/comfyui-watchdog.sh       # run one tick by hand
sudo touch /var/lib/comfyui-watchdog/hold     # pause auto-shutdown
sudo rm -f  /var/lib/comfyui-watchdog/hold    # resume
systemctl list-timers comfyui-watchdog.timer  # next run
```

## Tests

```bash
bash test-watchdog.sh     # 18 checks, mocks nvidia-smi/curl/who/aws/shutdown
```
