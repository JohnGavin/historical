---
title: Combinatorial Purged Cross-Validation (CPCV) — Purging, Embargo, Multi-Path OOS, PBO
canonical_question: "What is CPCV, how do purging and embargo prevent label-window leakage, and how does the resulting OOS path distribution support PBO and path-DSR?"
status: active
fresh_until: 2027-05-28
consensus_level: direct
sources:
  - lopez-de-prado-afml-2018.md
  - bailey-2014-pbo.md
  - bergmeir-benitez-2012.md
compiled_by: claude-sonnet-4-6
compiled_on: 2026-05-28
tags: [backtesting, cross-validation, purging, embargo, CPCV, PBO, deflated-sharpe, overfitting, look-ahead-bias]
---

# Combinatorial Purged Cross-Validation (CPCV)

Combinatorial Purged Cross-Validation (CPCV) is the resampling scheme for financial time series introduced in López de Prado (2018, AFML Ch. 12). It fixes two structural leakage problems that standard k-fold cross-validation ignores, then extends the single OOS path to a *distribution* of paths — the substrate for PBO and path-DSR. This page is the project knowledge digest; see also `#299` and `walk-forward-correlation.md` for complementary over-fitting diagnostics.

---

## The Two Leakage Problems CPCV Fixes

Standard k-fold CV assumes observations are i.i.d. Financial features derived from overlapping windows (e.g., 21-day return windows, rolling factor signals) violate this assumption in two ways:

### 1. Label-window overlap → training contamination (purging)

> ⚠ AI-inferred: the exact overlap condition depends on the label horizon relative to the fold boundary; the rule below is the standard formulation from AFML Ch. 12.

When a label (the target variable, e.g. next-month return) is computed from a window that extends forward in time, observations near the train/test boundary have labels that "see" into the test fold. Training on those observations injects direct look-ahead bias.

**Purging** removes all training observations whose label-window end-date is later than the first date of the test fold:

```
Remove from training:  { t ∈ train | t + label_horizon ≥ test_start }
```

For a 1-month label horizon and monthly frequency this removes the single month immediately before the test fold. For weekly data with a 4-week label, four weekly observations are removed.

### 2. Serial correlation leakage → post-test contamination (embargo)

Even after purging, serial autocorrelation between observations just after the test fold and those immediately preceding it can leak test-period information back into training. The **embargo** removes a further `embargo_n` observations *from training* that lie immediately after the end of the test fold:

```
Remove from training:  { t ∈ train | test_end < t ≤ test_end + embargo_n }
```

> ⚠ AI-inferred: López de Prado suggests embargo_n ≈ h × (T / T_bar), where h is label horizon, T is total observations, and T_bar is average number of observations per bar. In practice, for monthly data, embargo_n = 1 month is a standard conservative default.

The purge+embargo combination ensures the training set contains no observations whose information overlaps — either forward (purge) or backward via autocorrelation (embargo) — with the test fold.

---

## Combinatorial Paths

Standard walk-forward CV yields **one** OOS path: a sequence of test-fold predictions concatenated in time order. CPCV generalises this by treating fold assignment as a combinatorial object.

Divide the timeline into **N** equally-sized groups. Choose **k** groups to be the test set. There are C(N, k) = N! / (k! × (N-k)!) such combinations. Each combination yields a distinct OOS path (the predicted performance across that subset of test folds). The union of all C(N, k) paths forms the **path distribution**.

For N = 6 groups and k = 2 test groups: C(6,2) = 15 paths.

> ⚠ AI-inferred: Not all C(N,k) paths cover the full time span; only paths that use non-overlapping folds cover disjoint periods. The implementation in `hd_cpcv_paths()` returns ALL C(N,k) combinations without filtering for time-contiguity — downstream analysis should account for this when constructing equity curves.

### Why this matters

A single OOS path can be a fortunate draw. The path distribution exposes whether the "best" parameter configuration dominates *across paths* or merely on the one selected path — analogous to how WFC (#297) exposes whether the best parameter dominates across the full optimisation surface.

---

## Probability of Backtest Overfitting (PBO)

PBO was introduced in Bailey, Borwein, López de Prado & Zhu (2014) and is natural to compute from the CPCV path distribution.

**Algorithm (Bailey et al. 2014):**

1. For each of the C(N,k) path combinations, identify the in-sample (IS) best strategy: the strategy that ranks highest on IS performance across the training folds in that combination.
2. Evaluate the *same* strategy on the complementary OOS test folds for that path.
3. Compute the fraction of paths on which the IS-best strategy ranks below the OOS-median performance of all strategies tested.

```
PBO = fraction of paths where IS-best strategy has OOS rank < 0.5
```

- PBO close to 1 → the IS-best selection almost never survives OOS → strong evidence of overfitting.
- PBO close to 0 → the IS-best selection tends to rank above median OOS → strategy has genuine edge.
- PBO ≈ 0.5 under the null (random strategy) → a well-calibrated test should produce ~0.5 for a noise strategy.

> ⚠ AI-inferred: the exact implementation in Bailey et al. 2014 uses logistic regression of OOS performance on IS rank to smooth the discrete comparison; the version in `hd_pbo()` uses the simpler fraction-below-median formulation, which is equivalent in the large-path limit.

### Connection to trial-count DSR (#160)

The trial-count Deflated Sharpe (using `K_eff_strat` from Vertox) corrects a *reported* Sharpe for multiple testing across the set of strategies examined. PBO from CPCV is complementary: it asks whether the *resampling scheme itself* repeatedly selects the same strategy as best — a different angle on the same overfitting problem. Both should be reported; neither supersedes the other.

---

## Path-DSR

> ⚠ AI-inferred: "path-DSR" is not a named statistic in Bailey et al. (2014) or López de Prado (2018); it refers to computing the Deflated Sharpe Ratio using the *distribution of path Sharpes* (mean and standard deviation across paths) rather than the single OOS Sharpe. This gives a more conservative Sharpe estimate that accounts for path uncertainty.

Concretely:

```r
# Compute Sharpe for each path
path_sharpes <- sapply(paths, function(p) mean(p$ret) / sd(p$ret) * sqrt(12))
# Path-DSR uses distribution statistics
sharpe_mean <- mean(path_sharpes)
sharpe_sd   <- sd(path_sharpes)
# Apply deflation using K_eff_strat as trial count (from plan_falsification.R)
path_dsr <- hd_deflated_sharpe(path_sharpes, K_trials = K_eff_strat)
```

---

## Our Gap (Project Status — 2026-05-28)

| CPCV element | Status | Notes |
|---|---|---|
| Purging | Missing | `look-ahead-bias-prevention` guards the bet-decision cutoff but not label-window overlap between train/test. See FIXME in `plan_drif.R`. |
| Embargo | Missing | No post-test gap removal anywhere in the pipeline. |
| Combinatorial paths | Missing | Single OOS path only (`backtest-partitions` 3-way split). |
| PBO | Missing | Scaffolded in `hd_pbo()` in `packages/historicaldata/R/cpcv.R`. |
| Path-DSR | Missing | Depends on combinatorial paths; deferred to integration PR. |

The scaffold in this PR (`#299`) adds the helper functions. Full pipeline integration (targets wrapping each strategy's signal through `hd_cpcv_paths()`) is the follow-up.

---

## DRIF / MAX Label-Window Leakage Assessment

**DRIF elastic-net (plan_drif.R):** The target variable is `target_ret`, which is the **current month's actual return** (`monthly_ret` computed from `prod(1 + value) - 1` over the current month's daily returns). The training set for month `m` is all months with `ym < m`. At the partition boundary (test_start = 2020-01-01), month 2019-12-31 is in training and its label is December 2019's return — which does NOT overlap January 2020 (the first test month). The expanding window condition `ym %in% train_months` (strictly `< m`) enforces t-1 prediction.

**Assessment:** DRIF uses strictly prior months for training, with `target_ret` being the *current* (not future) month. This means the prediction at month m is made using features from month m-1 and earlier, and trained on actual returns up to month m-1. **No classical label-window overlap** in the standard CPCV sense — the label horizon is 1 month and the training window terminates at m-1.

However: the elastic-net is fitted with `cv.glmnet(..., nfolds = 5)` inside the expanding window. This inner CV uses **all folds of the training set** (months 1 to m-1) without purging. The inner CV's test folds may overlap with the outer test fold's label window if the label construction has any forward-looking component. For monthly non-overlapping labels this is a minor concern, but it should be flagged.

**MAX signal (plan_factormax.R):** The MAX signal is `max(daily_value)` within the current month `ym`. It is then used to predict *next* month's return (the portfolio buys factors with high current-month MAX for next-month return). This means: the MAX signal for month m is computed from all trading days within month m, and the prediction (trade) is executed at the end of month m for month m+1. This is correctly t+0 → t+1 signal → return. No label overlap.

**FIXME note added to plan_drif.R and plan_factormax.R below.**

---

## References

1. **López de Prado, M. (2018).** *Advances in Financial Machine Learning*, Wiley, Ch. 7 (Purging and Embargo), Ch. 12 (Combinatorial Purged Cross-Validation). ISBN 978-1-119-48208-6.
2. **Bailey, D., Borwein, J., López de Prado, M., & Zhu, Q. (2014).** "The Probability of Backtest Overfitting." *Journal of Computational Finance*, 20(4), 39–70. DOI 10.21314/JCF.2015.322.
3. **Bergmeir, C., & Benítez, J. M. (2012).** "On the Use of Cross-Validation for Time Series Predictor Evaluation." *Information Sciences*, 191, 192–213. DOI 10.1016/j.ins.2011.12.028.
4. **Bailey, D., & López de Prado, M. (2014).** "The Deflated Sharpe Ratio: Correcting for Selection Bias, Backtest Overfitting and Non-Normality." *Journal of Portfolio Management*, 40(5), 94–107.

## Sources

- `knowledge/raw/tinsley-walk-forward-correlation-2026.md` (cites CPCV as [6], p.2)
- Bailey et al. 2014 (primary PBO reference)
- López de Prado 2018 AFML (primary CPCV reference)
- Wikipedia: https://en.wikipedia.org/wiki/Purged_cross-validation
- QuantInsti article: https://blog.quantinsti.com/cross-validation-embargo-purging-combinatorial/
- Issue #299 (project gap audit)
- Issue #297 (Walk-Forward Correlation — related diagnostic)
- Issue #160 (Deflated Sharpe / K_eff_strat — complementary tool)
