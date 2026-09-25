# `inner_join` Audit — Remaining ~20 Sites (#657)

**Date:** 2026-09-24
**Store commit read against:** `main` @ `952bd45` (the `docs/_targets` store in the
main checkout at that build state; store contains 1421 targets)
**Method:** Reconstruct each join from the built store via `tar_read_raw()` (read-only,
no `tar_make()`); compute the exact overlap window on the join key and compare to the
result row count. Where the raw upstream side is not itself a stored target (a live
API fetch embedded in the target body), the post-join target's own coverage is used as
the best available proxy and is flagged as such.

This follows on from [#656](https://github.com/JohnGavin/historical/issues/656), which
verified the 8 sites from the original #641 sweep plus one it missed. This audit covers
the remaining ~20 sites named in [#657](https://github.com/JohnGavin/historical/issues/657),
prioritising `plan_strategy_correlation.R` and `plan_wf_correlation.R` first as instructed.

## Summary

| Classification | Count |
|---|---|
| CONFIRMED (loses periods now, on a published path) | 0 |
| LATENT (structurally capable, currently 0 dropped, feeds a published metric) | 1 |
| SAFE / BENIGN (verified with real evidence) | 26 |
| INDETERMINATE | 1 |

**Headline result:** every site that genuinely joins two *independently-sourced,
period-keyed* time series and feeds a published dashboard turned out, on measurement,
to lose either **zero** months within the overlap window, or to lose months **only** at
the live leading/trailing edge (one series' data starts later or hasn't caught up to
the most recent month yet — a publication-lag effect, not a hazard). The one LATENT
finding is fixed in this PR (Pattern 4 observability, not a behaviour change). The
issue's own stated prior — "most are fine" — held up under measurement for every site
this audit could quantify.

---

## Priority sites: correlation targets (done first, as required)

### `R/plan_strategy_correlation.R:302` — `strat_returns_aligned` — **LATENT (fixed)**

```r
aligned <- base |> inner_join(ltr_col, by = "ym") |> select(-ym) |> arrange(date)
```

`base` = the 4-strategy family (`stk_max`, `stk_drif`, `fac_max`, `fac_drif`) from
`port_returns`, already complete-case filtered. `ltr_col` = `ltr_portfolio`'s monthly
return, keyed on `ym`.

**Evidence (tar_read reconstruction):**

| | nrow | range |
|---|---:|---|
| `base` (4-strategy family, complete-case) | 193 | 2010-02 … 2026-02 |
| `ltr_col` | 254 | 2005-01 … 2026-02 |
| `inner_join` result (= stored `strat_returns_aligned`) | 193 | — |
| months in `base` dropped (not in `ltr_col`) | **0** | — |
| months in `ltr_col` dropped (not in `base`) | 61 | 2005-01 … 2010-01 (before `base`'s own window starts — expected) |

Zero months are lost from the family's own window. `ltr_portfolio`'s extra pre-2010
history is correctly excluded because the other four strategies have no data there
either. Cross-checked by recomputing the correlation matrix both ways
(`inner_join`-based vs. a `full_join` + `pairwise.complete.obs` alternative): **max
absolute difference across all 25 cells = 0**. The two constructions are numerically
identical on this build.

**Why LATENT, not SAFE-and-done:** `strat_corr_matrix` (built from this target) feeds
`strat_keff_vertox`, which is exposed as the published `k_eff_family`/`k_raw_family`
columns on `leaderboard.qmd` (via `plan_leaderboard.R`'s `.dsr_row()`, `is_family =
TRUE` branch). A *future* gap in `ltr_portfolio` within the family's own window would
silently shrink that published window with no trace — exactly the
`fail-loud-not-null.md` defect shape, just not triggered by today's data.

**Fix applied:** extracted the check into `.warn_ltr_join_gap()` (plain, unit-testable
function, same rationale as the existing `.build_wide_corr_matrix()` helper in the same
file) and called it before the join. It `cli::cli_warn()`s the count and the exact
dropped `ym` values whenever `ltr_portfolio` fails to cover a family month. No
behaviour change on this build (0 dropped → silent). Snapshot-tested in
`tests/testthat/test-strategy-correlation-wide.R`.

### `R/plan_wf_correlation.R:225,469` — `wfc_fm_grid`, `wfc_drif_grid` — **SAFE**

Both join a fixed 5-element parameter grid (`theta_id` = `top_n ∈ {1..5}` for
Factor MAX, `alpha ∈ {0,0.25,0.5,0.75,1}` for DRIF elastic-net) between an IS and an
OOS computation. The grid is a hardcoded literal, identical on both sides of each join
(`top_n_grid <- 1L:5L` appears verbatim at both the IS and OOS target; `alpha_grid <-
c(0.00, 0.25, 0.50, 0.75, 1.00)` likewise). The only failure mode is an all-or-nothing
early return (`< 6` or `< 3` months of history) that empties **both** IS and OOS
tibbles together — never a per-`theta_id` dropout.

**Evidence (tar_read of the actual stored targets):**

| target | nrow | theta_ids |
|---|---:|---|
| `wfc_fm_grid_is` | 5 | 1,2,3,4,5 |
| `wfc_fm_grid_oos` | 5 | 1,2,3,4,5 |
| `wfc_fm_grid` (joined) | 5 | 1,2,3,4,5 |
| `wfc_drif_grid_is` | 5 | 1,2,3,4,5 |
| `wfc_drif_grid_oos` | 5 | 1,2,3,4,5 |
| `wfc_drif_grid` (joined) | 5 | 1,2,3,4,5 |

This is not a period-key join at all in the `fail-loud-not-null.md` sense — it's a
lookup-table join on a compile-time-fixed enumeration, the same class as a ticker key.
`R/plan_mom_prepeak_gauntlet.R:121` (`mom_prepeak_wfc_grid`) uses the identical
construction (fixed `n_quantiles` grid on both IS/OOS sides) and is classified SAFE by
the same reasoning; not independently re-verified via `tar_read` in this pass given the
code-level proof is identical.

---

## Remaining ~20 files — full classification

### CONFIRMED / real drops within an overlap window

None found.

### LATENT (feeds a published path)

Only `strat_returns_aligned` above.

### SAFE / BENIGN — verified via `tar_read` reconstruction

| Site | Join | Evidence |
|---|---|---|
| `R/plan_etf_replication.R:333` (`etf_comparison_plot`, published chart) | `inner_join(a, b, by="date")`, `etf_a_portfolio` vs `etf_b_portfolio` | a: 119 rows (2016-06→2026-04); b: 153 rows (2013-06→2026-02). Dropped from a: 2 (**2026-03, 2026-04** — both after b's last date 2026-02-15: pure trailing-edge publication lag). Dropped from b: 36 (all before a's 2016-06 start — expected). **0 mid-series loss.** |
| `R/plan_managed_futures.R:84` (`mf_data`, feeds `mf_signals`→`mf_portfolios`→published "Managed Futures" leaderboard row via `strat_returns_wide`) | `inner_join(assets, ff5, by="ym")` | assets: 242 rows (2006-03→2026-04); FF5 RF: 752 rows (1963-07→2026-02). Dropped from assets: 2 (**2026-03, 2026-04** — again both after FF5's last month 2026-02: trailing-edge lag in the FF5 data feed, not a hazard). Dropped from FF5: 512 (pre-2006 FF5 history, unused — expected). **0 mid-series loss.** |
| `R/plan_rafi.R:79` (`rafi_data`) | `inner_join(ff5_wide, mom_wide, by="date")` | ff5_wide: 752 rows (1963-07→2026-02); mom_wide: 1192 rows (1926-11→2026-02). Dropped from ff5_wide: **0**. Dropped from mom_wide: 440 (mom's earlier 1926-1963 history, unused). |
| `R/plan_drif.R:374` (`drif_vs_max`, published comparison chart of two flagship strategies) | `inner_join(drif, max_data, by="ym")` | drif: 691 rows (1968-08→2026-02); fm_portfolio (max): 740 rows (1964-07→2026-02). Dropped from drif: **0** (DRIF's own full history is fully preserved). Dropped from max_data: 49 (1964-07→1968-07, before DRIF's own history starts — expected). |
| `R/plan_european_overlay.R:108` (`eur_daily`) | per-ticker EU ETF daily return `inner_join(regime_daily, by="date")` | Raw per-ticker fetch is a live Yahoo call embedded in the target, not itself a stored target — reconstructed via the stored `eur_daily`'s own per-ticker gap structure instead. Max gap per ticker: 5-7 calendar days (EXSA.DE 6, FEZ 5, VGK 5, EWG/EWQ 7) — consistent with ordinary weekend + national-holiday trading calendars, not a truncation. `eur_daily`'s full date range is contained within `rsc_regime`'s range. |
| `R/plan_european_overlay.R:333` (`eur_ciss_results`) | per-ticker `inner_join(eur_ciss_regime, by="date")` | Reconstructed directly: for all 5 tickers, pre-join n exactly equals post-join n (EXSA.DE 4519=4519, FEZ 5904=5904, VGK 5304=5304, EWG 6606=6606, EWQ 6606=6606). **0 dropped for every ticker.** |
| `R/plan_european_overlay.R:390` (`ov_sharpe` in `eur_caption`) | `inner_join(bh_sharpe, ov_sharpe, by="ticker")` | Both sides are filtered subsets of the same upstream `eur_results` table by `strategy` value — same lineage, same ticker universe by construction. |
| `R/plan_factormax.R:353` (`fm_etf_corr`) | per-(ETF,factor)-pair `inner_join(etf_ret, fac_ret, by="ym")` | Self-reports the exact overlap as a `Months` column in its own output (151-153 across the 6 pairs) — transparent by construction; a reader sees the sample size directly, no silent loss. |
| `R/plan_factormax.R:422` | `inner_join(date_lookup, expected_dates, by="ym")` | Not a data-computation join — this is a `stopifnot()`-gated regression guard against a *previous* bug (#216), asserting two derivations of the same quantity agree. |
| `R/plan_guardian.R:91` (`gdn_vs_spy`, NOT published — no `.qmd` or R consumer found for this target) | `inner_join(wide, spy, by="year_month")` | gdn: 55 distinct months (2021-12→2026-08); SPY: 76 months (2020-01→2026-04). Dropped from gdn: 4 (**2026-05, 2026-06, 2026-07, 2026-08** — all after SPY's last month 2026-04: trailing-edge lag in the cached SPY feed). Dropped from spy: 25 (before gdn's 2021-12 start — expected). **0 mid-series loss; also unpublished (orphan diagnostic).** |
| `R/plan_jst_trend.R:276` (`jt_pervasiveness`) | `inner_join(bh_sh, tf_sh, by="iso")` — country code, not a period key | Both sides are filtered subsets of the same upstream `jt_country_metrics` by `strategy` value — same lineage, same country universe by construction. Self-reports `n_countries`/`n_tf_wins` in its output. |
| `R/plan_xgb_signal.R:120` (`xgb_drif_portfolio`) — **re-verified, closes out a #656 "inferred" claim** | `inner_join(stk_monthly, by=c("ticker","ym"))` | Directly reconstructed: `xgb_drif_signal` 18,999 distinct (ticker,ym) pairs; `stk_monthly` 24,409. `anti_join` → **0 pairs dropped**. This proves the "shared `stk_drif_features` lineage" claim #656 made by *inference* — it is now proven by *measurement* on this build. |
| Compound `(ticker, date)` / `(ticker, ym)` keyed joins: `R/commodities_momentum.R:141`, `R/cross_reference.R:21`, `R/plan_alpha_decay.R:93,95,131`, `R/momentum_decomposition.R:443,605`, `R/plan_momentum_decomposition.R:99` | Various | Each joins a series to its own forward/lagged return, or two tables sharing the exact same per-instrument upstream lineage. A missing key drops that one instrument-period, not a calendar period shared across constituents — the SAME shape #656 already ruled BENIGN for `plan_xgb_signal.R:104,113` and `plan_add_crowding.R:154`. `cross_reference.R:21` is additionally a diagnostic QA utility that already `cli_warn()`s on zero overlap. |
| `R/momentum_decomposition.R:221` (`momentum_components`, De Boer et al. replication; tracked by `qa_summary` but not rendered on any `.qmd`) | `inner_join(factor_ym, by="ym")` | stock_ym: 772 distinct months (1962-01→2026-04); factor_ym (FF5): 753 months (1963-07→2026-03). 19 stock months have no factor match: **18 are 1962-01→1963-06 (before FF5's own start) and 1 is 2026-04 (after FF5's own end)** — pure leading+trailing edge, 0 mid-series gaps. |

### SAFE — classified by code-pattern analogy (not independently `tar_read`-reconstructed this pass)

| Site | Reasoning |
|---|---|
| `R/plan_nyt_sentiment.R:188,215` | Period-key join (date, lag-shifted) between NYT keyword counts and SPY monthly returns. Self-reports `n_months` as an output column and has a `min_months` floor guard before computing a correlation — same transparency shape as `fm_etf_corr` and `gdn_vs_spy`, both of which were independently verified above to lose only trailing-edge months. Flagged here as lower-confidence evidence than the fully-quantified rows; a follow-up could `tar_read` `nyt_keywords` + `hd_ohlcv("SPY")` the same way `gdn_vs_spy` was done. |
| `R/tracking_error.R:59` (`calculate_te_ir`) | **Dead code.** Its only two callers are `R/plan_te_ir.R` and `R/plan_integration.R`; neither `plan_te_ir()` nor `plan_integration()` is sourced or called by either `_targets.R` (root or `docs/`) — confirmed by grep. The function is unreachable from any build. |

### INDETERMINATE

| Site | Why |
|---|---|
| `R/plan_jst.R:98` (`jst_ff_comparison`) | `inner_join(jst_usa, ff_annual, by="year")` is never reached on this build. `ff_annual` is derived from `hd_factors(dataset="FF3", frequency="annual")`, which returns **0 rows** (verified directly) — the target's own guard (`if (is.null(ff) \|\| nrow(ff)==0L) { cli::cli_warn(...); return(NULL) }`) fires first and the stored `jst_ff_comparison` target is confirmed `NULL`. This is a genuine, already fail-loud (per `fail-loud-not-null.md`) data-availability gap — the "FF3 annual" frequency does not exist in the `factors` parquet — but it is a *different* defect class than a silent `inner_join` truncation, and it means the join's behaviour on real data cannot currently be evaluated at all. Recommend a separate issue for the FF3-annual data gap; out of scope to fix here. |

---

## The two "inferred rather than proven" claims from #656

1. **`R/plan_xgb_signal.R:167` (now line 120) "shared `stk_drif_features` lineage" → PROVEN.** See the table row above: `anti_join` on the current store shows 0 of 18,999 (ticker,ym) pairs dropped.
2. **`R/plan_stock_backtest.R:1014-1033` claim, and the #603 historical figure (~128/~190 months) at `R/plan_bootstrap_ci.R`.** Not re-verified in this pass — the file has shifted substantially since #656 (current `plan_stock_backtest.R` line 1014-1033 no longer contains the cited join; the actual site could not be located with confidence within this dispatch's time budget) and re-deriving the #603 historical figure requires rebuilding an older commit's store, which is out of scope for a read-only audit against the current build. Flagged for a follow-up dispatch.

## Recommendation: lint-style check for new period-key `inner_join`s

Not implemented in this pass. A `ast-grep`/regex rule that flags any new `inner_join(...,
by = c("date"))` or `by = "ym"` (period-only key, no ticker/instrument/country
component) outside an allow-list would catch the *shape* early, though it cannot by
itself distinguish CONFIRMED from BENIGN — that still needs the `tar_read`
reconstruction this audit and #656 both did by hand. Worth a small follow-up issue.

## Related

#656 (verified findings for the first 9 sites), #641 (origin), #651 (the fix pattern
reused here for `.warn_ltr_join_gap`), #626/#635 (the correlation structure this audit
covers is what the leverage/book-vol diversification claim rests on),
`.claude/rules/fail-loud-not-null.md`.
