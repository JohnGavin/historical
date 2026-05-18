## Cakici et al. (2024) Coverage Audit — Elastic Net, DRIF, Reversal, Anomalies

Trigger: issue [#118](https://github.com/JohnGavin/historical/issues/118). Paper: Cakici, Fieberg, Metko, Zaremba — "Daily Return Information and the Cross-Section of Expected Stock Returns" (SSRN 6005614, 2024).

Purpose: document what this repo already does on each of the paper's 8 keyword categories before starting #117 (the main implementation issue), to avoid duplicating work.

Method: `Grep` sweep across `R/` and `packages/historicaldata/R/` plus `gh issue list --search` for each keyword. Cross-checked against `tar_target` enumerations and the existing wiki.

---

### 1. Elastic-Net Forecasting — ✅ Implemented

| File | Role |
|---|---|
| [`R/plan_drif.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R) | Main implementation — `glmnet::cv.glmnet(X_train, y_train, alpha = drif_params$alpha)` at L155-156; `drif_params$alpha = 0.5` (L19), 5-fold CV, MSE objective |
| [`R/plan_etf_replication.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_etf_replication.R) | Factor exposure replication for ETFs |
| [`R/plan_xgb_signal.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_xgb_signal.R) | XGBoost variant (no elastic net itself; named for the DRIF analogue) |
| [`R/plan_stock_backtest.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_stock_backtest.R) | Stock-level DRIF (uses `stk_drif_signal`; ML method varies) |
| [`R/plan_interpretability.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_interpretability.R) | SHAP / feature-importance for the elastic-net signals |

Targets: `drif_signal`, `drif_features`, `drif_portfolio`, `drif_metrics`, `drif_cumret_plot`, `drif_selection_freq`, `drif_vs_max`, `xgb_drif_signal`, `xgb_vs_enet`.

> ⚠ AI-inferred: `alpha = 0.5` (the project's setting) corresponds to equal L1/L2 mixing. Cakici's paper uses elastic-net for cross-sectional regression but I have not verified the paper's `alpha` value against the project's choice — flagged as a tuning question for #117.

Related closed issues: [#74](https://github.com/JohnGavin/historical/issues/74) (SHAP/feature importance for LTR + DRIF), [#29](https://github.com/JohnGavin/historical/issues/29), [#31](https://github.com/JohnGavin/historical/issues/31) (monotonic binning with XGBoost).

---

### 2. Daily Return Information (DRIF) — ✅ Implemented (factor-level), ⚠ Partial (stock-level)

| Layer | File | Status |
|---|---|---|
| Factor-level | [`R/plan_drif.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R) | ✅ Elastic net on 21-day daily factor returns → predict next-month factor return; rotate to predicted-best factor |
| Stock-level | [`R/plan_stock_backtest.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_stock_backtest.R) | ⚠ Uses `stk_drif_signal` (XGBoost analogue, not the paper's elastic-net spec); universe survivorship-biased per [#150](https://github.com/JohnGavin/historical/issues/150) |
| Falsification | [`R/plan_falsification.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_falsification.R) | `fals_drif_input` is in the pairwise tail-independence matrix (verified 254 complete monthly rows, #146 close) |

Targets: 10 `drif_*` targets in `plan_drif.R`; `stk_drif_signal`, `stk_drif_portfolio`, `stk_drif_metrics` in `plan_stock_backtest.R`.

Gap vs paper: Cakici's DRIF is **stock-level cross-section** with elastic-net regression. The project's stock-level version uses XGBoost. [#117](https://github.com/JohnGavin/historical/issues/117) tracks the paper-faithful elastic-net stock-level implementation. Also blocked on [#150](https://github.com/JohnGavin/historical/issues/150) (survivorship bias invalidates stock-level Sharpes).

---

### 3. Return Reversal — ⚠ Partial (different framing than paper)

| File | Implementation |
|---|---|
| [`R/plan_mean_reversion.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_mean_reversion.R) | Stock-level mean reversion: buy z-score < threshold; filters with skewness, semivariance; 7 `mr_*` targets |
| [`R/plan_volatility_spikes.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_volatility_spikes.R) | Computes `reversal_data` = days from VIX spike → recovery; informational, not a tradeable strategy |
| [`R/disclosures.R`](https://github.com/JohnGavin/historical/blob/main/R/disclosures.R) | Lists `mean_reversion` as a survivorship-bias-flagged strategy |

Targets: `mr_params`, `mr_daily`, `mr_risk_stats`, `mr_portfolio`, `mr_metrics`, `mr_plot`, `mr_caption`.

> ⚠ AI-inferred: Cakici's "Return Reversal" is **short-horizon cross-sectional return reversal** (last week / last month winners → losers). The project's `plan_mean_reversion.R` is a *time-series* z-score strategy — related but not the same construct. The cross-sectional short-horizon reversal that Cakici uses is not implemented as a standalone strategy.

Related issues: [#119](https://github.com/JohnGavin/historical/issues/119) (momentum underperformance + reversal speed), [#138](https://github.com/JohnGavin/historical/issues/138) (mean reversion in commodities).

---

### 4. Cross-Sectional Asset Pricing — ⚠ Partial

| File | Role |
|---|---|
| [`R/plan_falsification.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_falsification.R) | 9 `fals_*` targets including HAC and white-noise tests; `fals_tail_independence` runs pairwise tail-dependence across 5 strategies |
| [`R/plan_drif.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R) | Cross-sectional ranking across FF5 factors each month |
| [`R/plan_ltr_momentum.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R) | Cross-sectional momentum on factors (LTR = long-term reversal across the factor cross-section) |

Gap: No stock-level cross-section in the paper's sense (672 stocks survivorship-biased; full cross-section requires PIT data — #150 Option A).

---

### 5. Short-Horizon Return Predictability — ⚠ Partial

The project uses short lookback windows in several places but does not have a dedicated "short-horizon" experiment matching the paper's 1-day / 1-week prediction setup.

| Where short horizons appear | What |
|---|---|
| `plan_drif.R` | 21-day daily returns feed the elastic-net features |
| `plan_xgb_signal.R` | Short-horizon xgb features |
| `plan_alpha_decay.R` | `decay_delayed_returns`, `decay_half_life` — measures how fast alpha decays at t+1, t+2, ... |
| `plan_bootstrap_ci.R` | Block-bootstrap with short blocks |
| `plan_portfolio_opt.R` | Short-lookback covariance |

Targets in `plan_alpha_decay.R`: `decay_params`, `decay_delayed_returns`, `decay_metrics`, `decay_half_life`, `decay_plot`. (Important: covers paper's claim that DRIF alpha must persist at t+1 — already enforced project-wide per `feedback_alpha-decay-min-t1.md` memory.)

Related: [#122](https://github.com/JohnGavin/historical/issues/122) (causal modeling + ML ensembles for short-horizon risk and alpha).

---

### 6. Factor Zoo / Asset-Pricing Anomalies — ⚠ Partial

| File | Role |
|---|---|
| [`R/plan_forecast_eval.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_forecast_eval.R) | Forecast evaluation across strategies (the project's own zoo, not a published one) |
| [`R/plan_regime.R`](https://github.com/JohnGavin/historical/blob/main/R/plan_regime.R) | Regime conditioning across factors |
| [`R/disclosures.R`](https://github.com/JohnGavin/historical/blob/main/R/disclosures.R) | Implicit anomaly inventory: DRIF, FacMAX, LTR, RSC, VIXO, mean_reversion |

Gap: No standardised anomaly dataset (e.g. the 153 anomalies from Hou-Xue-Zhang or the 207 from the Cakici paper). FF5 is the only external factor input.

Related: [#143](https://github.com/JohnGavin/historical/issues/143) (Tinsley 14-step audit), [#116](https://github.com/JohnGavin/historical/issues/116) (Quantitativo 5-paper comparison).

---

### 7. Multiverse Analysis / Specification Curve — ❌ Not implemented

`Grep` for `multiverse|specification.curve|spec.curve` returned **no matches**. The closest hit is `plan_avoid_worst.R` which has a `_sensitivity` target — but a one-parameter sensitivity sweep is not a multiverse analysis.

Gap (vs paper):
- No formal enumeration of `2^n` analytical choices
- No fan chart over "robust to choice" specifications
- No equivalent to Simonsohn-Simmons-Nelson p-curve / specification curve plots

> ⚠ AI-inferred: This is the largest single gap relative to the paper. Cakici uses multiverse / specification-curve to defend their elastic-net spec against "garden of forking paths" critique. Without an equivalent, the project's DRIF Sharpe is one specification among many uncomputed ones.

Recommend opening a follow-up issue to implement at least a 2^4 = 16-cell multiverse on the existing `plan_drif.R` (alpha, nfolds, feature subset, target horizon).

---

### 8. Asset-Pricing Anomalies (named strategies) — ⚠ Partial

Project strategies that map to documented anomalies:

| Project strategy | Documented anomaly | Reference |
|---|---|---|
| DRIF | Cakici 2024 short-horizon | This paper |
| FacMAX | MAX effect (Bali, Cakici, Whitelaw 2011) | Not cited in repo |
| LTR | Long-term reversal (De Bondt-Thaler 1985) | Not cited in repo |
| RSC | Volatility regime conditioning | No standard citation |
| VIXO | VIX overlay | No standard citation |
| Mean reversion | Short-term reversal | Lehmann 1990, Jegadeesh 1990 |

Gap: No bibliographic citations in code or vignettes for the well-known anomalies. Tooltip work in [#140](https://github.com/JohnGavin/historical/issues/140) added GitHub-link tooltips but no academic citations.

---

### Cross-Cutting Gaps

1. **No multiverse / specification curve infrastructure** (keyword 7). Closing this would strengthen claims for every strategy, not just DRIF.
2. **No stock-level cross-section with PIT data** (#150 Option A blocker). Without it, the project's stock-level DRIF and LTR Sharpes are biased upward.
3. **No external anomaly dataset import** (keyword 6). Comparing in-house strategies against a standardised zoo would calibrate effect sizes.
4. **Short-horizon framing is implicit, not explicit** (keyword 5). Restructuring `plan_alpha_decay.R` outputs as "this strategy's edge at horizon h ∈ {1, 5, 21, 63} days" would surface short-horizon performance per `priced-in-prohibition` rule.

---

### Recommended Next Steps (ordered by impact ÷ effort)

| # | Action | Effort | Impact |
|---|---|---|---|
| 1 | Add Cakici / De Bondt-Thaler / Bali citations to `disclosures.R` and strategy vignettes | ~1h | Low cost, signals academic grounding; supports [#143](https://github.com/JohnGavin/historical/issues/143) Gap 1 |
| 2 | Re-frame `plan_alpha_decay.R` outputs as horizon-conditional table | ~3h | Addresses keyword 5; visible in leaderboard; feeds [#143](https://github.com/JohnGavin/historical/issues/143) Gap 2 |
| 3 | Open follow-up issue: 2^4 multiverse on `plan_drif.R` | ~1d | Largest single paper gap; sets precedent for other strategies |
| 4 | After [#150](https://github.com/JohnGavin/historical/issues/150) Option A, re-run [#117](https://github.com/JohnGavin/historical/issues/117) stock-level DRIF with PIT universe | $$$ + ~2d | Highest paper-faithfulness, but blocked on data acquisition |
| 5 | Import 1-2 external anomaly datasets (e.g. Hou-Xue-Zhang via openassetpricing.com) | ~1d | Calibrates in-house strategies against published ones |

---

### Sources

- Cakici, N., Fieberg, C., Metko, D., Zaremba, A. (2024). "Daily Return Information and the Cross-Section of Expected Stock Returns." SSRN 6005614. <https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6005614>
- [Issue #118](https://github.com/JohnGavin/historical/issues/118) — this audit's tracking issue
- [Issue #117](https://github.com/JohnGavin/historical/issues/117) — paper implementation tracking
- [Issue #150](https://github.com/JohnGavin/historical/issues/150) — PIT data blocker for paper-faithful stock-level cross-section
- Related wiki pages: [[priced-in-signals]], [[regime-trend-following]], [[market-behavior-gap-analysis]]
