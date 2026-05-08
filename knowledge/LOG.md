# Discovery Log

Chronological record of findings. Wiki pages synthesise these into structured knowledge.

## 2026-05-08

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
