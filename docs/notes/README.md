# Audit and findings notes

Point-in-time notes. Each was written on the date in its header, and its figures
may be stale. Re-verify against current targets before relying on any number.

## In this folder

| Note | What it is |
|------|------------|
| [`unit-vocab-census-668.md`](unit-vocab-census-668.md) | Census of where metric units and vocabulary are normalised (issue #668, phase 1). |
| [`415-summary.md`](415-summary.md) | Audit of Alpha Architect factor strategies against our strategies (issue #415). |

## Elsewhere, left in place on purpose

These are still referenced by their current path from code comments, scripts,
tests or a rule, so moving them would leave dangling pointers (and `R/` is out
of scope for this tidy). Move them together with those references in a later change.

| Note | Referenced from |
|------|-----------------|
| [`../inner-join-audit-657.md`](../inner-join-audit-657.md) | `R/`, `tests/testthat/` |
| [`../ticker-join-audit-865.md`](../ticker-join-audit-865.md) | `scripts/fetch_fundamentals_edgar.R` |
| [`../olmar-universe-findings-976-977.md`](../olmar-universe-findings-976-977.md) | `R/plan_olmar.R`, `scripts/seed_olmar_*.R` |
| [`../../audits/`](../../audits/) (`cost-assumptions-*`, `inner_join_audit_*`, `snapshot_ratio_*`) | `R/`, `.claude/rules/snapshot-test-policy.md`, `scripts/audit_snapshot_ratio.R` |
