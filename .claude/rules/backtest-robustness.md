---
paths:
  - "R/plan_*backtest*.R"
  - "R/plan_*qa*.R"
  - "R/tar_plans/plan_*.R"
---
# Rule: Backtest Robustness (Parameter Sensitivity & Regime Testing)

## When This Applies
Any project that backtests a trading strategy, betting model, or signal.

## CRITICAL: Reject Sharp Peaks, Require Plateaus

A strategy that only works at one "perfect" parameter setting is overfit.
Robust strategies work across a **broad region** of parameter space.

## Mandatory Checks

### 1. Parameter Sensitivity Sweep

Every backtest pipeline with tunable parameters MUST include a
`qa_parameter_robustness` target that varies each key param ±20%
and measures Sharpe/ROI degradation.

```r
tar_target(qa_parameter_robustness, {
  # For each tunable parameter, evaluate at -20%, base, +20%
  param_grid <- expand.grid(
    min_edge = c(0.024, 0.03, 0.036),
    rho = c(-0.156, -0.13, -0.104)
  )

  results <- purrr::pmap_dfr(param_grid, function(...) {
    params <- list(...)
    pnl <- run_backtest_with_params(params)
    tibble::tibble(!!!params, roi = pnl$roi, sharpe = pnl$sharpe)
  })

  # FAIL if Sharpe drops >50% at any ±20% perturbation
  base_sharpe <- results$sharpe[results$min_edge == 0.03 & results$rho == -0.13]
  worst_sharpe <- min(results$sharpe)
  ratio <- worst_sharpe / base_sharpe

  if (!is.na(ratio) && ratio < 0.5) {
    cli::cli_warn(c(
      "!" = "Parameter sensitivity: Sharpe drops {round((1-ratio)*100)}% at ±20%",
      "i" = "Strategy may be overfit to specific parameters"
    ))
  }

  results
}, cue = tar_cue(mode = "always"))
```

### 2. Regime-Conditional Evaluation

Separate backtest results by **volatility regime** (or equivalent risk
proxy). A strategy that only profits in low-vol and loses in high-vol
has hidden risk.

```r
tar_target(qa_regime_robustness, {
  # Classify each period as high/low vol
  bets <- ah_walkforward_all |>
    dplyr::mutate(
      regime = dplyr::if_else(
        rolling_vol > median(rolling_vol, na.rm = TRUE),
        "high_vol", "low_vol"
      )
    )

  bets |>
    dplyr::group_by(model, regime) |>
    dplyr::summarise(
      n_bets = dplyr::n(),
      roi_pct = round(100 * sum(net) / sum(stake), 1),
      sharpe = mean(net) / sd(net),
      .groups = "drop"
    )
})
```

### 3. Multi-Frequency Evaluation (where applicable)

For strategies that could be evaluated at different frequencies, test
at multiple timescales (daily, weekly, monthly aggregation). For
single-event markets (football matches), this means testing per-season
and per-league stability.

### 4. Falsification Test Summary (Mandatory)

Every backtest report MUST include a falsification test summary alongside
standard metrics. This tests whether the strategy's apparent edge survives
against simulated environments where no real edge exists.

| Metric | Description | Fail threshold |
|--------|-------------|---------------|
| K_eff_acf | Effective sample size *in time* after autocorrelation adjustment (Newey-West, per series) | < 30 |
| K_eff_strat | Effective *number of independent strategies* tested, correlation-aware (Vertox) | (input to deflated Sharpe, not a pass/fail) |
| Delta_Z | Z-score gap between strategy and null | < 1.96 |
| Stage 1 rejection rate | % of 5 simulation environments where strategy is rejected as noise | < 80% (must reject in 4/5) |
| Deflated Sharpe (DSR) | Sharpe corrected for non-normality AND multiple testing, using `K_eff_strat` (not raw M) as the trial count | DSR p-value > 0.05 |
| CVaR (95%) | Conditional Value at Risk | Worse than benchmark |

**Two distinct `K_eff` quantities — never conflate:** `K_eff_acf`
(`calculate_keff()`, autocorrelation-adjusted effective sample size *in time*,
per strategy) and `K_eff_strat` (`hd_strat_keff_vertox()`, correlation-aware
effective *count of strategies* across the tested portfolio). Bare `K_eff` is
reserved — always use a method-suffixed name. The deflated Sharpe ratio
(`hd_deflated_sharpe(r, K_trials = round(K_eff_strat))`) takes `K_eff_strat`,
NOT the raw strategy count `M`: on a correlated portfolio the raw count
over-penalises (the strategies are not independent tests).

Report these in a dedicated table in every backtest output, not just the
equity curve and raw Sharpe. References: [Backtests Lie](https://www.vertoxquant.com/p/backtests-lie),
[The Effective Number of Tested Strategies](https://www.vertoxquant.com/p/the-effective-number-of-tested-strategies) (Vertox), Lopez de Prado (2018) Deflated Sharpe Ratio.

### 5. K_eff-Guided Search Stopping (Correlated-Variant Multiple Testing)

When you iteratively add variants of an already-tested strategy (HRP Phase 1 →
Phase 2 → Phase 3, ADV-cap on/off, multiple Kelly fractions, universe
restrictions), each new variant is **highly correlated** with the prior ones.
Vertox's monotonicity axiom says such a variant adds **< 1** to `K_eff_strat`
even though it adds 1 to the raw count `M`. Reporting each variant's Sharpe as
an independent gain inflates apparent edge — the gains are partly a
multiple-testing artefact.

**Stop rule:** halt hyperparameter / variant search when the *marginal*
`K_eff_strat` gain from adding a variant falls below a threshold (default: a
new variant must raise `K_eff_strat` by ≥ 0.25 to justify a separate reported
result). Track `K_eff_strat / M` (the independence ratio) across the search:
when it drops sharply, you are mining correlated variants, not discovering
independent edge.

```r
# Before reporting a new strategy variant as a distinct result:
k_before <- hd_strat_keff_vertox(corr_without_variant, seed = 160L)
k_after  <- hd_strat_keff_vertox(corr_with_variant,    seed = 160L)
if (k_after - k_before < 0.25) {
  cli::cli_warn(c(
    "!" = "Variant adds only {round(k_after - k_before, 2)} to K_eff_strat",
    "i" = "Highly correlated with existing strategies; its Sharpe gain is partly a multiple-testing artefact. Apply deflated Sharpe before reporting."
  ))
}
```

## Robustness Heatmap

When reporting results with a tuned parameter, include a heatmap of
the objective (Sharpe or ROI) across a 2D param grid. Reject if the
optimal cell is an isolated peak surrounded by negative performance.

## Red Flags

| Pattern | Problem |
|---------|---------|
| Single optimal parameter | Overfit — real edge spans a region |
| Strategy works in 1 league only | Sample-specific, not generalizable |
| Strategy works in 1 season only | Temporal anomaly, not systematic |
| Sharpe > 2.0 in backtest | Suspiciously good — check for leakage first |

## What This Rule Prevents

- Publishing a "+5% ROI" result that only exists at `min_edge = 0.0317`
- Deploying a strategy that fails in the first high-vol regime
- Confusing in-sample parameter mining with genuine edge

## §6 PBO and Path-DSR via CPCV

The deflated Sharpe and K_eff_strat tools (§4) correct the *reported* Sharpe
for multiple testing across the strategy set. CPCV (Combinatorial Purged
Cross-Validation, López de Prado 2018, AFML Ch. 12) adds a complementary
diagnostic: instead of one OOS path, generate a **distribution** of OOS paths
and compute:

### §6.1 Probability of Backtest Overfitting (PBO)

PBO is the fraction of CPCV paths on which the in-sample (IS) best strategy
ranks below the OOS median (Bailey et al. 2014). It diagnoses whether the
*resampling scheme itself* repeatedly selects the same strategy — a different
angle from K_eff_strat (which asks about the strategy *set*).

```r
paths     <- hd_cpcv_paths(n_groups = 6L, n_test_groups = 2L)  # 15 paths
pbo_res   <- hd_pbo(is_scores, oos_scores)
# pbo near 1 → strong evidence of overfitting
# pbo near 0 → IS-best tends to rank above OOS median
```

### §6.2 Path-DSR

> See `knowledge/wiki/cpcv-purged-embargo.md` §Path-DSR for the derivation.

Compute the deflated Sharpe using the **distribution of path Sharpes** as the
estimate of the underlying Sharpe distribution, rather than the single OOS
Sharpe. This provides a more conservative DSR estimate that accounts for path
uncertainty:

```r
path_sharpes <- sapply(paths, function(p) mean(p$ret) / sd(p$ret) * sqrt(12))
path_dsr     <- hd_deflated_sharpe(path_sharpes, K_trials = round(K_eff_strat))
```

### §6.3 Two complementary layers — report both

| Layer | Tool | What it guards against |
|---|---|---|
| Multiple testing (strategy set) | DSR via `K_eff_strat` | Choosing the luckiest strategy from a correlated set |
| Resampling over-fitting | PBO via CPCV | IS-selection bias in the CV scheme itself |
| Path variability | Path-DSR | Single-path Sharpe estimate variance |

Neither supersedes the other. Report all three in every robustness summary.

### §6.4 Project status

CPCV helpers scaffolded in `packages/historicaldata/R/cpcv.R` (#299).
Full pipeline integration (plan_*.R targets per strategy) is deferred to
the #299 follow-up PR. Cross-reference: #297 (WFC), #160 (K_eff_strat).

## Related Rules

- `look-ahead-bias-prevention` — temporal leakage; §5 covers purge + embargo
- `backtest-partitions` — train/test/validation splits
- `statistical-reporting` — FPR, effect sizes
- `resulting-prohibition` — judge revisions by process, not outcome
- `cross-geography-pervasiveness` — geographic replication requirement
- `earnings-mean-reversion` — decay priors in feature construction
