# Budget guardrails

Promotional credits are applied automatically and first. That makes billing data
misleading in one specific way:

| Budget type | `IncludeCredit` | What it reads while credit remains | Fires when |
|---|---|---|---|
| NET | `true` | $0.00 | only after the card is already paying |
| GROSS | `false` | real resource cost | real usage crosses the threshold |

A NET budget with an ACTUAL action at $20 would only stop the node after $20 had
already been charged to the card - the opposite of a safety net. So:

1. **GROSS budget, ACTUAL 50/80%, FORECAST 100%** -> "a node was forgotten running".
2. **NET budget at $1** -> "the credit has run out". Any NET charge means stop now.
3. **On-instance watchdog** -> the only control that acts in minutes, not hours.
   Billing data lags up to ~24h, so budgets are alarms, not brakes.
4. **AWS has no hard spend cap.** Zero out-of-pocket is only guaranteed by having
   zero running resources - hence `ops/teardown`.
