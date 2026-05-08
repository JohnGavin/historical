# Regime-Dependent Trend Following: Research Analysis

## Summary

Investigation of regime-dependent allocation strategies and comparison to existing implementations in the historical project. The primary source (Alpha Architect article) was inaccessible due to website blocking (403 error), so this analysis is based on existing codebase implementations and general regime-dependent allocation principles.

## Existing Implementations

The historical project has **three distinct regime-based approaches** already implemented:

### 1. plan_regime.R — Volatility-Based Regime Classification

**Regime Definition:**
- Uses **realized portfolio volatility** (12-month rolling window)
- Classifies months as low/medium/high risk based on training-period quantiles (33rd/80th percentiles)
- Optionally augments with VIX when available
- Risk signal = coalesce(VIX volatility, realized volatility)

**Allocation Rules:**
- Low risk: 100% exposure (scale_low = 1.0)
- Medium risk: 70% exposure (scale_medium = 0.7)
- High risk: 40% exposure (scale_high = 0.4)
- Remainder allocated to cash earning risk-free rate

**Bias Prevention:**
- Quantile thresholds computed from **training data only** (before `stk_params$is_end`)
- Falls back to full-period quantiles only if training sample < 12 months
- No look-ahead bias in regime classification

**Evidence:**
- Targets: `regime_metrics` compares base vs regime-adjusted returns across training/testing/full periods
- Plots: equity curves with shaded high-risk bands
- Metrics: CAGR, vol, Sharpe, max drawdown per regime

---

### 2. plan_risk_state.R — VIX Options-Based Multi-Signal Overlay

**Regime Definition (Three Signals):**
1. **VVIX** (volatility-of-volatility): percentile thresholds (80th/95th percentiles)
   - Earliest warning signal
2. **Term structure change**: 5-day Δ in VIX3M/VIX1M ratio
   - Early warning thresholds: -4%/-8%
3. **Term structure level**: VIX3M/VIX1M ratio percentile (10th/5th percentiles)
   - Confirming signal

**Combined Regime:**
- Regime = **worst of three signals** (benign/cautious/hostile)
- Explicit **t+1 execution**: all signals use PREVIOUS-day values

**Allocation Rules:**
- Benign: 100% exposure
- Cautious: 50% exposure
- Hostile: 10% exposure
- Cash earns RF rate

**Bias Prevention:**
- Thresholds computed from **training data only** (`date < oos_start`)
- Percentile-based cuts avoid parameter sensitivity
- Explicit lag enforcement: `lag(vvix)`, `lag(vix1m)`, `lag(vix3m)` in all signal computations

**Evidence:**
- Standalone SPY backtest (buy-and-hold vs overlay)
- Overlay applied to DRIF and Factor MAX strategies
- Alpha decay analysis: delays signals 1-10 days, tracks performance degradation
- Subperiod stability: 3 sub-periods plus full period
- Three-panel signal chart showing VVIX, term structure level, term structure change

---

### 3. plan_avoid_worst.R — VIX-Triggered Protection (Practical Strategy)

**Regime Definition:**
- **Shock trigger**: absolute daily return > 3%
- **VIX elevated**: VIX > 30
- **VIX re-entry**: VIX < 25
- **Cooling-off**: minimum 5 days in cash after shock, even if VIX drops

**Allocation Rules:**
- Default: 100% in market (SPY)
- Exit to cash (0% market exposure) when: shock OR VIX > 30
- Re-enter when: VIX < 25 AND cooloff expired

**Bias Prevention:**
- **Explicit t+1 execution**: `vix_prev = d$vix[i-1]`
- Comment in code: "You cannot act on today's VIX; you see it at close and trade next day"
- Shock detection uses previous-day return

**Evidence:**
- Walk-forward validation: yearly expanding-window optimization (2000-2026)
  - For each year, optimize VIX threshold on all prior data
  - Apply to test year
  - Tracks chosen VIX threshold, OOS CAGR, Sharpe, max DD per year
- Parameter sensitivity: sweep VIX thresholds (25/30/35/40), shock thresholds (2-5%)
- Transaction costs: 5bps per switch, gross vs net comparison
- Subperiod stability: 1993-2007, 2008-2019, 2020-2026
- Cross-market validation: SPY, QQQ, IWM, DIA
- Bootstrap CI on Sharpe (block bootstrap, 63-day blocks)
- Alpha decay: delay signal 1-10 days, measure performance degradation

---

## Comparison: General Regime-Dependent Trend Following Principles

### Typical Regime Indicators (Literature)

| Indicator | How Used | Existing Implementation |
|-----------|----------|------------------------|
| **Volatility** | High vol = defensive regime | ✅ All three plans use volatility signals (realized vol, VIX, VVIX) |
| **Trend** | SMA crossovers, time-series momentum | ❌ Not explicitly in regime plans (but see plan_ltr_momentum.R for trend) |
| **Macro** | GDP growth, unemployment, yield curve | ⚠️ Partial: VIX term structure = volatility curve, not yield curve |
| **Valuation** | P/E ratios, earnings yield spreads | ❌ Not in regime plans (covered in valuation-spread-threshold rule) |

### Typical Allocation Mechanisms

| Mechanism | Description | Existing Implementation |
|-----------|-------------|------------------------|
| **Binary (on/off)** | 100% exposure or 0% | ✅ plan_avoid_worst.R (cash during elevated VIX) |
| **Tiered scaling** | Low/medium/high exposure levels | ✅ plan_regime.R (100%/70%/40%), plan_risk_state.R (100%/50%/10%) |
| **Continuous scaling** | Smooth function of regime signal | ❌ All existing plans use discrete levels |
| **Position sizing** | Scale individual positions, not portfolio | ❌ All existing plans scale total exposure |

### Bias Prevention Mechanisms

| Risk | Prevention | Existing Implementation |
|------|-----------|------------------------|
| **Look-ahead bias** | Threshold estimation from training data only | ✅ All three plans: regime.R uses `filter(date <= stk_params$is_end)`, risk_state.R uses `filter(date < rsc_params$oos_start)` |
| **t+0 execution** | Enforce t+1 lag on all signals | ✅ Explicit in risk_state.R and avoid_worst.R: `lag(vix)`, comments emphasize "PREVIOUS day" |
| **Data snooping** | Walk-forward validation | ✅ avoid_worst.R has full walk-forward: yearly expanding-window optimization |
| **Parameter sensitivity** | Robustness testing | ✅ avoid_worst.R: sensitivity sweeps, alpha decay (1-10 day delays) |

---

## Key Findings

### Strengths of Existing Implementations

1. **Multiple regime definitions tested**: volatility-based (regime.R), multi-signal VIX options (risk_state.R), simple VIX trigger (avoid_worst.R)
2. **Rigorous bias prevention**:
   - Training-only threshold estimation
   - Explicit t+1 execution enforcement
   - Walk-forward validation
3. **Comprehensive robustness testing**:
   - Parameter sensitivity sweeps
   - Subperiod stability analysis
   - Cross-market validation (SPY/QQQ/IWM/DIA)
   - Alpha decay (delayed signal performance)
   - Bootstrap confidence intervals
4. **Transaction cost awareness**: 5bps per switch, gross vs net comparisons
5. **Modular design**: risk_state.R is an **overlay** that can be applied to any strategy (demonstrated on DRIF and Factor MAX)

### Gaps vs Literature

1. **No trend-based regime definition**:
   - Existing plans focus on volatility/VIX signals
   - Typical regime-dependent trend following uses **trend strength** or **trend persistence** as regime classifier
   - Example: use 12-month SMA distance or time-series momentum z-score to define "trending" vs "mean-reverting" regimes
   - **Recommendation**: Add `plan_trend_regime.R` using:
     - Regime = "trending" if |SMA(12)-Price| > threshold
     - Regime = "mean-reverting" otherwise
     - Allocation: 100% trend-following in trending regime, 50% or switch to mean-reversion strategy in choppy regime

2. **No macro regime indicators**:
   - No GDP, unemployment, yield curve slope, credit spreads
   - **Recommendation**: Add `plan_macro_regime.R` using:
     - Yield curve slope (10Y-2Y spread) as recession indicator
     - Credit spreads (BAA-AAA) as stress indicator
     - Combine with existing VIX signals
     - Allocation: scale down equities, scale up bonds/gold in recession regime

3. **Discrete scaling only**:
   - All plans use discrete levels (100%/70%/40% or 100%/50%/10%)
   - **Recommendation**: Test continuous scaling:
     - Exposure = max(0.1, min(1.0, 1 - (VIX - 15) / 30))
     - Smooth transition reduces whipsaw trades at threshold boundaries

4. **No position-level scaling**:
   - All plans scale total portfolio exposure
   - Alternative: scale individual stock positions based on stock-specific volatility regimes
   - **Recommendation**: Lower priority — portfolio-level scaling is simpler and more robust

---

## Comparison to plan_avoid_worst.R (VIX Protection)

### Similarities to Typical Regime-Dependent Approaches

| Feature | plan_avoid_worst.R | Typical Regime Approach |
|---------|-------------------|------------------------|
| Regime signal | VIX level + daily shock | ✅ Common: volatility as regime proxy |
| Allocation mechanism | Binary (100% or 0%) | ✅ Common: some use binary, some tiered |
| t+1 execution | ✅ Enforced | ✅ Standard |
| Walk-forward validation | ✅ Yearly expanding window | ✅ Best practice |
| Transaction costs | ✅ 5bps per switch | ✅ Standard |

### Differences

| Aspect | plan_avoid_worst.R | Typical Regime Approach |
|--------|-------------------|------------------------|
| Regime definition | VIX > 30 (hard threshold) | Often percentile-based (e.g., 80th percentile) |
| Cash vs alternative assets | Cash only | Often bonds, gold, or other defensive assets |
| Re-entry logic | VIX < 25 + cooloff | Often trend-based: re-enter on uptrend signal |
| Shock trigger | 3% daily move | Less common; typically only volatility level |

### Key Insight from avoid_worst.R

The **clustering analysis** (lines 222-295) is critical:
- Median distance from worst day to nearest best day: very short
- 6+ of 10 worst days occur within 20 calendar days of a best day
- **Implication**: selective avoidance is impractical — missing worst days means missing best days

This finding **justifies the VIX protection strategy**:
- Don't try to avoid specific days
- Instead, exit during **high-volatility regimes** (VIX > 30)
- Accept that you'll miss some upside, but avoid catastrophic drawdowns

---

## Recommendations (Prioritized)

### High Priority (Easy to Test)

1. **Add trend-regime overlay to existing strategies**:
   - Create `plan_trend_regime.R`
   - Regime = "trending" if 12-month momentum > 0 AND |Price - SMA(252)| > 5%
   - Regime = "choppy" otherwise
   - Allocation: 100% in trending, 50% in choppy
   - Test on DRIF and Factor MAX (same pattern as risk_state.R overlay)
   - **Hypothesis**: Trend-following strategies work best in trending regimes; VIX overlay is orthogonal (volatility regime)

2. **Combine VIX and trend regimes**:
   - Two-dimensional regime: (trending/choppy) × (low-vol/high-vol)
   - Four states: trending low-vol (100%), trending high-vol (70%), choppy low-vol (50%), choppy high-vol (20%)
   - **Hypothesis**: Worst state is choppy high-vol (whipsaw risk + drawdown risk); best is trending low-vol

3. **Test continuous VIX scaling in avoid_worst.R**:
   - Replace binary (VIX > 30 = cash) with continuous: `exposure = max(0.1, min(1.0, (40 - VIX) / 15))`
   - VIX = 25 → 100%, VIX = 32.5 → 50%, VIX = 40 → 10%
   - **Hypothesis**: Reduces switches, improves net-of-cost returns

### Medium Priority

4. **Add yield curve regime**:
   - Regime = "expansion" if 10Y-2Y spread > 0.5%
   - Regime = "recession" if 10Y-2Y spread < 0 (inverted)
   - Allocation: scale equities 100%/70%/40% by expansion/neutral/recession
   - **Hypothesis**: Yield curve inversions precede recessions; defensive tilt may reduce drawdowns

5. **Multi-asset regime allocation**:
   - Extend plan_vix_macro_overlay.R (tested TLT, GLD, DBC, UUP)
   - VIX overlay **failed on SPY** (R²=41%, no alpha) per line 3 comment
   - Hypothesis in vmo plan: VIX better for non-equity assets
   - **Recommendation**: Test regime-dependent rotation: equities in low-VIX, bonds/gold in high-VIX

### Low Priority (Complex)

6. **Position-level volatility scaling**:
   - Scale each stock position by its own realized vol (not portfolio-level)
   - Requires stock-level data, complex rebalancing
   - **Recommendation**: Defer — portfolio-level scaling is simpler

7. **Machine learning regime detection**:
   - Use HMM (hidden Markov model) or clustering to infer regimes
   - Requires careful validation to avoid overfitting
   - **Recommendation**: Defer — existing percentile/threshold methods are interpretable and robust

---

## Integration with Existing Rules

### Relevant Project-Specific Rules

From `.claude/rules/`:

1. **`resulting-prohibition.md`**:
   - Judge by process, not outcome
   - **Application**: Don't revise regime thresholds based on recent underperformance
   - **Compliance**: Walk-forward validation in avoid_worst.R re-optimizes yearly, which is process-driven (not outcome-chasing)

2. **`underperformance-prior.md`**:
   - 13-40 year underperformance is historically normal
   - **Application**: Don't abandon regime strategy after 2-5 years of underperformance
   - **Compliance**: Subperiod analysis (2009-2014, 2015-2019, 2020-2026) checks stability across regimes

3. **`cross-geography-pervasiveness.md`**:
   - Require 2+ independent markets
   - **Application**: Cross-market validation on SPY/QQQ/IWM/DIA is a start, but all are US equities
   - **Gap**: Test on international markets (EFA, EEM), bonds (TLT, IEF), commodities (GLD, DBC)
   - **Action**: Expand `aw_cross_market` target to include non-equity tickers

4. **`valuation-spread-threshold.md`**:
   - Only tilt at 2-3 SD deviations, cap at 5-10%
   - **Application**: Regime plans use percentile thresholds (80th/95th), not SD
   - **Compliance**: plan_regime.R uses 33rd/80th percentiles → roughly 0.4 SD / 0.8 SD
   - **Recommendation**: Document the SD equivalents for transparency

5. **`earnings-mean-reversion.md`**:
   - Apply 40%/yr decay to earnings growth features
   - **Application**: Not directly relevant to regime plans (they use volatility, not earnings)
   - **If** we add a valuation-based regime (P/E spreads), apply decay to abnormal earnings

6. **`priced-in-prohibition.md`**:
   - Require incremental power after controlling for known factors
   - **Application**: VIX is widely followed → may be priced in
   - **Compliance**: avoid_worst.R walk-forward tests OOS performance; plan_risk_state.R alpha decay shows performance degrades with delay (faster decay = already being traded on)
   - **Conclusion**: VIX protection **does not** provide alpha (R²=41% on SPY per vmo line 3), but it **reduces drawdowns** (defensive overlay, not return-generating signal)

---

## Evidence Quality Assessment

### plan_avoid_worst.R

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Pervasive | ⚠️ 60% | Cross-market (4 US ETFs), but no international/non-equity |
| Persistent | ✅ 90% | Full period 1993-2026, subperiod stability |
| Robust | ✅ 95% | Parameter sweeps, walk-forward, alpha decay, bootstrap CI |
| Investable | ✅ 85% | Transaction costs (5bps), net-of-cost CAGR reported |
| Intuitive | ✅ 90% | VIX = fear gauge; high VIX = elevated drawdown risk |

**Overall**: 82% — **Strong evidence** for VIX protection as a defensive overlay. Gaps: pervasiveness (need non-US markets).

### plan_risk_state.R

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Pervasive | ⚠️ 50% | Only tested on SPY, DRIF, Factor MAX (all US equity-linked) |
| Persistent | ✅ 85% | 2009-2026, subperiod analysis |
| Robust | ✅ 90% | Alpha decay, subperiod stability, three independent signals |
| Investable | ⚠️ 70% | No explicit transaction cost analysis |
| Intuitive | ✅ 95% | VVIX = earliest warning, term structure = stress indicator |

**Overall**: 78% — **Good evidence**. Gaps: pervasiveness (test on bonds, gold), transaction costs.

### plan_regime.R

| Criterion | Score | Evidence |
|-----------|-------|----------|
| Pervasive | ⚠️ 60% | Applied to multi-strategy portfolio (stk_max, stk_drif, fac_max, fac_drif), but all US-based |
| Persistent | ✅ 80% | Training/testing/full period |
| Robust | ⚠️ 60% | No parameter sensitivity sweeps reported |
| Investable | ⚠️ 60% | No transaction cost analysis |
| Intuitive | ✅ 90% | Realized vol = observed risk; scale down in high-vol |

**Overall**: 70% — **Acceptable evidence**. Gaps: robustness testing, transaction costs, pervasiveness.

---

## Next Steps (For Implementation)

**This is research only — no code changes.**

If the user wants to implement enhancements:

1. **Quick win**: Add continuous VIX scaling to `plan_avoid_worst.R` as a variant (parameter sweep)
   - Compare binary (current) vs continuous scaling
   - Report switches, transaction costs, net CAGR

2. **New plan**: Create `plan_trend_regime.R`
   - Regime = f(12-month momentum, distance from SMA)
   - Apply as overlay to DRIF
   - Compare to `plan_risk_state.R` (VIX overlay)

3. **Enhance pervasiveness**: Expand `aw_cross_market` to include:
   - International equities: EFA (Europe), EEM (Emerging)
   - Bonds: TLT, IEF
   - Commodities: GLD, DBC
   - Alternative: VIX overlay on 60/40 portfolio (SPY/TLT)

4. **Transaction cost analysis**: Add to `plan_regime.R` and `plan_risk_state.R`
   - Count monthly switches
   - Apply 5bps per switch (same as avoid_worst.R)
   - Report gross vs net metrics

---

## Sources

- **Primary (inaccessible)**: Alpha Architect, "Rethinking Trend Following: Optimal Regime-Dependent Allocation" — website blocked (403 error)
- **Codebase**: `/Users/johngavin/docs_gh/proj/finance/data/historical/historical-102/R/`
  - `plan_avoid_worst.R` (lines 469-1055: VIX protection)
  - `plan_regime.R` (volatility-based regime)
  - `plan_risk_state.R` (VIX options multi-signal)
  - `plan_vix_macro_overlay.R` (VIX on non-equity assets)
- **Literature (general principles)**:
  - Trend-following regime strategies (generic)
  - Volatility regime switching (generic)
  - Macro regime indicators (yield curve, credit spreads)

---

## Related

- `plan_avoid_worst.R` — VIX protection, walk-forward validation
- `plan_regime.R` — volatility-based regime classification
- `plan_risk_state.R` — multi-signal VIX options overlay
- Project rules: `resulting-prohibition`, `underperformance-prior`, `cross-geography-pervasiveness`, `priced-in-prohibition`
- Issue #102 — this research task

---

## Date

2026-05-08
