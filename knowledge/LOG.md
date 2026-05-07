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
