# ADR 0001 - On-demand GPU, spot as an option

**Status:** accepted

## Context
The first design used a one-time spot request with `shutdown == terminate` - cheapest,
and billing provably stops when the box stops. In practice spot capacity for G-family
instances was unavailable across the region for days.

## Decision
`aws_instance` with a `purchase_option` switch. Default `on-demand`, shutdown behaviour
`stop`. Spot stays available through `instance_market_options`.

## Consequences
- Sessions start reliably.
- `stop` keeps the EBS disk, so ComfyUI does not reinstall on each start - but an idle
  floor of ~$6.5/month exists until teardown.
- The watchdog becomes the primary cost control, since the instance is no longer
  self-destroying.
