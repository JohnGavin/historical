# Discovery Log

Chronological record of findings. Wiki pages synthesise these into structured knowledge.

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
