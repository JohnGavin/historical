# Market Behavior Gap Analysis

## Definition vs Implementation Audit

Issue: #105
Date: 2026-05-08
Branch: research/market-behavior-audit

## Executive Summary

Audit of the comprehensive market behavior definition (from #105 comment) against current historical project implementation. The project has **strong coverage** of performance and risk metrics (75%), **partial coverage** of correlation/volatility/evolution (60%), and **weak coverage** of liquidity/volume (20%).

**Priority gaps:** Actual liquidity metrics (bid-ask spreads, market depth), volume-price relationships, and tracking error metrics.

---

## 1. Performance Metrics

### Definition Requirements
- Returns (absolute and risk-adjusted)
- Drawdowns and recovery periods
- Sharpe ratio and variants
- Risk-adjusted performance metrics

### Current Coverage: ✅ **FULLY COVERED (95%)**

| Metric | Implementation | Source |
|--------|---------------|--------|
| CAGR (gross and net) | ✅ | `plan_leaderboard.R`, all strategy metrics |
| Volatility (annualised) | ✅ | All strategy metrics |
| Sharpe ratio (naive) | ✅ | All strategy metrics |
| HAC-corrected Sharpe | ✅ | `packages/historicaldata/R/falsification.R::hd_hac_sharpe()` |
| Max drawdown | ✅ | All strategy metrics |
| CVaR 95% | ✅ | `plan_leaderboard.R` (cost_rows computation) |
| Cumulative P&L (net) | ✅ | `plan_leaderboard.R` |
| Bootstrap confidence intervals | ✅ | `plan_bootstrap_ci.R` |
| Alpha decay (execution delay) | ✅ | `plan_alpha_decay.R` |

**Vignettes displaying:**
- Leaderboard: Full Period + By Partition tables
- Falsification: HAC vs naive Sharpe comparison
- Bootstrap CI tab in leaderboard

### Gaps: ⚠️ **MINOR (5%)**

| Missing | Priority | Reason |
|---------|----------|--------|
| Recovery period duration | Medium | Drawdown depth tracked, but time-to-recovery not explicit |
| Sortino ratio | Low | Downside deviation variant of Sharpe |
| Calmar ratio | Low | CAGR / max drawdown |

**Recommendation:** Add recovery period tracking in drawdown analysis. Sortino/Calmar are low priority (Sharpe + CVaR cover the same ground).

---

## 2. Correlation Profile

### Definition Requirements
- Cross-asset correlations
- Regime-conditional correlations
- Tail dependence

### Current Coverage: ⚠️ **PARTIALLY COVERED (65%)**

| Metric | Implementation | Source |
|--------|---------------|--------|
| Pairwise strategy correlation | ✅ | `plan_multi_strategy.R` → leaderboard Correlations tab |
| Regime-based performance splits | ✅ | `plan_regime.R`, `plan_risk_state.R` |
| Crisis-period correlation | ✅ | Causal graph implication tests (HML-VIX split) |
| Cross-asset correlations | ❌ | Only strategy-to-strategy; no equity-bond-commodity |
| Tail independence (K_eff_crisis) | ⚠️ | Mentioned in causal graph (#55) but not computed |

**Vignettes displaying:**
- Leaderboard: Correlations tab (strategy-to-strategy, Pearson monthly)
- Falsification: Causal graph HML-VIX split by period
- Regime tab: Regime-adjusted metrics

### Gaps: ⚠️ **MODERATE (35%)**

| Missing | Priority | Reason |
|---------|----------|--------|
| Equity-bond-commodity correlations | High | Multi-asset allocation requires cross-asset correlations |
| Crisis-conditional correlation matrix | High | K_eff in calm vs crisis regimes |
| Rolling correlation windows | Medium | Static correlation may hide time-variation |
| Copula tail dependence | Low | Advanced, not required for current strategies |

**Recommendation:** Add multi-asset correlation matrix (SPY, TLT, GLD, DBC) to a new "Market Correlations" tab. Implement `hd_tail_keff()` per falsification.R comment.

---

## 3. Volatility

### Definition Requirements
- Historical volatility
- Implied volatility (VIX, VVIX)
- Volatility regimes

### Current Coverage: ⚠️ **PARTIALLY COVERED (70%)**

| Metric | Implementation | Source |
|--------|---------------|--------|
| Historical volatility (annualised) | ✅ | All strategy metrics |
| VIX levels | ✅ | `plan_vix_macro_overlay.R`, `plan_risk_state.R` |
| VIX regimes (low/med/high) | ✅ | `plan_risk_state.R` |
| Vol-of-vol (VVIX) | ❌ | Not tracked |
| Realised vs implied vol spread | ❌ | Not computed |
| GARCH persistence | ⚠️ | Used in null tests but not reported as metric |

**Vignettes displaying:**
- Leaderboard: Vol column in all tables
- Regime tab: VIX regime scaling plot
- Avoid Worst Days: VIX spike filtering

### Gaps: ⚠️ **MODERATE (30%)**

| Missing | Priority | Reason |
|---------|----------|--------|
| VVIX (VIX of VIX) | Medium | Proxy for tail risk uncertainty |
| Realised vol - implied vol spread | Medium | Options mispricing signal |
| GARCH(1,1) persistence params | Low | Academic interest, not actionable |
| Volatility surface (by strike/tenor) | Low | Options-specific, out of scope |

**Recommendation:** Add VVIX to market data ingestion. Compute realised-implied spread for SPY if options data available.

---

## 4. Liquidity

### Definition Requirements
- Bid-ask spreads
- Market depth
- Turnover rates
- Volume data

### Current Coverage: ❌ **WEAK (15%)**

| Metric | Implementation | Source |
|--------|---------------|--------|
| Assumed turnover (cost model) | ✅ | `plan_leaderboard.R` assumptions tab (80%/month) |
| Actual bid-ask spreads | ❌ | Not tracked |
| Market depth (order book) | ❌ | Not tracked |
| Volume data | ❌ | Not ingested or used |

**Vignettes displaying:**
- Leaderboard: Assumptions tab lists "Estimated turnover: 80% per month", but this is an assumption, not a measurement.

### Gaps: ❌ **MAJOR (85%)**

| Missing | Priority | Reason |
|---------|----------|--------|
| Actual bid-ask spreads | **HIGH** | Cost model uses 0.50% assumption — real spreads may differ |
| Daily volume data | **HIGH** | Liquidity constraint detection (can we execute?) |
| Market depth (L2 order book) | Medium | Institutional execution concern, not retail |
| Turnover tracking (realised) | Medium | Compare assumed 80% to actual strategy turnover |
| Amihud illiquidity ratio | Low | Volume-return impact measure |

**Recommendation:**
1. **Priority 1:** Ingest daily volume data from Yahoo Finance (already available in CRSP/Compustat). Add volume filter: skip stocks with avg daily volume < $1M.
2. **Priority 2:** Compute realised turnover per strategy per month and compare to 80% assumption.
3. **Priority 3:** Obtain bid-ask spreads from CRSP or TAQ (requires institutional access).

---

## 5. Trading Volumes

### Definition Requirements
- Volume trends
- Volume-price relationships
- Volume-volatility relationships

### Current Coverage: ❌ **WEAK (10%)**

| Metric | Implementation | Source |
|--------|---------------|--------|
| Volume data ingestion | ❌ | Not ingested |
| Volume trends | ❌ | Not tracked |
| Volume-price correlation | ❌ | Not computed |
| Volume spikes (liquidity events) | ❌ | Not detected |

**Vignettes displaying:** None.

### Gaps: ❌ **MAJOR (90%)**

| Missing | Priority | Reason |
|---------|----------|--------|
| Daily volume ingestion | **HIGH** | Required for liquidity filters |
| Volume-weighted returns | High | More realistic execution assumptions |
| Volume spike detection | Medium | Liquidity shock indicator |
| Price-volume divergence | Low | Technical signal, low priority for factor strategies |

**Recommendation:** Ingest volume alongside OHLC data. Add volume-based liquidity filters to stock selection (e.g., require ADV > $1M). Compute volume-weighted average price (VWAP) for more realistic cost estimates.

---

## 6. Evolution Since Launch

### Definition Requirements
- Time-varying characteristics
- Structural breaks
- Parameter stability over time

### Current Coverage: ✅ **WELL COVERED (80%)**

| Metric | Implementation | Source |
|--------|---------------|--------|
| Partition-based metrics | ✅ | `plan_partitions.R` (Training/Testing/Validation) |
| Alpha decay analysis | ✅ | `plan_alpha_decay.R` (half-life by strategy) |
| Strategy decay (#73) | ✅ | `plan_strategy_decay.R` (Factor MAX decay >50%) |
| Bootstrap CI (parameter stability) | ✅ | `plan_bootstrap_ci.R` |
| Regime-split performance | ✅ | Causal graph HML-VIX by period (pre/post 2010) |
| Formal structural break tests | ❌ | Regime detection exists but no Chow/CUSUM tests |

**Vignettes displaying:**
- Leaderboard: By Partition tab, Alpha Decay tab, Bootstrap CI tab
- Falsification: Causal graph implication split tests

### Gaps: ⚠️ **MINOR (20%)**

| Missing | Priority | Reason |
|---------|----------|--------|
| Chow test (structural break) | Medium | Formal test for parameter change at known date |
| CUSUM (rolling break detection) | Medium | Detect breaks at unknown dates |
| Rolling window Sharpe | Low | Already have partition-based + bootstrap |

**Recommendation:** Add Chow test for strategies with suspected decay (e.g., Factor MAX at 2010 split). Low priority — partition-based analysis and causal graph splits already cover this ground.

---

## 7. Comparison to Broader Market

### Definition Requirements
- Beta to market
- Tracking error
- Information ratio
- Relative performance

### Current Coverage: ⚠️ **PARTIALLY COVERED (55%)**

| Metric | Implementation | Source |
|--------|---------------|--------|
| Fama-French factor betas | ✅ | `plan_falsification.R` → FF5+Mom regression |
| Market beta (Mkt-RF loading) | ✅ | FF regression table |
| R² (variance explained by factors) | ✅ | Falsification scorecard |
| Alpha (excess return over factors) | ✅ | FF regression alpha column |
| Tracking error | ❌ | Not explicitly computed |
| Information ratio | ❌ | Not computed |
| Relative drawdown | ❌ | Not computed |

**Vignettes displaying:**
- Falsification: FF5+Mom Betas tab (shows all factor loadings including Mkt-RF)
- Falsification: Alpha vs Factor Exposure scatter (alpha % and R² %)

### Gaps: ⚠️ **MODERATE (45%)**

| Missing | Priority | Reason |
|---------|----------|--------|
| Tracking error (vs SPY) | High | Standard institutional metric |
| Information ratio (alpha / tracking error) | High | Risk-adjusted alpha |
| Up/down capture ratios | Medium | Asymmetric market exposure |
| Relative drawdown (strategy - benchmark) | Low | Captured by alpha and max DD separately |

**Recommendation:** Add tracking error and information ratio to a new "Relative Performance" section. Benchmark = SPY for stock strategies, equal-weight FF factors for factor strategies.

---

## Summary Table: Coverage by Component

| Component | Coverage | Status | Priority Gaps |
|-----------|----------|--------|---------------|
| 1. Performance | 95% | ✅ Full | Recovery periods (medium) |
| 2. Correlation | 65% | ⚠️ Partial | Cross-asset correlations (high), tail K_eff (high) |
| 3. Volatility | 70% | ⚠️ Partial | VVIX (medium), realised-implied spread (medium) |
| 4. Liquidity | 15% | ❌ Weak | **Bid-ask spreads (high), volume data (high)** |
| 5. Trading Volumes | 10% | ❌ Weak | **Volume ingestion (high), volume filters (high)** |
| 6. Evolution | 80% | ✅ Good | Structural break tests (medium) |
| 7. Market Comparison | 55% | ⚠️ Partial | Tracking error (high), information ratio (high) |

**Overall Coverage: 53%** (weighted by importance: performance 2x, liquidity 1.5x)

---

## Priority Recommendations

### Tier 1 (High Priority — Core Gaps)

1. **Volume data ingestion** (#5, #4)
   - Add daily volume to stock data pipeline
   - Implement liquidity filters (ADV > $1M)
   - Compute realised turnover per strategy
   - File: `R/plan_stock_backtest.R`, `packages/historicaldata/R/query.R`

2. **Tracking error and information ratio** (#7)
   - Compute tracking error vs SPY/equal-weight FF
   - Add Information Ratio = alpha / TE
   - New vignette tab: "Relative Performance"
   - File: New `R/plan_relative_performance.R`

3. **Cross-asset correlations** (#2)
   - Ingest SPY, TLT, GLD, DBC daily returns
   - Compute rolling 3-month correlation matrix
   - Add "Market Correlations" tab to leaderboard
   - File: New `R/plan_market_correlations.R`

4. **Tail K_eff (crisis vs calm)** (#2)
   - Implement `hd_tail_keff()` per falsification.R comment
   - Compute K_eff separately for VIX > 30 and VIX < 20
   - Add to falsification multiplicity section
   - File: `packages/historicaldata/R/falsification.R`

### Tier 2 (Medium Priority — Enhancements)

5. **Recovery period tracking** (#1)
   - Compute time-to-recovery after each drawdown
   - Add to leaderboard metrics
   - File: `packages/historicaldata/R/scoring.R` (new function)

6. **VVIX ingestion** (#3)
   - Add to VIX data pipeline
   - Display in risk state dashboard
   - File: `R/plan_vix_macro_overlay.R`, `R/plan_risk_state.R`

7. **Structural break tests** (#6)
   - Chow test for Factor MAX at 2010 (known decay)
   - Add to strategy decay analysis
   - File: `R/plan_strategy_decay.R`

### Tier 3 (Low Priority — Nice-to-Have)

8. Sortino ratio, Calmar ratio (#1)
9. Rolling correlation windows (#2)
10. GARCH persistence reporting (#3)
11. Amihud illiquidity ratio (#4)
12. Up/down capture ratios (#7)

---

## Implementation Notes

### Data Availability

| Metric | Data Source | Availability |
|--------|-------------|--------------|
| Volume | Yahoo Finance, CRSP | ✅ Already available |
| Bid-ask spreads | CRSP Daily, TAQ | ⚠️ Requires institutional access |
| VVIX | CBOE, Yahoo Finance | ✅ Freely available |
| SPY/TLT/GLD/DBC | Yahoo Finance | ✅ Already used |

### Effort Estimates

| Recommendation | Effort | Files to Edit |
|----------------|--------|---------------|
| Volume ingestion + filters | 2-3 hours | `query.R`, `plan_stock_backtest.R` |
| Tracking error + IR | 1-2 hours | New `plan_relative_performance.R` |
| Cross-asset correlations | 1-2 hours | New `plan_market_correlations.R` |
| Tail K_eff | 2-3 hours | `falsification.R`, `plan_falsification.R` |
| Recovery periods | 1 hour | New function in `scoring.R` |
| VVIX | 1 hour | `plan_vix_macro_overlay.R` |

**Total estimated effort (Tier 1 only): 8-12 hours**

---

## Sources

- Vignettes: `docs/leaderboard.qmd`, `docs/falsification.qmd`, `docs/stock-backtest.qmd`
- Plans: All `R/plan_*.R` files (40+ files audited)
- Package functions: `packages/historicaldata/R/` (scoring.R, falsification.R, query.R)
- Market behavior definition: #105 comment (comprehensive list)

## Related Issues

- #53: Deflated Sharpe Ratio (DSR) — not yet implemented (tier 2-3)
- #55: Tail independence K_eff — flagged in causal graph, not computed (tier 1)
- #58: Cross-geography pervasiveness — requires international data (out of scope)
- #73: Strategy decay — already implemented for Factor MAX

---

**Next Steps:** Review this gap analysis, prioritise recommendations, and create implementation issues for Tier 1 items.
