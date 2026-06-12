# Multivariate Return Simulation — Phase A Audit

**Issue:** JohnGavin/historical#389
**Date:** 2026-05-31
**Scope:** Read-only investigation of current pipeline state; no code changes.

---

## Executive Summary

The `historical` pipeline does **not** currently produce multivariate joint return
simulations suitable for downstream cashflow projection. The pipeline is a
high-quality data ingestion and strategy-backtesting engine: it ingests equity,
crypto, macro, and factor data; validates and consolidates it; and runs
single-asset or strategy-level analyses. Cross-asset correlation infrastructure
(`plan_cross_asset_corr.R`, `regime_correlations.R`) exists as a plan file but
remains partially wired — it depends on a `strategy_returns_wide` target that is
not produced by the canonical `_targets.R`. No `simulate_paths()` function or
joint multi-asset simulator of any kind exists anywhere in the codebase. Four
specific capabilities are missing: a first-class annual-return series per asset
class, a calibrated joint covariance target, a forward-path simulator, and a
real-vs-nominal split via CPI. Phases B–E (described below) would add these
incrementally without touching the existing backtesting machinery.

---

## Current Pipeline Inventory

### `_targets.R` — canonical entry point

The top-level pipeline (`_targets.R:1–108`) orchestrates ingestion and validation
for four data families:

| Target group | Key targets | Schema |
|---|---|---|
| Equity | `equity_api_raw`, `equity_api_valid`, `equity_clean`, `consolidated_equity` | `ticker, date, open, high, low, close, adjusted, volume` |
| Crypto | `crypto_api_raw`, `crypto_api_valid`, `crypto_clean`, `consolidated_crypto` | same schema as equity |
| Macro (FRED) | `macro_raw`, `macro_valid`, `consolidated_macro` | `date, value, series_id, source` |
| Factors (Ken French) | `factors_raw`, `factors_valid`, `consolidated_factors` | `date, factor_name, value, dataset` |

These are the pipeline's **only currently-wired targets**. All plan functions in
`R/` are available but not called from `_targets.R` — the pipeline is structured
as a data-warehouse foundation that strategy plans build on top of.

### Return series: what exists

**Per-ticker price series** exist in `consolidated_equity` and `consolidated_crypto`
(adjusted close, daily frequency). Daily log-returns can be computed from these
but are never materialised as a named target. Monthly aggregation is done
ad-hoc inside individual plan files (e.g. `plan_bootstrap_ci.R:22–35`,
`plan_portfolio_opt.R:26–44`). There is no reusable `monthly_returns` or
`annual_returns` target at the asset level.

**Factor returns** (Ken French FF5 + Momentum) exist in `consolidated_factors`
(daily) and are aggregated to monthly inside plan targets. `hd_factors()` in
`packages/historicaldata/R/` provides a direct query API.

**Strategy returns** are computed inside individual plan functions as `port_ret`
or `portfolio_ret` columns on wide monthly tibbles. These are strategy-level,
not asset-level.

### Correlation / covariance: what exists

`R/plan_cross_asset_corr.R` and `R/regime_correlations.R` provide the most
directly relevant existing code:

- `regime_correlations()` (`regime_correlations.R:11–64`) accepts a wide
  returns tibble and a VIX series and returns unconditional + VIX-regime-split
  correlation matrices (calm, crisis, vix_low/medium/high, tail quintiles).
- `detect_contagion()` (`regime_correlations.R:89–122`) flags pairs whose
  calm→crisis correlation jump exceeds a threshold.
- `plan_cross_asset_corr.R:8–160` wires these into targets, but the upstream
  target `strategy_returns_wide` is referenced as if it already exists — it is
  not produced by the canonical pipeline, making this plan currently
  non-executable as written.

**No covariance matrix target exists.** The correlation infrastructure computes
pairwise `stats::cor()` (`regime_correlations.R:78`), not a full covariance
matrix. The distinction matters for simulation: simulation requires `Σ`
(covariance), not just `R` (correlation), unless volatility is held constant.

### Simulation: what exists

`packages/historicaldata/R/falsification.R` contains six univariate null-environment
generators:

| Function | Model | Lines |
|---|---|---|
| `hd_null_env_white_noise()` | iid Gaussian | `falsification.R:116–123` |
| `hd_null_env_regime_vol()` | 2-state Markov-switching vol | `falsification.R:147–166` |
| `hd_null_env_ma1()` | MA(1) bid-ask bounce | `falsification.R:186–197` |
| `hd_null_env_factor_null()` | Single-factor β·f + ε | `falsification.R:219–254` |
| `hd_null_env_garch11()` | GARCH(1,1) | `falsification.R:255–304` |
| `hd_null_env_gjr_garch()` | GJR-GARCH (asymmetric leverage) | `falsification.R:305–353` |

All six are **single-asset, univariate** simulators. They return a list of
`M` numeric vectors of length `T_obs`. They are used in `plan_quiz.R:100–130`
to generate null-environment series for a strategy-discrimination game. None
accept a covariance matrix, and none produce multi-asset joint paths.

The block bootstrap in `plan_bootstrap_ci.R:38–57` resamples a *strategy* return
matrix in blocks to generate confidence intervals on Sharpe ratios. While it
preserves contemporaneous cross-strategy correlation within each block, it is
not a forward-path simulator; it does not project future paths and produces no
`(path_id, year, asset)` output.

### Inflation / real returns: what exists

**CPIAUCSL** (Consumer Price Index, all urban consumers, monthly, from 1947) is
registered in `packages/historicaldata/R/registry.R:218` and is queryable via
`hd_macro("CPIAUCSL")`. TIPS breakeven inflation series
(`T10YIE`, `T5YIE`, `T5YIFR`) are also registered (`registry.R:213–215`).
The JST Macrohistory database (`hd_jst()`, `jst.R:1–60`) provides annual CPI
alongside equity/bond total return indices back to 1870.

Despite this, **no target computes real returns** from any asset class. The macro
data is ingested into `consolidated_macro` (schema: `date, value, series_id`) but
never joined to equity or factor returns to produce inflation-deflated series.
There is no `real_return`, `return_real`, or `nominal_to_real` target or function
anywhere in `R/` or `packages/`.

---

## Gap Analysis

| Requirement | Current state | Gap |
|---|---|---|
| Per-asset marginal distributions | Adjusted-close price series exist; daily returns computable but not materialised as a named target. No per-asset return *distribution* object (mean, vol, skew, kurtosis, or fitted parametric model) | No `asset_return_summary` or distributional-fit target |
| Cross-asset covariance / correlation | Regime-conditional correlation matrices in `regime_correlations.R`, but (a) the plan is not wired into `_targets.R`, (b) only correlation (not covariance) is computed, (c) no rolling-window or annualised covariance target | Correlation plan exists but is unwired; covariance matrix absent |
| Time-varying structure (regime changes, vol clustering) | GARCH/GJR-GARCH null-env simulators exist per-asset; regime-split correlation matrices coded | GARCH and regime machinery is univariate + disconnected from a joint simulator |
| Inflation / real conversion | CPIAUCSL available in `consolidated_macro`; JST CPI available via `hd_jst()` | No target converts nominal returns to real; no `return_real` output column anywhere |

---

## Recommended Target API

The proposed function `simulate_paths()` should live in
`packages/historicaldata/R/simulate_paths.R` and produce a tidy tibble
consumable by downstream cashflow projectors.

```r
# simulate_paths() — proposed public API
#
# @param n_paths  Integer. Number of Monte Carlo paths (e.g. 1000L).
# @param horizon_years Integer. Years to project forward (e.g. 30L).
# @param assets  Character vector of tickers / series IDs registered in
#                hd_dataset_registry() (e.g. c("SPY", "TLT", "GLD")).
# @param Sigma   Numeric matrix (n_assets x n_assets). Annualised covariance.
#                If NULL, estimated from consolidated_equity via cov_annual target.
# @param mu      Named numeric vector. Annualised expected returns per asset.
#                If NULL, estimated from historical mean in return_summary target.
# @param method  One of "parametric" (multivariate normal), "bootstrap"
#                (block-bootstrap from historical returns).
# @param cpi_series  Series ID for CPI deflator (default "CPIAUCSL").
# @param seed    Integer random seed.
#
# @return Tibble with columns:
#   path_id       <int>    path index (1..n_paths)
#   year          <int>    projection year (1..horizon_years)
#   asset         <chr>    ticker / asset ID
#   return_nominal <dbl>   nominal annual return for (path, year, asset)
#   return_real   <dbl>    inflation-deflated return (nominal - CPI growth)
#   cum_nominal   <dbl>    cumulative nominal growth factor from t=0
#   cum_real      <dbl>    cumulative real growth factor from t=0

simulate_paths <- function(
  n_paths,
  horizon_years,
  assets,
  Sigma = NULL,
  mu    = NULL,
  method = c("parametric", "bootstrap"),
  cpi_series = "CPIAUCSL",
  seed = 42L
) {
  method <- match.arg(method)
  # ... implementation in Phase C ...
}
```

The output format mirrors tidy conventions used throughout the project (`long`
on `asset`, integer keys for `path_id` and `year`). Downstream consumers
(e.g. a cashflow projector) can summarise to `(year, asset)` quantiles with
a single `group_by() |> summarise()` call.

---

## Phase B–E Sketch

**Phase B — Correlation/covariance target** (estimated: 1–2 days)
Deliverable: a new `cov_annual` target in a `plan_returns.R` plan file that
(a) materialises monthly asset-level returns from `consolidated_equity`,
(b) annualises them, and (c) computes the full covariance matrix `Σ` alongside
a rolling 60-month covariance sequence. Also fixes the broken upstream dependency
in `plan_cross_asset_corr.R` so the existing correlation heatmap targets become
executable. No changes to the canonical `_targets.R` pipeline; the new plan
function is opt-in.

**Phase C — Joint simulator** (estimated: 2–3 days)
Deliverable: `simulate_paths()` in `packages/historicaldata/R/simulate_paths.R`
with two `method` modes: parametric (`MASS::mvrnorm()`) and block-bootstrap
(extending the existing per-strategy bootstrap in `plan_bootstrap_ci.R` to
multi-asset wide matrices). Unit-tested against known mean-vector / covariance
inputs. Returns the `(path_id, year, asset, return_nominal, return_real)` tibble
specified above.

**Phase D — Quantile outputs** (estimated: 1 day)
Deliverable: a `path_quantiles` target that wraps `simulate_paths()` and
summarises to P10/P25/P50/P75/P90 cumulative real and nominal return paths per
asset per horizon year. Plot function (`plot_fan_chart()`) producing fan-chart
visualisations per asset. This is the form downstream cashflow projectors will
consume directly.

**Phase E — Real-vs-nominal split using historical CPI** (estimated: 1 day)
Deliverable: a `cpi_annual` target that queries `consolidated_macro` for
`CPIAUCSL`, computes year-over-year CPI growth, and provides a historical
inflation bootstrap series for use inside `simulate_paths(method = "bootstrap")`.
Adds `return_real` to every simulation path by drawing paired (return, inflation)
blocks rather than treating inflation as a constant deduction. Validates against
JST Macrohistory equity-premium series as a sanity check.
