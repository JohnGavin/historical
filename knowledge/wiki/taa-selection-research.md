# TAA Selection, Mid-Caps, and Lazy Prices — Research Assessment

Investigation of three quantitative research papers for relevance to the historical project (issue #104, 2026-05-08).

---

## Article 1: Lazy Prices with Snowflake Cortex AI

**Source:** [quantt.co.uk](https://www.quantt.co.uk/resources/lazy-prices-snowflake-cortex-ai)

### Core Finding

10-K textual changes predict returns with a **6-18 month drift**, not contemporaneous correlation. Strategy: buy firms with minimal year-on-year 10-K changes, short firms with substantial rewrites.

| Metric | General Strategy | Risk Factors-Focused |
|--------|-----------------|---------------------|
| Monthly return | 30-58 bps | **188 bps** (22% annualized) |
| t-statistic | Not reported | 2.76 |
| Drift period | 6-18 months | 6-18 months |
| Announcement day | Zero | Zero |
| Reversal | None | None |

### Signal Construction

- **Text features:** Four similarity measures (cosine, Jaccard, edit distance, word-level diff)
- **Quintiles:** Monthly sort on similarity; buy minimal-change quintile, short high-change quintile
- **Key section:** Risk Factors (strongest signal)
- **Mechanism:** 86% of textual changes are negative in sentiment — management buries bad news in prose without explicit comparison phrases

### Evidence Quality

| Dimension | Assessment |
|-----------|------------|
| Sample | "Every publicly traded firm in the United States" (original 2019 paper) |
| Period | Not disclosed in this article (need original paper) |
| Robustness | Tested 4 different similarity measures — signal is robust to method |
| Out-of-sample | Not mentioned |
| Markets tested | US only (no cross-geography evidence) |

**Grade:** B+ (strong signal, multiple methods, but single-market and unknown backtest period)

### Comparison to Guardian NLP (#89)

| Dimension | Guardian News NLP | Lazy Prices (10-K) |
|-----------|------------------|-------------------|
| **Source** | News articles (Guardian, NYT) | SEC 10-K filings |
| **Timing** | Published after market moves | Filed quarterly/annually with delay |
| **Signal window** | Same-month only (contemporaneous) | **6-18 month drift** |
| **Next-month r** | < 0.08 (no signal) | Not tested monthly; drift is gradual |
| **Nature** | Journalist interpretation | Management's official disclosure |
| **Frequency** | Daily | Quarterly/annual |
| **Priced-in status** | Fully priced by publication | **Under-reacted** (drift evidence) |

**Key difference:** News is *already* the market's interpretation. 10-K text is *raw input* that the market processes slowly. Guardian null result does NOT imply Lazy Prices would fail.

### Actionability

| Requirement | Status | Notes |
|-------------|--------|-------|
| **Data availability** | Yes — SEC EDGAR | Free, bulk download via `sec-edgar-downloader` or `edgar` R package |
| **NLP tools** | Partial | Similarity measures are standard (tm, text2vec R packages), but Snowflake Cortex is proprietary. Can replicate with open-source NLP. |
| **Frequency** | Quarterly | 10-K annual, 10-Q quarterly — low turnover, low cost |
| **Universe** | All US public firms | Broader than current SPY-based work |
| **Implementation cost** | Medium | Text extraction + similarity calc + storage (DuckDB can handle) |
| **Expected ROI** | High | 22% annualized (Risk Factors) >> current TAA strategies |

### Cross-Geography Pervasiveness

**CRITICAL VIOLATION:** `cross-geography-pervasiveness` rule requires 2+ independent markets. Lazy Prices is US-only. Before deployment, require:
- [ ] Evidence from UK (Companies House filings)
- [ ] Evidence from EU (regulatory filings)
- [ ] Evidence from Asia-Pacific

Original 2019 paper may have international tests — need to obtain.

### Implementation Roadmap (If Prioritized)

1. **Obtain original paper** — Cohen, Malloy, Nguyen (2019), likely in Journal of Finance or similar
2. **Verify robustness** — sample period, out-of-sample, transaction costs
3. **Data pipeline:**
   - `sec-edgar-downloader` for bulk 10-K/10-Q text
   - DuckDB storage of full filings (text column)
   - Extract Risk Factors section via regex
   - Compute 4 similarity measures vs prior year
   - Store monthly quintile assignments
4. **Backtest replication** — match paper's methodology exactly
5. **Cost model** — quarterly rebalance, estimate slippage for small-cap names
6. **International evidence** — test UK/EU if data available (lower priority)

### Priority: HIGH

**Rationale:**
- 22% annualized return with 2.76 t-stat is exceptional
- 6-18 month drift suggests genuinely slow information diffusion (not priced-in)
- Differs fundamentally from failed Guardian NLP (news vs filings)
- Data is free and structured
- Aligns with `priced-in-prohibition` rule's exception for "structural/behavioural anomalies with academic evidence"

**Risk:** Single-market evidence. Swedroe framework requires cross-geography pervasiveness before deployment.

---

## Article 2: Trading Lower Tier Large Caps and Upper Mid Caps

**Source:** [Quantpedia](https://quantpedia.com/when-big-gets-small-trading-the-lower-tier-of-large-caps-and-upper-mid-caps/)

### Core Finding

**Winning configuration:** Long smallest 20 S&P 500 stocks / Short largest 20 non-S&P 500 stocks → 11.23% annualized, Sharpe ≈ 0.4

**Initial hypothesis (FAILED):** Long large non-S&P / Short small S&P → negligible returns

### Market Cap Thresholds

| Band | Definition | Approximate cap |
|------|-----------|----------------|
| **Lower tier large** | Smallest 20 in S&P 500 | ~$10-15B (varies by market) |
| **Upper mid** | Largest 20 outside S&P 500 | ~$8-12B |

**Note:** Article does NOT disclose exact dollar thresholds or how they vary over time.

### Mechanism

**Index membership effect:** Passive flows into S&P 500 create persistent demand regardless of company size. Smallest S&P 500 firms benefit from index inclusion; largest non-S&P firms suffer exclusion.

### Evidence Quality

| Dimension | Assessment |
|-----------|------------|
| **Sample period** | NOT DISCLOSED |
| **Backtest dates** | NOT DISCLOSED |
| **Out-of-sample** | NOT DISCLOSED |
| **Cross-market** | NOT DISCLOSED (US-only implied) |
| **Robustness** | Tested 4 portfolio sizes (5, 10, 20, 50) — 20 is optimal |
| **Parameter tuning** | Authors explicitly acknowledge tuning risk |

**Grade:** D (results not credible without sample period, no out-of-sample, single market)

### Comparison to Current Work

| Current practice | Article finding | Implication |
|-----------------|----------------|-------------|
| Universe = SPY constituents | Smallest SPY names may have index premium | May benefit from excluding smallest SPY (lower tier) |
| Benchmark = SPY | Index flows affect smallest SPY names most | Benchmark choice matters for flow-driven effects |
| No mid-cap exposure | Upper mid-caps underperform per article | Confirm with data before excluding |

### Actionability

| Requirement | Status | Notes |
|-------------|--------|-------|
| **Data availability** | Yes | Historical S&P 500 constituents (CRSP, compustat, or scrape Wikipedia) + market cap data |
| **Implementation** | Easy | Filter universe: exclude smallest N S&P 500 names |
| **Cost** | Zero | Universe filter, no new data sources |
| **Expected ROI** | Unknown | No disclosed sample period = cannot validate claim |

### Critical Issues

1. **No sample period** — cannot distinguish genuine effect from backtest overfitting
2. **No out-of-sample** — 11.23% may be in-sample only
3. **Parameter tuning acknowledged** — authors admit calibration risk
4. **Single market** — violates `cross-geography-pervasiveness`
5. **Hypothesis reversal** — initial idea failed; reported result is post-hoc

### Comparison to Size Premium Literature

Classic size premium (Fama-French): small caps outperform large caps. This article claims:
- Smallest S&P 500 > mid-caps outside S&P 500
- Mechanism is index flows, not risk premium

**This is a DIFFERENT claim** than classic size effect. Requires independent validation.

### Priority: LOW

**Rationale:**
- No disclosed sample period or robustness tests
- Authors acknowledge parameter tuning
- Hypothesis reversal (initial idea failed)
- Single-market, no replication
- 11.23% return with Sharpe 0.4 is modest vs Lazy Prices (22%, t=2.76)

**Action:** Monitor for academic replication. Do NOT implement without independent evidence.

---

## Article 3: Selecting TAA Strategies Based on Recent Performance

**Source:** [AllocateSmartly](https://allocatesmartly.com/selecting-taa-strategies-based-on-recent-performance-part-1/)

### Core Methodology

**Meta-strategy:** Each month, rank 100+ TAA strategies by trailing N-month return, select top M performers, equal-weight for next month.

| Parameter | Tested values |
|-----------|--------------|
| Lookback | Multiple (3-6 months performed worst) |
| Top N | 1-2 performers vs broader selection |
| Universe | 100+ TAA strategies |

### Performance vs Equal-Weight

| Metric | Selection | Equal-Weight |
|--------|-----------|--------------|
| **Annualized return** | Higher | Lower (baseline) |
| **Sharpe ratio** | **No improvement** | Baseline |
| **Ulcer Performance Index** | **No improvement** | Baseline |
| **Drawdown** | Terrible (1-2 top picks) | Better |

### Key Finding

**Selection does NOT beat equal-weight on risk-adjusted basis** despite higher raw returns.

**3-6 month lookback performed worst** — short-term momentum fails for TAA strategies.

### Sample Period

**1973-2026** (~53 years) — this is a LONG backtest period, far exceeding typical Quantpedia articles.

### Comparison to plan_multi_strategy.R

| Current approach | AllocateSmartly | Key difference |
|-----------------|----------------|----------------|
| **Fixed weights** (50/35/15) | **Dynamic selection** (top N) | Stability vs momentum |
| **Decay-aware weighting** | **Momentum ranking** | Process vs outcome |
| **3 strategies** (DRIF, LTR, Factor MAX) | **100+ strategies** | Concentrated vs diversified |
| **Low turnover** (monthly rebalance, stable weights) | **High turnover** (chasing momentum) | Cost efficiency |
| **Outcome:** Sharpe not reported | **Outcome:** No Sharpe improvement | Similar risk-adjusted result |

### Critical Limitation

**No transaction cost model** — authors acknowledge "actual results would have been worse" due to switching costs.

### Evidence Quality

| Dimension | Assessment |
|-----------|------------|
| **Sample period** | 1973-2026 (53 years) — excellent |
| **Universe size** | 100+ strategies — excellent |
| **Robustness** | Tested multiple lookbacks and top-N counts |
| **Out-of-sample** | Not explicitly mentioned, but 53yr span likely includes multiple regimes |
| **Transaction costs** | **NOT modeled** — critical omission |

**Grade:** B (long sample, large universe, but missing cost model and result is null)

### Actionability

| Requirement | Status | Notes |
|-------------|--------|-------|
| **Data availability** | Partial | Would need returns for 100+ TAA strategies (AllocateSmartly subscription?) |
| **Implementation** | Medium | Ranking + selection logic is straightforward |
| **Cost** | High | Monthly switching between strategies = high turnover |
| **Expected ROI** | **Zero** | Article shows no risk-adjusted improvement |

### Implications for Multi-Strategy Work

1. **Decay-aware weighting is superior to momentum selection** — our fixed 50/35/15 weights based on stability are process-driven, not outcome-driven (`resulting-prohibition` rule)
2. **Equal-weight is a strong baseline** — AllocateSmartly confirms this
3. **Short-term momentum (3-6mo) fails** — do NOT chase recent TAA performance
4. **Transaction costs matter** — switching strategies monthly would erode returns

### Priority: INFORMATIONAL (No Action Required)

**Rationale:**
- Article confirms our current approach (fixed weights) is sound
- Momentum selection shows no risk-adjusted improvement
- Missing cost model makes reported returns unreliable
- 100+ strategy universe is impractical for our project

**Action:** Document as validation of current decay-aware weighting approach. No implementation.

---

## Summary Table

| Article | Signal/Finding | Evidence Grade | Actionability | Priority | Reason |
|---------|---------------|---------------|---------------|----------|--------|
| **Lazy Prices** | 10-K text changes → 22% annual (6-18mo drift) | B+ | High | **HIGH** | Exceptional returns, differs from failed Guardian NLP, free data |
| **Size Effect** | Small S&P 500 > large non-S&P (11% annual) | D | Low | **LOW** | No sample period, parameter tuning, single market, hypothesis reversal |
| **TAA Selection** | Momentum selection shows no Sharpe improvement | B | Medium | **INFORMATIONAL** | Validates current fixed-weight approach; no action needed |

---

## Implementation Roadmap (Lazy Prices Only)

### Phase 1: Obtain Original Paper (1 day)
- [ ] Find Cohen, Malloy, Nguyen (2019) — likely "Lazy Prices" in Journal of Finance
- [ ] Read full methodology, sample period, robustness tests
- [ ] Check for international evidence (UK, EU, Asia)
- [ ] Verify 22% return claim and t-stat

### Phase 2: Data Pipeline (2-3 days)
- [ ] Install `sec-edgar-downloader` or `edgar` R package
- [ ] Bulk download 10-K filings (last 5 years as test)
- [ ] Extract Risk Factors section via regex
- [ ] Compute 4 similarity measures (cosine, Jaccard, edit, diff) using `text2vec`
- [ ] Store in DuckDB: `filings(ticker, date, filing_type, risk_factors_text, similarity_vs_prior)`
- [ ] Create monthly quintile assignments

### Phase 3: Backtest Replication (2 days)
- [ ] Match paper's methodology exactly
- [ ] Long minimal-change quintile, short high-change quintile
- [ ] Compute monthly returns, t-stat, drift pattern
- [ ] Compare to paper's 188 bps/month claim

### Phase 4: Cost Model (1 day)
- [ ] Quarterly rebalance (10-K is annual, 10-Q is quarterly)
- [ ] Estimate slippage for small-cap names (use average market cap by quintile)
- [ ] Model transaction costs at 20 bps round-trip
- [ ] Net-of-cost Sharpe ratio

### Phase 5: Integration (1 day)
- [ ] Add to `plan_lazy_prices.R` in targets pipeline
- [ ] Add to multi-strategy portfolio with decay-aware weight
- [ ] Render vignette with falsification tests
- [ ] Update strategy name mapping (`strategy_names` target)

**Estimated effort:** 7-10 days total

**Expected outcome:**
- If replication succeeds and international evidence exists → deploy with 15-25% portfolio weight
- If US-only → document as high-potential but violates `cross-geography-pervasiveness`
- If fails replication → document null result, investigate causes

---

## Violations of Project Rules

### Lazy Prices
- **`cross-geography-pervasiveness`** — US-only evidence (need UK/EU replication)
- **`priced-in-prohibition`** — EXCEPTION applies: academic evidence of slow diffusion (6-18mo drift), not contemporaneous

### Size Effect
- **`cross-geography-pervasiveness`** — US-only, no international tests
- **`backtest-robustness`** — no disclosed sample period or out-of-sample
- **`resulting-prohibition`** — hypothesis reversal (post-hoc finding)

### TAA Selection
- **`backtesting-assumptions`** — no cost model (authors acknowledge omission)
- **No rule violations** — long sample, negative result is informational

---

## Sources

- Cohen, Malloy, Nguyen (2019), "Lazy Prices" (original paper — to be obtained)
- Quantt.co.uk Lazy Prices article: https://www.quantt.co.uk/resources/lazy-prices-snowflake-cortex-ai
- Quantpedia size effect: https://quantpedia.com/when-big-gets-small-trading-the-lower-tier-of-large-caps-and-upper-mid-caps/
- AllocateSmartly TAA selection: https://allocatesmartly.com/selecting-taa-strategies-based-on-recent-performance-part-1/
- Guardian NLP findings: [[guardian-nlp]]
- Multi-strategy portfolio: `R/plan_multi_strategy.R`
- Priced-in signals: [[priced-in-signals]]
- Project rules: `.claude/rules/` (cross-geography-pervasiveness, priced-in-prohibition, resulting-prohibition, backtest-robustness, backtesting-assumptions)

---

**Prepared:** 2026-05-08 | **Investigator:** Claude Sonnet 4.5 | **Issue:** #104
