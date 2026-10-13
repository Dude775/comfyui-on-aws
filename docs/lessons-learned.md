# Lessons learned

Real failures hit while building this, in the order they happened. Each one changed
the code or the process.

## 1. Free Plan blocks GPU instances, even with approved quotas

**Symptom:** console refused every G-family type: *"This instance type is not eligible
under the Free Plan"* - after both vCPU quota requests (spot and on-demand G/VT) had
been approved at 8 vCPU.
**Cause:** the account was on the AWS Free Plan, which hard-blocks credit-draining
services regardless of quota.
**Fix:** upgrade to a paid plan. Promotional credits carry over.
**Lesson:** quota approval is necessary, not sufficient. Check the account plan first.

## 2. Wrong quota code in automation

**Symptom:** `NoSuchResourceException` from `service-quotas get-service-quota`.
**Cause:** a mistyped quota code. The on-demand G/VT quota is `L-DB2E81BA`; spot is
`L-3819A6DF`.
**Fix:** `ops/cost/preflight.sh` checks the real code before any apply.

## 3. No spot capacity

**Symptom:** `There is no Spot capacity available that matches your request` across
every AZ in the region, repeatedly.
**Fix:** `purchase_option` variable - spot when available, on-demand otherwise. On-demand
also allows `stop` instead of `terminate`, so the EBS disk keeps outputs.

## 4. Dead clone URL in user-data

**Symptom:** bootstrap died at the GGUF loader step.
**Cause:** the custom-node repo was referenced under the wrong GitHub org.
**Fix:** `city96/ComfyUI-GGUF` is the canonical repo. Pinned in `userdata.sh.tpl`.

## 5. Root disk too small for the models

**Symptom:** only ~24 GB free on the root EBS after the AMI.
**Fix:** models live on the instance-store NVMe (229 GB, free with the instance) and
`ComfyUI/models` is a symlink to it. Root EBS stays at 75 GB.

## 6. NVMe mount race filled the root disk to 100%

**Symptom:** after a stop/start the ComfyUI service crash-looped; `df` showed root at 100%.
**Cause:** the model sync ran before the DLAMI had mounted `/opt/dlami/nvme`. It wrote
~13 GB of partial files into the empty mount-point directory - on the root EBS.
**Fix:** `comfy-models.service` has `RequiresMountsFor=/opt/dlami/nvme`, and
`sync-models.sh` refuses to run unless `mountpoint -q` passes and enough space is free.
**Lesson:** "the directory exists" is not "the disk is mounted".

## 7. Sampler mode returned copies of the input

**Symptom:** edits came back as near-copies of the input with burnt colours; instructions
were ignored. An earlier sampler choice (`dpm_2/karras`) produced pure noise.
**Cause:** `ModelSamplingAuraFlow` was set to `sampling=img_to_img_velocity`.
**Fix:** controlled A/B on a fixed seed: `euler / simple / flow` is the only combination
that applied the edit with natural colour. CI now asserts the recipe on the committed
workflow (`tests/test_graph.py`).

## 8. Edit graph ignored the source image

**Symptom:** faces and framing drifted between runs.
**Cause:** the sampler's `latent_image` came from `EmptyLatentImage`, so the photo was
only a text-encoder hint, not the starting latent.
**Fix:** `LoadImage -> VAEEncode -> latent_image`, denoise 0.75. Regression test:
`test_edit_graph_encodes_source_image`.

## 9. The home IP moved

**Symptom:** UI suddenly unreachable; SSH timed out.
**Cause:** residential IP changed; the SG allowed only the old `/32`.
**Fix:** `allowed_cidrs` is a list, and `preflight.sh` checks the current IP against the
SG before starting the node.

## 10. Watchdog bugs caught by its own tests

- `exec 9>"$LOCK" 2>/dev/null` redirected stderr for the **whole script**, so the logger
  went silent. Redirect only the command that needs it.
- `: "${SUDO:=sudo}"` treats an empty value as unset, so running as root still prefixed
  `sudo`. When empty is a legitimate value, test with `${VAR+x}`.
- The script documented loading `/etc/default/comfyui-watchdog` but never did. systemd's
  `EnvironmentFile` hid the gap; a manual "dry run" would have used `DRY_RUN=0`.

## 11. Budgets that could never fire

**Symptom:** a $100 budget reported `$0.00 actual` while the node had clearly run.
**Cause:** `IncludeCredit=true` - the budget measured **net** spend, which is $0 while
credits cover usage. An action on it would fire only after the card had been charged.
**Fix:** guard on a **gross** budget; keep a $1 net budget as the "credit ran out"
tripwire. See [cost-guardrails.md](cost-guardrails.md).
