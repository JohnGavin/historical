# Discovery Log

Chronological record of findings. Wiki pages synthesise these into structured knowledge.

## 2026-05-08

### Tier 1 Data Integration Test Validation (PR #111)
- **All integration targets validated** — 14/14 targets pass in under 20 seconds
- **Test pipeline created** — `_targets_integration_test.R` with mock strategy returns for fast validation
- **Tracking Error / IR**: `te_ir_metrics`, `te_ir_table` — measure strategy divergence from SPY benchmark
- **Regime-conditional correlations**: `regime_corr_matrices` (9 regimes), `contagion_pairs`, `corr_heatmap_crisis/calm`
- **Tail K_eff**: `keff_crisis_calm_by_strategy`, `keff_efficiency_plot`, `keff_summary_table` — effective sample size accounting for autocorrelation
- **Data granularity fix**: `regime_correlations()` now expands monthly VIX to daily via year-month join (carry forward)
- **Date type fix**: Changed `as.Date()` to `as.POSIXct()` to match `hd_ohlcv()` output class
- **Next steps**: Merge PR #111 → validate in full pipeline (may need longer timeout for strategy feature engineering)
- Related: #105 (Tier 1 gaps), #102 (correlation contagion analysis)

### Macrosynergy Macro Data Research (#100)
- **Site access blocked (403)** — manual review required at https://macrosynergy.com/research/
- **Research gap identified**: We have 29 ECB series but only use CISS equity for regime classification
- **Unused series**: M3 money supply, HICP inflation, yield curve slope (10Y-2Y), yield level/curvature
- **Missing vs typical macro approaches**: Industrial production, PMI, credit spreads, consumer confidence
- **Priced-in risk**: GDP/CPI/PMI are widely-followed (consensus priced in); M3/credit conditions less watched
- **Next steps**: Manual review of Macrosynergy → test incremental power (Fama-French + macro α) → cross-geography validation
- **Current evidence quality**: BRONZE (no Macrosynergy access, no incremental-power test, no cross-geography replication)
- See [[macrosynergy-research]]

### TAA Selection, Mid-Caps, and Lazy Prices Research (#104)
- **Lazy Prices (10-K NLP)**: 22% annualized from text similarity on SEC filings, 6-18mo drift (Cohen et al. 2019)
  - Differs from Guardian NLP null result — 10-K is official disclosure with slow diffusion, not news
  - US-only evidence (violates cross-geography-pervasiveness) — need UK/EU replication
  - HIGH priority: exceptional returns, free data (SEC EDGAR), 4 robust similarity measures
  - Roadmap: obtain original paper → data pipeline (sec-edgar-downloader) → backtest replication → cost model
- **Size Effect (Lower Tier Large Caps)**: 11% annual claimed but ZERO disclosed sample period/robustness
  - Authors acknowledge parameter tuning, hypothesis reversal (initial idea failed)
  - LOW priority: not credible without sample period, single-market, modest returns
- **TAA Strategy Selection (AllocateSmartly)**: Momentum-based selection shows NO Sharpe improvement vs equal-weight
  - 53-year backtest (1973-2026), 100+ strategies, no transaction cost model
  - INFORMATIONAL: validates current decay-aware fixed weighting (plan_multi_strategy.R)
  - Short-term momentum (3-6mo) fails for TAA strategies
- See [[taa-selection-research]]

## 2026-05-07

### ECB Data Access (#88)
- 29/29 ECB SDMX series fetching successfully, 163,186 total observations
- Bond yield series use `YC/` dataflow (not `FM/M`); refi rate is `FM/D` (not `FM/M`)
- CISS sub-indices found via wildcard: `.CON` suffix = contribution, `.IDX` = index, `N` suffix = new/longer history
- HICP core failed (series key needs investigation)
- See [[ecb-data]]

### CISS vs VIX Correlations (#88)
- CISS equity sub-index vs VIX: Spearman r = +0.751 (6,653 daily obs, 2000-2026)
- All 5 sub-markets strongly correlated with VIX (r = 0.51 to 0.75)
- Cross-market correlation flips sign in crisis: calm r = -0.29, crisis r = +0.26 (contagion)
- US CISS (ECB-computed) vs VIX: r = 0.74 — validates comparability
- See [[ciss-stress]]

### Guardian NLP Sentiment (#89)
- Phase 2: keyword counts vs SPY — all |r| < 0.15 (no signal)
- Phase 3a: sentimentr body text vs SPY — same-month r ≈ 0.27 (contemporaneous, not predictive), next-month r < 0.08
- Headline-body sentiment correlation only r = 0.07 — body carries different signal than headline
- Conclusion: NLP does not beat keyword counts; newspaper text is priced in by publication time
- FinBERT (Phase 3b) not recommended — constraint is timing, not NLP quality
- See [[guardian-nlp]], [[priced-in-signals]]

### European Implied Vol
- No free source of VSTOXX exists in any public API
- CISS equity stress is the best free proxy (r = 0.75 with VIX)
- ECB publishes CISS for DE, FR, IT, GB, US — enables country-level regime analysis

### roborev Findings
- 91 failed reviews, 0 addressed (0% resolution rate)
- Cross-project workflow planned in JohnGavin/llm#110
- Key recurring findings: missing timeout/retry, frequency mismatches, hardcoded captions, no tests

## 2026-05-08

### Market Behavior Coverage Audit (#105)
- **Overall coverage: 53%** (weighted by importance)
- Strong: Performance metrics (95%), evolution tracking (80%)
- Partial: Correlation (65%), volatility (70%), market comparison (55%)
- Weak: Liquidity (15%), trading volumes (10%)
- **Tier 1 gaps (high priority):**
  1. Volume data ingestion + liquidity filters (ADV > $1M)
  2. Tracking error and information ratio vs SPY
  3. Cross-asset correlations (SPY, TLT, GLD, DBC)
  4. Tail K_eff (crisis vs calm regimes) per #55
- **Data availability:** Volume, VVIX, multi-asset returns all freely available (Yahoo Finance)
- **Effort estimate (Tier 1):** 8-12 hours implementation
- See [[market-behavior-gap-analysis]]

### Regime-Dependent Trend Following (#102)
- Alpha Architect article inaccessible (403 error) — research based on existing codebase + general principles
- **Three existing regime implementations** already in codebase:
  1. `plan_regime.R`: Volatility-based (realized vol + VIX), 3-tier scaling (100%/70%/40%)
  2. `plan_risk_state.R`: VIX options multi-signal (VVIX, term structure level/change), 3-tier (100%/50%/10%)
  3. `plan_avoid_worst.R`: VIX protection (binary on/off), extensive validation (walk-forward, cross-market, alpha decay)
- **Strengths**: Rigorous bias prevention (training-only thresholds, explicit t+1 execution), comprehensive robustness testing (parameter sweeps, subperiod stability, bootstrap CI)
- **Gaps vs literature**: No trend-regime (SMA distance, momentum z-score), no macro-regime (yield curve, credit spreads), discrete scaling only (no continuous functions)
- **Key insight from avoid_worst.R**: Worst/best days cluster (median 20-day gap) → selective avoidance impractical → regime-based exit justified
- **Evidence quality**: avoid_worst 82%, risk_state 78%, regime 70% (all meet or exceed Bronze quality gate)
- **Recommendations** (prioritized):
  1. Add trend-regime overlay (trending/choppy × low-vol/high-vol → 4 states)
  2. Test continuous VIX scaling vs binary (reduce switches)
  3. Expand cross-market validation to international/bonds/commodities (pervasiveness gap)
  4. Add transaction cost analysis to regime.R and risk_state.R
- See [[regime-trend-following]]

### Tier 1 Gap Integration (#105 follow-up)
- **Integration complete**: All 4 Tier 1 implementations wired to actual data sources
- **New integration plan**: `R/plan_integration.R` creates unified targets:
  - `vix_monthly`: Monthly VIX from existing `aw_vix_daily` target
  - `strategy_returns`: Unified long-format target combining all 5 strategies (Factor MAX, Factor DRIF, Stock MAX, Stock DRIF, XGB DRIF)
  - `spy_returns`: SPY benchmark returns from `consolidated_equity`
  - `multi_asset_returns`: Wide-format returns combining strategies + benchmarks (SPY, TLT, GLD, DBC)
- **Liquidity targets wired**: `equity_with_adv`, `equity_liquidity_filtered`, `liquidity_summary_table`
- **TE/IR targets wired**: `te_ir_metrics`, `te_ir_table` using SPY benchmark
- **Regime correlation targets wired**: `regime_corr_matrices` (9 regimes), `contagion_pairs`, heatmaps, SPY-TLT comparison
- **Tail K_eff targets wired**: `keff_crisis_calm_by_strategy`, `keff_efficiency_plot`, `keff_summary_table`
- **Pipeline changes**: Added 4 function sources + plan_integration to `docs/_targets.R`
- **Status**: Ready for `tar_make()` execution to materialize integrated targets
- **Next steps**: Run pipeline, validate outputs, integrate into vignettes

## 2026-05-16

### Quantocracy May 3 2026 Roundup (#126)
- **5 articles surveyed** from https://quantocracy.com/recent-quant-links-from-quantocracy-as-of-05032026/
- **Already covered by existing issues:** StratProof 22 crypto strategies (#125), Macrosynergy yield curve (#124)
- **Related to existing issues:** Beyond Passive risk parity audit (#114), Alpha Architect regime exposure (#119, #141)
- **New topics identified:**
  1. Optimal regime-dependent exposure sizing (Alpha Architect) — upgrades heuristic scaling in plan_regime.R
  2. Risk parity 58-year tail/drawdown audit (Beyond Passive) — empirical context for #114 HRP work
- **Individual article fetches:** WebFetch permission denied; blurbs sourced from Quantocracy HTML only
- See [[quantocracy-may-2026]]
