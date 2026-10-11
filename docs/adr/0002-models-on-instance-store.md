# ADR 0002 - Model weights on instance-store NVMe, S3 as source of truth

**Status:** accepted

## Context
~21 GB of weights; the DLAMI leaves ~24 GB free on the root volume. g5.xlarge ships a
229 GB local NVMe that costs nothing extra but is wiped on every stop.

## Decision
S3 `models/` is the source of truth. A oneshot systemd unit re-syncs to NVMe on every
boot, gated by `RequiresMountsFor`, and `ComfyUI/models` is a symlink to it.

## Consequences
- Root EBS stays at 75 GB.
- ~3 minutes of sync on each start.
- A boot-ordering bug here can fill the root disk - mitigated in the unit and the script.
