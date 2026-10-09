# ADR 0004 - On-instance watchdog as the primary brake

**Status:** accepted

## Context
Billing data lags up to ~24 hours. A forgotten g5.xlarge burns ~$24/day.

## Decision
A systemd timer on the node checks GPU utilisation every 5 minutes and stops the
instance after 45 consecutive idle minutes. It is blocked by a non-empty ComfyUI queue,
a hold file, an interactive session, or an unreadable `nvidia-smi` (fail safe).
Budgets remain as alarms.

## Consequences
Worst-case waste drops from "until someone notices" to ~50 minutes. The watchdog only
stops - it can never start a node.
