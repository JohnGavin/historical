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


### 6. Walk-Forward Correlation (WFC) across the Full Grid

The checks above (ss1 sweep, heatmap) evaluate robustness locally or
visually.  WFC quantifies whether the IS optimisation surface has
structural predictive power by computing the Pearson and Spearman
correlation between IS and OOS metric across every parameter combination
(Tinsley 2026, SSRN 6324079).

WFC = rho(X, Y) over all theta in P, where X(theta) is the IS Sharpe
and Y(theta) is the OOS Sharpe for that parameter combination.

2x2 diagnostic matrix (Tinsley p.4):

High WFC + positive OOS  ->  Structural edge
High WFC + negative OOS  ->  Consistently loss-making
Low  WFC + positive OOS  ->  Spurious luck / over-fit
Low  WFC + negative OOS  ->  Noise

Calibration thresholds from paper Figure 4: high approx 0.881,
moderate approx 0.581, low approx 0.234.  Project working threshold: 0.70
(midpoint of moderate-high range).  See backtest-robustness rule for
the project-level hd_wf_correlation() wrapper.

Correlation is not edge: high WFC proves predictive consistency, not
profitability.  High WFC + positive OOS is the target.

WFC complements, not replaces, ss1-5 above.  See
knowledge/wiki/walk-forward-correlation.md for the full digest and
R/plan_wf_correlation.R + packages/historicaldata/R/wf_correlation.R
for the implementation (issue 297).

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

## Related Rules

- `look-ahead-bias-prevention` — temporal leakage
- `backtest-partitions` — train/test/validation splits
- `statistical-reporting` — FPR, effect sizes
- `resulting-prohibition` — judge revisions by process, not outcome
- `cross-geography-pervasiveness` — geographic replication requirement
- `earnings-mean-reversion` — decay priors in feature construction
