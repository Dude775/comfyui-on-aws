# ADR 0003 - Prompts and images never cross the infrastructure boundary

**Status:** accepted

## Context
The workload is personal creative content. Infra automation, CI, and anyone helping
operate the account should not need to see it.

## Decision
- Prompts, exported graphs and images are git-ignored and stay on the operator laptop.
- Only a placeholder example graph is committed, and CI lints its *structure*, never content.
- The pipeline CLI has `--quiet` to avoid echoing prompt text into terminals or logs.
- The S3 `outputs/` prefix expires after 30 days.

## Consequences
Infra changes can be reviewed and run by people who never see the content. The cost is
that the real workflow must be re-exported locally after graph edits.
