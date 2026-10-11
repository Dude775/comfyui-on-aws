#!/usr/bin/env bash
# cost-report.sh - month-to-date GROSS vs NET spend, per service.
# GROSS = what the resources cost. NET = what hits the card after credits.
# If NET > 0 the credit is gone and the card is paying - stop everything.
set -euo pipefail

START="${START:-$(date -u +%Y-%m-01)}"
END="${END:-$(date -u -d tomorrow +%Y-%m-%d)}"

echo "== period $START .. $END"
aws ce get-cost-and-usage --time-period "Start=$START,End=$END" --granularity MONTHLY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=RECORD_TYPE \
  --query 'ResultsByTime[0].Groups[].{type:Keys[0],usd:Metrics.UnblendedCost.Amount}' --output table

echo "== gross usage by service"
aws ce get-cost-and-usage --time-period "Start=$START,End=$END" --granularity MONTHLY \
  --metrics UnblendedCost --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[?Metrics.UnblendedCost.Amount>`0.01`].{service:Keys[0],usd:Metrics.UnblendedCost.Amount}' \
  --output table
