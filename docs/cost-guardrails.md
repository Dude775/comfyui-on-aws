# Cost guardrails

AWS credits are consumed automatically and there is **no native "stop when the credit runs
out"** - once spent or expired, usage bills the card. Alerts alone cannot prevent this.

- **IncludeCredit - net vs gross.** With `IncludeCredit=true` a budget reports *net* spend, so it
  sits at $0 while credit covers usage and an attached action fires only after real money is
  charged. Guards belong on a **gross** budget (`IncludeCredit=false`); a net budget is only a
  last-line "any real charge" tripwire.
- **Alerts are not enforcement.** Notifications just email. Only an action stops anything - and
  cost data lags hours, so budgets are cushions, not real-time stops.
- **Four layers.**
  1. *State* - read the credit balance and expiry before a session.
  2. *Visibility* - ACTUAL and FORECASTED alerts on the gross budget.
  3. *Enforcement* - the on-instance watchdog (minutes) plus a budget action (hours).
  4. *Payment isolation* - the only hard zero-out-of-pocket guarantee is having nothing running,
     which is what `ops/teardown` is for.

## Real numbers from this project

| Item | Cost |
|---|---|
| g5.xlarge on-demand | ~$1.0 / hour |
| One evening session (~3 h) | ~$2.9 |
| Root EBS 75 GB gp3 while **stopped** | ~$0.15-0.20 / day |
| S3, ~21 GB of models | ~$0.50 / month |
| Fixed idle floor (stopped node + bucket) | ~$6.5 / month |

The idle floor is why "stopped" is not "free", and why the project ends with a full
teardown rather than a parked instance.
