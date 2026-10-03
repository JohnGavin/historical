---
paths:
  - "R/**/*.R"
  - "packages/*/R/**/*.R"
  - "scripts/**/*.R"
  - "docs/_targets.R"
---

# Details: Fail Loud, Never Null — origin incidents and worked cases

Companion to [`fail-loud-not-null`](fail-loud-not-null.md). That file holds every
normative requirement; this one holds the evidence behind them. Nothing here
adds or relaxes a requirement.

## Source

Generalised from the same defect recurring three times in two days (2026-08-03 → 2026-08-05), each time in a different vocabulary, each time discovered by accident rather than by a gate:

| Issue | The unexpected value | What it was silently coerced to | How it surfaced |
|---|---|---|---|
| [#637](https://github.com/JohnGavin/historical/issues/637) | a metric in percent where fractions were assumed | a number 100× wrong, ranked against its peers as if comparable | a reader noticed a vol of 6.82 next to a vol of 0.18 |
| [#643](https://github.com/JohnGavin/historical/issues/643) | period label `"Full"` where `"Full Period"` was assumed | a dropped row — the strategy vanished from the ranking | someone counted the leaderboard rows |
| [#640](https://github.com/JohnGavin/historical/issues/640) | absent `metric_unit` | `NA_character_`, written to the registry as a bare unitless number | found while fixing #637, not by any check |
| [#641](https://github.com/JohnGavin/historical/issues/641) | a month missing from one of four constituents | the month deleted from the portfolio for **all** constituents | someone asked why the heatmap had no March |

Earlier instances of the identical shape, recorded before it was named: `as.logical("1")` returning `NA` and silently disabling `VIGNETTE_STRICT`; a `Date`/`POSIXct` mismatch making `full_join` produce zero matches; NAs cascading through `roll_mean`/`roll_sd`.

## Why the defect is expensive

Null-ish states are indistinguishable from *legitimately absent* data. The failure produces output that looks exactly like a correct answer to a smaller question. Nobody sees a stack trace. The number just quietly becomes wrong, gets published, and is then used as an input somewhere else — #641's truncated PSO Optimal vol was about to be adopted as the book-level risk anchor in [#635](https://github.com/JohnGavin/historical/issues/635).

The three carriers seen so far are **units**, **vocabularies**, and **factor levels / join keys**. Expect a fourth.

## Pattern 2 cautionary case

#640 is the cautionary case for validating on both sides: `bt.metric` correctly *recorded* `metric_unit` but validated it on neither side, so the column was decoration.

## Pattern 4 — most common instance

A silent `return(NULL)` inside an `lapply()` is the single most common instance of this in `R/` — it removes a whole period from a series and leaves no trace.

## Pattern 5 — guard placement evidence

| instance | guard was correct, but ran only… | so what escaped |
|---|---|---|
| #693/#694 | when the extractor found a `tibble()` | a refactor to `data.frame()` returned `character(0)`, so `required` was empty and the coverage check passed vacuously |
| #710 | in `--data-staleness` mode, which needs a store | a malformed `HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS` is silently ignored in default mode *and in the weekly CI job* |

Both were written to satisfy the rule, by someone who had read it, and both left a hole one level up. That is the evidence that "add a guard" is not sufficient guidance on its own — placement is a separate decision from existence, and it is the one that keeps going wrong.

### The adjacent failure — the guard fires and nobody sees it

#691 is often cited alongside the two above and it is not the same thing: `hd_metric_record()`'s unit guard was correctly placed and *did* fire, erroring eleven registry writers. What failed is that `error = "continue"` in `docs/_targets.R` made `tar_make()` exit 0 anyway, so the guard's output was invisible for four commits.

Keep the two apart, because the fixes differ. A mis-placed guard is fixed by moving it; an unseen guard is fixed by making its output reachable — which is why `scripts/build.sh` and `scripts/check_pipeline_errors.R` exist. Both defeat the same intent, so when a guard fails to protect you, ask **which** of the two it was before reaching for a fix.

## Pattern 6 — gates in this family so far

| Gate | Guards | Introduced |
|---|---|---|
| S9 `qa_leaderboard_metric_ranges` | units — cagr/vol/max_dd within fractional range | #637 |
| S10 `qa_leaderboard_period_vocab` | vocabulary — canonical `period` labels | #643 |

The gap the rule closed: **#640 (registry units) and #641 (join-key coverage) had no gate**, which is exactly why they survived the session that fixed the first two.

## Self-test — why the second question exists

#694 and #710 both passed the first question and failed the second, in code written by people who had read the rule.

## Related issues

- [#637](https://github.com/JohnGavin/historical/issues/637), [#640](https://github.com/JohnGavin/historical/issues/640), [#641](https://github.com/JohnGavin/historical/issues/641), [#643](https://github.com/JohnGavin/historical/issues/643) — the four instances that motivated the rule
- [#693](https://github.com/JohnGavin/historical/issues/693), [#710](https://github.com/JohnGavin/historical/issues/710) — the two instances that motivated Required Pattern 5 (guard placement). Both post-date the rule and were written in compliance with it.
- [#691](https://github.com/JohnGavin/historical/issues/691) — the adjacent failure: a correctly-placed guard whose output was invisible because `error = "continue"` let `tar_make()` exit 0. Fixed by #693's `scripts/build.sh`, not by moving any guard.
