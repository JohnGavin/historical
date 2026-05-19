# Current Work (Session 2026-05-18→19 — Nix segfault chain + roborev U-sweep + #208 narrative, ENDED)

**Last updated:** session end after PR #225 merge
**Previous sessions:** 2026-05-17 (roborev cluster sweep), 2026-05-16 (Opus marathon)

## Final state

`main` synced through `d011959` (PR #225 squash-merge). Working tree clean except for `inst/extdata/results/results_2026-05-18.parquet` (untracked pipeline output following the tracked pattern). 0 commits ahead of origin.

## Session totals

- **9 PRs merged**: #212, #214, #218, #219, #220, #221, #222, #223, #225
- **4 issues filed**: #210 (PR-U tracking), #211 (Rcpp ABI segfault — closed by #219), #224 (15 pre-existing pipeline errors), cross-comment on #208
- **98 roborev verdicts closed** (24 B1 + 47 B2 + 27 PR-U1..U5)
- **Full `tar_make()` completed**: 352/502 targets succeed, 22m 57s wall
- **Critical empirical finding surfaced**: Validation Sharpe -0.84 (every strategy loses money OOS) — drove the #208 narrative rewrite

## Key technical work

### The PR #206 dispatch trap (closed by #212)
`calc_backtest_metrics` collision: new vector-style function had same name as df-style function in `plan_stock_backtest.R:348`. Dispatch picked wrong variant → `nrow(numeric_vector) = NULL` → `if (NULL < 12)` error. Plus `R/utils_metrics.R` was never sourced. Fix: rename to `annualise_returns` + add source line.

### The Nix segfault chain (closed by #218 + #219)
- `*** caught segfault *** in dyn.load` on `zak_signal_percentile` — R_LIBS_SITE inherited from outer shell pointed to ABI-incompatible paths.
- `#218`: 24-line closure-rebuild shellHook (per `nix-nested-shell-isolation` rule) + `default.post.sh` idempotent re-application script + `slider` in tproject.toml.
- `#219`: added `RcppRoll` (the actual missing dep), removed 19-line glob hack from `docs/_targets.R` AND duplicate in `R/plan_qa_vignette.R` that re-introduced the bad paths.
- After fix: `zak_signal_percentile` 169ms, full pipeline 22m 57s.

### Roborev U-sweep (PR-U1..U5)
- `#214` (U1) leaderboard `opt_vol` + factormax determinism + avoid_worst as.Date() + vintages silent tryCatch
- `#220` (U3) XSS innerHTML + 33 target=_blank rel + VIGNETTE_STRICT footgun
- `#221` (U4) Python `0.0 or X = X` bug → `first_present(d, *keys)` + dead rename
- `#222` (U2) qa_summary explicit metric deps + duplicated glob removal
- `#223` (U5) stale prose cleanup

### #208 narrative rewrite (PR #225)
Sonnet fixer in worktree rewrote 9 sites across stock-backtest.qmd + drif.qmd. Reversed: "best OOS Sharpe (0.79)" → -1.51. Added Validation-period callout boxes. Length-zero-safe Validation slices. Hardcoded vol/DD/CAGR replaced with `safe_tar_read` inline R. Quarto render PASS both files.

## Carried forward to next session

### High priority (smallest first)
- **#224 PR-V1 patchwork dep** — add to tproject.toml + flake.nix; unblocks 1 vig_* target. Smallest.
- **#224 PR-V2** — `vig_eq_vol` log-of-negative; needs `pmax(x, eps)` or filter.
- **#210 PR-U6** — causal-diagrams.js bindFunctions + sample_data.R @param. Small docs follow-up.
- **#224 PR-V3** — 4 `vig_*` targets need stingy duckplyr / explicit collect().
- **#224 PR-V4** — 3 `crypto_bt_*` schema drift (ticker col join).
- **#224 PR-V5** — `port_monthly_returns`.

### Medium priority (carry-forward from prior sessions)
- `#142` EUR Phase 1
- `#200` OLMAR-1222 Phase 1
- `#192` Kinlay agentic-workflows infrastructure pillars (PIT wrapper / research-log DB / 4-role agents / critic / human-gate)
- `#194` AlphaVantage Phase 0 + alphavantager wrapper test
- `#160` PR 3+4
- `#171` Alpaca scrape
- `#170` Macrosynergy
- `#168` IBKR Phase 2

### Verification debt
- **T7 cluster D dark-mode contrast** — needs Pages deploy + live URL (check_dark_contrast.sh doesn't accept file://). Run after next Pages deploy.
- **MIDD.L #644** — group still has live references at `groups.R:65,74` beyond PR #198's fix. Reopen.

## Pipeline state

- 352/502 targets succeed; 15 errors pre-existing and tracked in #224
- Latest leaderboard Sharpes (post-rebuild): Training 0.06 / Testing 0.06 / **Validation -0.84**
- Persistence metric (12m horizon): stock_specific_momentum rank IC 0.031, t-stat 6.52 (the dominant signal)
- Style / industry / beta components near zero — supports the empirical case for focusing on stock-specific signals over factor rotation
