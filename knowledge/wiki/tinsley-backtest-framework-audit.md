# Tinsley Backtest Framework Audit — Historical Pipeline

One-line purpose: Per-pillar audit of whether the `historical` pipeline satisfies Martyn Tinsley's seven-pillar backtest quality framework, with HAVE / PARTIAL / GAP verdicts and proposed fixes for the two confirmed gaps.

---

## Pillar Audit Table

| # | Pillar | Verdict | Evidence | One-line justification |
|---|--------|---------|----------|------------------------|
| 1 | Data quality | **PARTIAL** | `R/plan_stock_backtest.R:109`, `R/plan_leaderboard.R:108-109` | Look-ahead bias enforced by `qa_look_ahead_bias` target; survivorship bias *flagged but not fixed* — `survivorship_biased = TRUE` column is a warning, not a filter |
| 2 | Simplicity | **HAVE** | `R/plan_drif.R:15-21`, `R/plan_leaderboard.R:24` | DRIF has 5 named parameters (`lookback_days`, `top_n`, `alpha`, `min_train_months`, `start_date`) plus 2×21=42 derived features; feature count is documented in the leaderboard (`"Elastic net (42 feat)"`); logic is explicit and documented |
| 3 | Walk-forward | **HAVE** | `R/plan_drif.R:113-130`, `R/plan_factormax.R:89-100` | DRIF uses `train_months[1:(m_idx - 1)]` (expanding window); Factor MAX uses prev-month signal (natural one-period expanding look-back); 60-month minimum training window enforced |
| 4 | Parameter sensitivity | **PARTIAL** | `R/plan_avoid_worst.R:622-678`, `R/plan_drif_v2.R` (no sweep found), `R/plan_factormax.R` (no sweep found) | `aw_practical_sensitivity` target sweeps VIX threshold and shock threshold for Avoid Worst; no corresponding `±20%` sweep target exists for DRIF `alpha`, `lookback_days`, `top_n`, or for Factor MAX `top_n` |
| 5 | Implementation realism | **PARTIAL** | `R/plan_stock_backtest.R:383-387`, `R/plan_leaderboard.R:46`, `R/plan_liquidity.R:20-23` | Cost model: 0.50% per trade, 3% borrow, ±20% winsorisation, ADV cap; round-trip in leaderboard uses 0.20% (leaderboard L46: `COST_PER_MONTH <- 0.002`); liquidity filter exists (`equity_liquidity_filtered` with 1M ADV threshold) but uses `filter_mode = "warn"` — not blocking — and is not wired into `stk_universe` |
| 6 | Logic before patterns | **HAVE** | `.claude/rules/cross-geography-pervasiveness.md`, `.claude/rules/resulting-prohibition.md`, `.claude/rules/priced-in-prohibition.md` | Three project rules enforce Tinsley's "causal reason for edge" criterion: pervasiveness across geographies required, outcome-driven revisions prohibited, priced-in signals prohibited |
| 7 | Portfolio context | **PARTIAL** | `R/plan_leaderboard.R:129-144` | `strategy_correlation` target exists and computes pairwise Pearson correlation of monthly returns across `stk_max`, `stk_drif`, `fac_max`, `fac_drif`; however, there is no incremental Sharpe calculation, no "redundant pair" flag visible in the leaderboard vignette, and no explicit integration of the correlation matrix into the ranking or decision logic |
| 8 | Risk as architecture | **PARTIAL** | `R/plan_falsification.R:766-806`, `R/plan_leaderboard.R:59` | `compute_drawdowns()` in `plan_falsification.R` computes `max_dd`, `avg_dd`, `n_drawdowns`, `max_dd_duration_obs`; `max_consecutive_losses` is also computed (L1089); `plan_leaderboard.R` reports `max_dd` and `cvar_95`; **loss clustering** (temporal concentration of losses, e.g. autocorrelation of negative monthly returns) is **not computed**; drawdown duration is computed but not surfaced in the leaderboard table |

---

## Pillar Detail

### Pillar 1 — Data Quality

**PARTIAL.** Two distinct quality concerns:

**Look-ahead bias — HAVE.** `plan_qa_gates.R` runs `qa_look_ahead_bias` on every `tar_make()` (cue mode `"always"`). It enforces four checks: no `lead(ym)` in return series, no forward-window `slide_dbl`, no `zoo::na.approx`, no `cumprod` of `forward_*` variables. The rule is codified at `.claude/rules/look-ahead-bias-prevention.md`.

**Survivorship bias — PARTIAL.** Merged in #150: `plan_stock_backtest.R:109` marks stock-level strategies with `survivorship_biased = TRUE` and `plan_leaderboard.R:109` propagates this flag to the leaderboard. However, no tickers are *removed* from `stk_universe` due to delisting absence. The `stk_top_tickers` filter (`top_n_market_cap = 100L`, `plan_stock_backtest.R:388`) restricts to top-100 by current market cap — which is itself a survivorship-prone filter (stocks that grew *to* top-100 are included; those that fell out are not). The issue body notes this is an open audit item (#143 Gap 3).

### Pillar 2 — Simplicity

**HAVE.** DRIF has five explicit scalar parameters in `drif_params` (L15–21 of `plan_drif.R`). The 42 features are derived columns (21 chronological + 21 rank), not independently tuned parameters. Factor MAX has two scalar parameters (`top_n = 2L`, `start_date`). Model failure is transparent: `cv.glmnet` failures produce `cli::cli_warn` and return `NULL`, which propagates as a missing month rather than a silent bad prediction. The leaderboard documents the feature count as a string (`"Elastic net (42 feat)"`).

### Pillar 3 — Walk-Forward Testing

**HAVE.** DRIF: for each trade month `m`, training data is `features[ym %in% months[1:(m_idx - 1)]]` (expanding window, `plan_drif.R:136`). Factor MAX: signal uses previous month's MAX ranks (`fm_signal |> filter(ym == prev_m)`, `plan_factormax.R:99`). Minimum training enforced: 60 months for DRIF (`min_train_months = 60L`), 12 months for Factor MAX. Three-way partition (train/test/validation) is defined in `plan_partitions.R` as a single source of truth shared by all strategies.

### Pillar 4 — Parameter Sensitivity

**PARTIAL.** Avoid Worst: `aw_practical_sensitivity` (`plan_avoid_worst.R:623`) sweeps VIX threshold and shock threshold — a genuine ±variation sweep. DRIF and Factor MAX: no equivalent target found by search across all `R/plan_*.R` files. Key parameters that lack a documented sweep: DRIF `alpha` (elastic net mixing, currently 0.5), `lookback_days` (21), `top_n` (2); Factor MAX `top_n` (2). The `robustness-testing.md` rule mandates ±20% sweeps for all strategies, but the implementation exists only for Avoid Worst.

### Pillar 5 — Implementation Realism

**PARTIAL.** Cost model is realistic: `cost_per_trade = 0.005` (0.50%), `borrow_rate_annual = 0.03`, winsorisation ±20%, ADV participation cap (`adv_pct_cap = 0.10`). The leaderboard net-cost calculation uses `COST_PER_MONTH = 0.002` (0.20% round-trip), which is the lower bound from the `backtesting-assumptions` rule. Liquidity analysis exists in `plan_liquidity.R` with a 1M USD ADV threshold, but uses `filter_mode = "warn"` (not `"error"` or `"filter"`), and `stk_universe` (L409) does not depend on `equity_liquidity_filtered` — illiquid stocks are not excluded from backtest portfolios.

### Pillar 6 — Logic Before Patterns

**HAVE.** Three project rules enforce this pillar:
- `.claude/rules/cross-geography-pervasiveness.md` — factor must be documented in ≥2 independent markets before adoption
- `.claude/rules/resulting-prohibition.md` — strategy revision must cite new *evidence*, not new *outcome*
- `.claude/rules/priced-in-prohibition.md` — signals from public information require incremental-power evidence beyond known factors

These rules are codified and referenced in the Swedroe alignment check in the issue. The DRIF signal derives from Alpha Architect research (documented in `plan_drif.R:3-4`); Factor MAX from a Dec 2025 Alpha Architect paper (`plan_factormax.R:3-4`).

### Pillar 7 — Portfolio Context

**PARTIAL.** The `strategy_correlation` target exists at `plan_leaderboard.R:129–144`. It computes a 4×4 Pearson correlation matrix of monthly returns (`stk_max`, `stk_drif`, `fac_max`, `fac_drif`) using the overlapping period from `port_returns`. What is *missing*:

1. No incremental Sharpe calculation (what does adding strategy X to {existing strategies} do to portfolio Sharpe?)
2. No "redundant pair" flag (pairs with |r| > 0.5 are not surfaced)
3. The correlation matrix is not displayed in the leaderboard vignette (no `tar_read("strategy_correlation")` call found by search)

> ⚠ AI-inferred: The `strategy_correlation` target was added recently (visible in the current code) and may not yet be surfaced in the vignette. Confirmation requires reading the leaderboard vignette `.qmd` file.

### Pillar 8 — Risk as Architecture

**PARTIAL.** What is computed: `max_dd`, `avg_dd`, `n_drawdowns`, `max_dd_duration_obs`, `max_consecutive_losses` (via `compute_drawdowns()` in `plan_falsification.R:766-806` and trade metrics at L1089); `cvar_95` in the leaderboard. What is *missing*:

- **Loss clustering**: temporal autocorrelation of negative monthly returns (do losses arrive in runs?). `max_consecutive_losses` is computed per strategy but not surfaced as a leaderboard column. No ACF of loss indicators or serial correlation test for the drawdown period.
- **Drawdown duration in leaderboard**: `max_dd_duration_days` is computed in `plan_falsification.R:868` but the leaderboard does not include it; `avg_dd_duration_days` is explicitly `NA_integer_` (L1105: `"complex to compute"`).

---

## Gaps and Proposed Fixes

### Gap 1 — Cross-Strategy Correlation Matrix Not Surfaced (Pillar 7)

**Status:** `strategy_correlation` target exists in code (`plan_leaderboard.R:129`) but the matrix is not displayed in the leaderboard vignette and there is no redundancy-flagging logic.

**Proposed fix (do not implement here — description only):**

In `plan_leaderboard.R`, add after the existing `strategy_correlation` target a second target `strat_redundancy_flags`:
```
strat_redundancy_flags: filter strategy_correlation to pairs where abs(r) > 0.5; 
  return tibble(strategy_a, strategy_b, correlation, flag = "redundant")
```

In the leaderboard vignette, add a "Strategy Correlations" tab:
- Display `strategy_correlation` as a colour-coded heatmap (red = high, blue = low)
- Display `strat_redundancy_flags` as a warning table if any pairs are flagged
- Caption: "Pairwise Pearson correlation of monthly returns. Pairs with |r| > 0.5 flagged as potentially redundant."

This would satisfy Tinsley's criterion: *"Value should be assessed by what the strategy contributes relative to existing holdings."*

### Gap 2 — Loss Clustering / Drawdown Duration Analysis (Pillar 8)

**Status:** `max_consecutive_losses` is computed per strategy in `plan_falsification.R:1089` but not used in the leaderboard. `avg_dd_duration_days` is explicitly left as `NA_integer_`. No serial correlation test on loss runs exists.

**Proposed fix (do not implement here — description only):**

Add a target `strat_loss_clustering` to `plan_falsification.R`:
- For each strategy, compute: monthly loss indicator (`ret < 0`), autocorrelation at lag 1 of the loss indicator, average run length of loss streaks, `max_consecutive_losses` (already computed), median drawdown duration in months
- Flag strategies where lag-1 autocorrelation > 0.2 as "loss-clustering" risk

Surface in the vignette as a "Risk Profile" subsection:
- Bar chart: `max_consecutive_losses` per strategy (Tinsley: "drawdown shape")
- Table: `avg_loss_run`, `median_dd_duration_months`, `loss_autocorr_lag1`

The existing `compute_drawdowns()` in `plan_falsification.R:766` already extracts `dd_runs` (drawdown run lengths); the `avg_dd_duration` can be derived from `mean(dd_runs)` and should be added rather than left `NA_integer_`.

---

## Gaps Summary

| Gap | Pillar | Severity | File to Change | Description |
|-----|--------|----------|---------------|-------------|
| Survivorship — filter not wired | 1 | High | `R/plan_stock_backtest.R` | `stk_universe` does not exclude illiquid/delisted stocks; `survivorship_biased` flag is advisory only |
| Liquidity filter not enforced | 5 | Medium | `R/plan_liquidity.R`, `R/plan_stock_backtest.R` | `equity_liquidity_filtered` uses `filter_mode = "warn"`, not wired into `stk_universe` |
| DRIF/FMAX no parameter sweep | 4 | Medium | `R/plan_drif.R`, `R/plan_factormax.R` | No `±20%` sweep targets for `alpha`, `lookback_days`, `top_n` |
| Correlation matrix not surfaced | 7 | Medium | Leaderboard vignette | `strategy_correlation` target exists but not displayed; no redundancy flag |
| Loss clustering not computed | 8 | Low | `R/plan_falsification.R` | `max_consecutive_losses` computed but not surfaced; `avg_dd_duration_days = NA_integer_` |

---

## Sources

- Issue #143 — original audit request with Tinsley's 7-pillar table and two gap proposals
- [#052 – Martyn Tinsley: Beyond the BackTest](https://algoadvantage.substack.com/p/052-martyn-tinsley-beyond-the-backtest) — The Algorithmic Advantage, May 11 2026
- `R/plan_drif.R` — DRIF parameters (L15–21), expanding window signal (L113–130)
- `R/plan_factormax.R` — Factor MAX expanding window (L89–100), 12-month minimum (L91)
- `R/plan_partitions.R` — train/test/validation partition source of truth
- `R/plan_leaderboard.R` — cost model (L46), survivorship flag (L109), `strategy_correlation` target (L129–144)
- `R/plan_stock_backtest.R` — cost parameters (L383–388), ADV cap (L113–138), universe construction (L409–436), survivorship marker (L698, L730, L960)
- `R/plan_qa_gates.R` — `qa_look_ahead_bias` target (L204–239), 4-pattern checks
- `R/plan_avoid_worst.R` — `aw_practical_sensitivity` parameter sweep (L622–678)
- `R/plan_falsification.R` — `compute_drawdowns()` (L766–806), `max_consecutive_losses` (L1089), `avg_dd_duration_days = NA_integer_` (L1105)
- `R/plan_liquidity.R` — `equity_liquidity_filtered` with `filter_mode = "warn"` (L20–23)
- `.claude/rules/look-ahead-bias-prevention.md` — look-ahead bias rule
- `.claude/rules/robustness-testing.md` — ±20% sweep mandate
- `.claude/rules/backtesting-assumptions.md` — cost model defaults
- `.claude/rules/cross-geography-pervasiveness.md` — Pillar 6 enforcement
- `.claude/rules/resulting-prohibition.md` — Pillar 6 enforcement
- `.claude/rules/priced-in-prohibition.md` — Pillar 6 enforcement
- Related: [[sweroe-evidence-investing]] (Swedroe alignment table in issue body)
- Related: #119 (momentum volatility spike analysis, Pillar 3 stress testing)
- Related: #125 (transaction cost reality check, Pillar 5)
- Related: #150 (survivorship bias warning added to leaderboard)
