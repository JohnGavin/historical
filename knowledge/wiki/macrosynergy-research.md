## Macrosynergy — Macroeconomic Data for Systematic Trading

### Access Limitation

⚠ **Site blocks automated access (403).** Manual review required at:
- Primary: https://macrosynergy.com/research/macroeconomic-data-and-systematic-trading-strategies/
- Hub: https://macrosynergy.com/research/

### Research Questions (Manual Review Checklist)

When manually reviewing Macrosynergy content, document:

1. **Indicator Construction**
   - [ ] What macro indicators do they use?
   - [ ] How are they normalized/standardized?
   - [ ] What categories (growth, inflation, policy, sentiment)?
   - [ ] What transformations (z-scores, percentiles, changes)?

2. **Publication Lag & Revisions**
   - [ ] How do they handle release lag (monthly GDP → 1-3 month delay)?
   - [ ] Do they model point-in-time data availability?
   - [ ] What's their approach to revisions (first release vs final)?
   - [ ] Do they use vintage data (as-published) or current (revised)?

3. **Predictive Power Evidence**
   - [ ] What asset classes do they trade?
   - [ ] What sample periods (in-sample vs OOS)?
   - [ ] What's the evidence quality (single market vs cross-geography)?
   - [ ] Do they report Sharpe/alpha/t-stats with HAC standard errors?

4. **Data Sources**
   - [ ] What providers (ECB, FRED, OECD, IMF, proprietary)?
   - [ ] Are there free alternatives to their data?
   - [ ] What's the frequency (daily, weekly, monthly)?

5. **Priced-In Defense**
   - [ ] How do they argue macro data isn't already priced in?
   - [ ] Do they claim speed advantage, processing advantage, or structural anomaly?
   - [ ] Do they test incremental power (alpha after controlling for known factors)?

### Comparison to Existing Work

#### Our Current Macro Data Inventory (plan_ecb.R)

| Category | Series | Frequency | History | Use |
|----------|--------|-----------|---------|-----|
| **FX** | EUR/USD, EUR/GBP, EUR/JPY, EUR/CHF | Daily | 2000-2026 | Not used in strategies |
| **Interest rates** | EURIBOR 3M/6M, ECB refi rate | Daily+Monthly | 2000-2026 | Yield spread calculated |
| **Yield curve** | 1Y, 2Y, 5Y, 10Y yields + Svensson params (level, slope, curvature) | Business daily | 2004-2026 | Regime indicator candidate |
| **CISS stress** | Composite + 5 sub-markets (equity, bond, FX, money, financial) + cross-correlation | Daily | 2000-2026 | **Active: CISS equity used for European regime** |
| **CISS country** | DE, FR, IT, GB, US | Daily | 2000-2026 | Country-level regime candidate |
| **Macro** | HICP inflation, M3 money supply | Monthly | 2000-2026 | Not used in strategies |

**Total:** 29 series, 163,186 observations.

#### Our Current Strategy Use (plan_european_overlay.R)

**CISS Equity Regime Classification:**
- Signal: CISS equity sub-index (r = 0.75 with VIX)
- Method: Percentile thresholds (33rd/67th) → benign/cautious/hostile
- Exposure: 100%/50%/10% in benign/cautious/hostile regimes
- Applied to: STOXX 600, Euro Stoxx 50, FTSE Europe, Germany, France ETFs
- Status: Testing (#58)

**VIX-Based RSC Overlay (US → Europe):**
- Signal: US VIX thresholds applied directly to European ETFs
- Exposure: Same 100%/50%/10% scaling as US SPY overlay
- Finding: Transfer effectiveness varies by ticker (some improve, some hurt)
- Issue: US-trained thresholds may not capture European-specific vol regimes

#### What We're Missing

Based on typical macro factor approaches (pending manual Macrosynergy review):

| Indicator Type | We have | Likely missing | Priority |
|---------------|---------|---------------|----------|
| **Growth** | M3 money supply (monthly) | Industrial production, retail sales, PMI, employment | Medium |
| **Inflation** | HICP headline (monthly) | HICP core, PPI, wage growth, breakeven inflation | Medium |
| **Policy** | ECB refi rate | Policy rate changes (not levels), forward guidance, QE announcements | Low (event-driven) |
| **Credit** | CISS financial stress | Credit spreads (BBB-AAA, high-yield), bank lending conditions | **High** |
| **Sentiment** | None | Consumer/business confidence, Sentix, ZEW | Low (priced-in risk) |
| **External** | FX rates (levels) | Trade-weighted EUR, terms of trade, commodity prices | Medium |

### Priced-In Analysis (Rule: priced-in-prohibition)

#### What We've Tested (All Failed)

From [[priced-in-signals]]:
- NYT/Guardian keyword counts → r ≈ 0
- NYT/Guardian sentiment (NLP) → same-month r ≈ 0.27, **next-month r ≈ 0**
- Conclusion: Narrative public data is priced in by publication time

#### Why CISS May Work (Structural/Institutional Edge)

| Factor | Why it may have edge |
|--------|---------------------|
| **Not widely followed** | CISS is ECB-specific, institutional focus — retail doesn't watch sub-indices |
| **Sub-market decomposition** | Breaks vol into equity/bond/FX/money/financial — reveals contagion patterns |
| **Cross-market correlation flip** | Calm r = -0.29, crisis r = +0.26 — quantifies "correlations go to 1" |
| **Free European vol proxy** | VSTOXX (commercial) alternative — retail stuck with VIX for European exposure |
| **Structural, not narrative** | Derived from market prices (vol, spreads), not opinion/forecast |

#### Macro Data: The Priced-In Challenge

| Macro release | Typical lag | Market reaction | Likely priced in? |
|--------------|-------------|-----------------|-------------------|
| GDP (quarterly) | 1-3 months | Strong (on surprise) | **Yes — consensus forecast priced in** |
| CPI/HICP (monthly) | 2-4 weeks | Very strong | **Yes — most-watched indicator** |
| PMI (monthly) | 1-2 weeks | Strong (leading indicator) | **Yes — widely followed** |
| ECB policy decision | Real-time | Immediate | **Yes — anticipated by forwards market** |
| M3 money supply (monthly) | 1 month | Weak (not closely watched) | **Possibly — less attention** |

**Implication:** For Macrosynergy's approach to work, they must either:
1. Have a **processing advantage** (transform macro data in a way others don't)
2. Trade on **less-watched series** (M3, credit conditions, not GDP/CPI)
3. Show **incremental power** after controlling for known factors (Fama-French, momentum, value)
4. Focus on **regime identification** (not forecasting levels)

### What to Look For in Manual Review

When reviewing https://macrosynergy.com/research/macroeconomic-data-and-systematic-trading-strategies/

**Red flags (violates priced-in-prohibition):**
- Claims macro forecasts (GDP, CPI) predict returns without incremental-power test
- Uses consensus data (analyst forecasts, widely-followed indicators) as signals
- No discussion of publication lag or vintage data
- No comparison to factor model residuals (alpha vs Fama-French)

**Green flags (legitimate edge):**
- Uses **changes** or **surprises** (actual vs consensus), not levels
- Focuses on **less-watched series** (credit conditions, money supply, not GDP)
- Tests **cross-sectional** signals (relative macro across countries), not time-series
- Explicitly models **point-in-time availability** (as-published vintages, not revised)
- Shows **incremental power** vs known factors
- Uses macro for **regime classification** (risk-on/risk-off), not return forecasting

### Data Availability Assessment

#### Free Public Sources (Comparable to ECB)

| Source | Coverage | Frequency | API | Status |
|--------|----------|-----------|-----|--------|
| **ECB SDMX** | Euro area + EU countries | Daily/Monthly | Yes (free, no auth) | ✓ Wired in (plan_ecb.R) |
| **FRED (St. Louis Fed)** | US + global macro | Daily/Monthly/Quarterly | Yes (free API key) | Not wired |
| **OECD.Stat** | OECD countries | Monthly/Quarterly | Yes (SDMX) | Not wired |
| **IMF IFS** | Global macro (200+ countries) | Monthly/Quarterly | JSON API | Not wired |
| **Eurostat** | EU countries, detailed sectoral | Monthly/Quarterly | Yes (via ECB or direct) | Not wired |
| **BIS** | Credit, housing, debt service | Quarterly | CSV download | Not wired |

#### Proprietary/Restricted

| Source | What it has | Cost | Status |
|--------|-------------|------|--------|
| **Macrosynergy** | Normalized macro indicators, JPMaQS dataset | Commercial | Not available |
| **Bloomberg** | Real-time + vintage macro, consensus forecasts | $$$ terminal | Not available |
| **Refinitiv/Datastream** | Historical macro, consensus, revisions | $$$ subscription | Not available |

**Implication:** We can replicate macro approaches using free APIs (ECB, FRED, OECD, IMF) but lack:
- Consensus forecast data (for surprise calculation)
- Vintage/revision history (for point-in-time modeling)
- Real-time intraday releases (for speed-based strategies)

### Recommended Next Steps

#### Immediate (This Issue #100)

1. **Manual review of Macrosynergy content**
   - Visit https://macrosynergy.com/research/macroeconomic-data-and-systematic-trading-strategies/
   - Fill in checklist above (indicator list, data sources, priced-in defense)
   - Download any whitepapers/methodology docs
   - Note any replicable findings

2. **Update this wiki page** with:
   - Specific indicators they use
   - Their data normalization approach
   - Evidence quality assessment (sample period, OOS, cross-geography)
   - Actionability score (High/Medium/Low) per indicator

#### Short-term (Next Sprint)

3. **Assess ECB macro series we're not using**
   - M3 money supply: growth rate, z-score transformation
   - HICP inflation: changes, deviations from ECB target (2%)
   - Yield curve slope (10Y-2Y): inversion as recession signal
   - Add these as regime features (alongside CISS equity)

4. **Test incremental power of macro features**
   - Add M3 growth, HICP deviation, yield slope to CISS regime model
   - Run Fama-French + macro regression: does macro α survive?
   - Compare in-sample vs OOS performance

5. **Cross-check with cross-geography pervasiveness rule**
   - If Macrosynergy shows a signal works in euro area, test on US data (FRED)
   - If US-only signal, test on European data (ECB)
   - Swedroe criterion: must work in 2+ independent markets

#### Medium-term (If Promising)

6. **Expand to FRED for US macro**
   - Add US industrial production, unemployment, retail sales
   - Test same regime classification on SPY using US macro (not VIX)
   - Compare US macro regime vs US VIX regime

7. **Test credit conditions indicators**
   - ECB bank lending survey (qualitative, quarterly)
   - BIS credit-to-GDP gap (leverage cycle indicator)
   - CISS financial intermediary stress (already have daily)

8. **Vintage data modeling (if Macrosynergy emphasizes this)**
   - Fetch historical GDP releases from Eurostat archives
   - Model as-published vs final-revised difference
   - Test whether first-release surprises predict returns

### Connection to Existing Rules

| Rule | How it applies |
|------|---------------|
| **priced-in-prohibition** | Macro data is public → burden of proof is on incremental power |
| **cross-geography-pervasiveness** | Macro signals must work in 2+ markets (US + Europe minimum) |
| **backtest-robustness** | Sweep normalization method (z-score vs percentile vs changes) |
| **look-ahead-bias-prevention** | Use point-in-time vintages, not revised data |
| **resulting-prohibition** | Judge macro signals by process (theory + cross-market evidence), not outcome |
| **underperformance-prior** | If macro overlay underperforms for 3-5 years, check historical regime durations before abandoning |

### Current Evidence Quality: Bronze

| Quality gate | Status |
|--------------|--------|
| **Documented approach** | ❌ Can't access Macrosynergy content (403) |
| **Replicable data** | ⚠ Partial (ECB free, but no consensus/vintage) |
| **Cross-geography test** | ❌ Not yet tested (CISS is euro area only) |
| **Incremental power vs factors** | ❌ No Fama-French + macro regression yet |
| **OOS validation** | ⚠ CISS overlay testing in progress (#58) |

**Upgrade path to Silver:** Manual review + replicate one Macrosynergy finding with ECB data + Fama-French α test.

**Upgrade path to Gold:** Cross-geography test (US FRED + Europe ECB) + 3-year OOS period + academic citation.

## Sources

- Macrosynergy research hub: https://macrosynergy.com/research/ (blocked, manual review needed)
- ECB SDMX API: tested 2026-05-07, 29 series active ([[ecb-data]])
- CISS methodology: Holló, Kremer & Lo Duca (2012), ECB WP #1426 ([[ciss-stress]])
- Priced-in evidence: [[priced-in-signals]]
- Swedroe framework: `~/docs_gh/llm/knowledge/wiki/swedroe-evidence-investing.md`
- Issue #100: https://github.com/JohnGavin/historical/issues/100
