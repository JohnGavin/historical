# Rule: Snapshot Test Policy (historical project)

## Global rule reference

The authoritative policy lives at
`~/docs_gh/llm/.claude/rules/snapshot-tests-mandatory.md`.
This file adds project-specific examples and the per-file audit table.
When the two conflict, the global rule takes precedence.

## When This Applies

Every test file added or modified in:

- `packages/historicaldata/tests/testthat/test-*.R`
- `tests/testthat/test-*.R`

## Decision Matrix

| Test type | Snapshot? | testthat function | Why |
|-----------|-----------|-------------------|-----|
| Pure algorithmic unit tests (toy inputs, hand-derived expected) | NO — keep `expect_equal` | — | Self-documenting, no fragility |
| Error / warning messages from `cli_abort` / `cli_warn` | **YES** | `expect_snapshot(error = TRUE, fn())` | Wording drift is meaningful; catches rename of `.arg` / `.field` |
| CLI informational messages (`cli_inform`) | **YES** | `expect_snapshot(fn_with_message())` | User-facing strings should be reviewed on change |
| Caption strings (assembled by `paste0`) | **YES** | `expect_snapshot(caption)` | Format/wording drift is detectable without hand-derivation |
| Function signatures (API stability) | **YES** | `expect_snapshot(args(fn))` | Catches param renames/additions/removals |
| Real-data target outputs (`tar_read(...)`) | **YES** | `expect_snapshot_value(result, style = "deparse")` | Catches schema drift; no hand-derivation possible |
| Numerical output with tolerance | Mixed | `expect_equal(tolerance=)` for gist + `expect_snapshot_value(style="deparse", tolerance=)` for structure | Both signals matter |
| Plot artefacts / Quarto HTML | **YES** | `expect_snapshot_file()` | Visual/structural regression |

## Minimum ratios (from global rule)

| test_that blocks in file | Minimum snapshots |
|--------------------------|-------------------|
| 1–3 | At least 1 |
| 4–8 | At least 2 |
| 9+ | At least 30% |

## Concrete patterns used in this project

### Error message snapshots (see test-drif-selection.R)

```r
test_that("non-data-frame predictions throws informative cli_abort", {
  expect_snapshot(
    error = TRUE,
    hd_drif_select_topn("not_a_df", make_params(), 2L)
  )
})
```

### Caption string snapshot (see tests/testthat/test-drif.R)

```r
test_that("drif_multiverse_caption format is stable", {
  caption <- build_caption(toy_mv)
  expect_snapshot(cat(caption))
})
```

### Function signature stability (see test-hd_strat_keff_vertox.R)

```r
test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_drif_select_topn))
})
```

## DO NOT use snapshots for

- Tests where the expected value is easily hand-derived and hand-verified
  (e.g., `expect_equal(nrow(result), 4L)` is more readable than a snapshot)
- Tests with random / timestamp-dependent output unless `transform =` is used
  to strip non-deterministic parts

## Commit rule

Snapshot files (`_snaps/*.md`) MUST be committed alongside the test file
changes that produce them. They are part of the test suite, not generated
artefacts.

## Per-file audit (as of 2026-05-31, issue #340)

### packages/historicaldata/tests/testthat/

| File | Total assertions | Snap | Non-snap | Verdict |
|------|-----------------|------|----------|---------|
| test-add-signal.R | 30 | 0 | 30 | algorithmic |
| test-alphavantage.R | 13 | 0 | 13 | algorithmic |
| test-column-naming.R | 11 | 0 | 11 | algorithmic |
| test-commodities-mean-reversion.R | 16 | 0 | 16 | algorithmic |
| test-cpcv.R | 34 | 0 | 34 | algorithmic |
| test-drif-selection.R | 22 | 0 | 22 | mixed — error msgs snapshottable |
| test-ecb.R | 15 | 0 | 15 | algorithmic |
| test-guardian.R | 11 | 0 | 11 | algorithmic |
| test-hd_strat_keff_vertox.R | 16 | 5 | 11 | compliant |
| test-jst.R | 27 | 0 | 27 | algorithmic |
| test-mom-prepeak-ff-join.R | 3 | 0 | 3 | algorithmic |
| test-mom-prepeak-metrics.R | 38 | 1 | 37 | mixed — more snapshots needed |
| test-mom-prepeak-portfolio.R | 19 | 1 | 18 | mixed — more snapshots needed |
| test-mom-prepeak-random-peak.R | 4 | 0 | 4 | algorithmic |
| test-mom-prepeak.R | 24 | 4 | 20 | compliant |
| test-olmar.R | 33 | 0 | 33 | algorithmic |
| test-pit-guard.R | 7 | 0 | 7 | algorithmic |
| test-query.R | 30 | 4 | 26 | compliant |
| test-registry-artefacts.R | 19 | 1 | 18 | mixed — more snapshots needed |
| test-registry-db.R | 12 | 0 | 12 | algorithmic |
| test-registry-metrics.R | 16 | 0 | 16 | algorithmic |
| test-registry-upsert.R | 11 | 0 | 11 | algorithmic |
| test-registry-writers.R | 12 | 0 | 12 | algorithmic |
| test-registry.R | 14 | 1 | 13 | mixed — more snapshots needed |
| test-research_log.R | 36 | 0 | 36 | algorithmic |
| test-risk-metrics.R | 27 | 0 | 27 | algorithmic |
| test-survivorship-bias.R | 8 | 0 | 8 | algorithmic |
| test-topological-risk-parity.R | 28 | 0 | 28 | algorithmic |
| test-vintages.R | 3 | 0 | 3 | algorithmic |
| test-wf-correlation.R | 34 | 0 | 34 | algorithmic |

### tests/testthat/ (root-level, targets pipeline helpers)

| File | Total assertions | Snap | Non-snap | Verdict |
|------|-----------------|------|----------|---------|
| test-cpcv-integration.R | 16 | 0 | 16 | algorithmic |
| test-drif.R | 17 | 0 | 17 | mixed — caption string snapshottable |
| test-momentum-decomposition.R | 12 | 3 | 9 | compliant |
| test-pairwise-alignment.R | 27 | 3 | 24 | compliant |
| test-plan-factormax.R | 5 | 0 | 5 | algorithmic |
| test-plan-portfolio-opt.R | 8 | 0 | 8 | algorithmic |
| test-qa-look-ahead-bias.R | 17 | 0 | 17 | algorithmic |
| test-qa-summary-deps.R | 5 | 0 | 5 | algorithmic |
| test-stock-backtest.R | 21 | 0 | 21 | mixed — warning msgs snapshottable |
| test-utils_align.R | 33 | 4 | 29 | compliant |
| test-utils_dates.R | 11 | 2 | 9 | compliant |
| test-utils_rolling.R | 16 | 3 | 13 | compliant |
| test-utils_validation.R | 49 | 3 | 46 | mixed — more snapshots needed |
| test-utils-metrics.R | 27 | 0 | 27 | algorithmic |
| test-vignette-utils.R | 32 | 0 | 32 | algorithmic |
| test-volatility-spike-na-alignment.R | 5 | 0 | 5 | algorithmic |

## Related

- `~/docs_gh/llm/.claude/rules/snapshot-tests-mandatory.md` — global rule
- `packages/historicaldata/tests/testthat/_snaps/` — existing snapshots
- `tests/testthat/_snaps/` — root-level snapshots
- Issue #340 — origin of this policy
