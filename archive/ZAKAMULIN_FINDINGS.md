# Zakamulin Continuous Regime Allocation - Findings

**Date:** 2026-05-11
**Issue:** #123 follow-up
**Branch:** `feat/zakamulin-regime-allocation`

## Summary

Implemented Zakamulin's continuous regime allocation method to test if dynamically adjusting momentum exposure based on VIX regime improves performance.

**Key Result:** Binary step allocation (100% when VIX <20, 0% otherwise) improved baseline momentum Sharpe from **0.05 to 0.24** (+385% improvement).

## Background

Issue #123 found that baseline momentum (total 12-month return) performs significantly better in VIX calm regime:
- **VIX <20 (calm):** Sharpe 0.63
- **Always invested:** Sharpe 0.05
- **Calm regime:** 65% of time

This suggested regime-based allocation could improve overall strategy performance.

## Methodology

### Signal Types Tested
1. **Raw VIX level** (chosen for simplicity)
2. VIX / VIX_MA(63) - relative to moving average
3. VIX percentile rank over 252-day window

### Allocation Functions Tested

| Method | Description | Formula |
|--------|-------------|---------|
| **Step** | Binary on/off at VIX threshold | 100% if VIX <20, else 0% |
| **Linear** | Linear scaling between thresholds | Scale 100% at VIX=15 to 0% at VIX=40 |
| **Sigmoid** | Smooth S-curve transition | 1 / (1 + exp((VIX - 25) / 5)) |
| **Piecewise** | Multi-level stepping | 100%@15, 80%@20, 30%@30, 0%@40 |

## Results

### Performance Comparison (Baseline Momentum Only)

| Method | Sharpe (No Regime) | Sharpe (Regime) | Improvement | Mean Exposure | % Time Invested | Annual Return | Max DD |
|--------|-------------------|----------------|-------------|---------------|-----------------|---------------|--------|
| **Step (VIX<20)** | 0.05 | **0.24** | **+385%** | 78% | 78.3% | 3.0% | -14.6% |
| Piecewise (4 levels) | 0.05 | 0.22 | +340% | 88% | 98.4% | 3.2% | -18.3% |
| Linear (15-40) | 0.05 | 0.21 | +320% | 88% | 98.5% | 3.2% | -19.9% |
| Sigmoid (center=25) | 0.05 | 0.21 | +320% | 84% | 99.6% | 3.0% | -16.7% |

**N = 742 months** (all methods tested on same data)

### Transition/Turnover Analysis

| Method | Mean Monthly Change | Median Change | % Large Changes (>20%) | N Large Changes |
|--------|-------------------|---------------|----------------------|----------------|
| Step (VIX<20) | 0.096 (9.6%) | 0 | 9.6% | 71/742 |
| Linear (15-40) | 0.060 (6.0%) | 0 | 10.9% | 81/742 |
| Sigmoid (center=25) | 0.064 (6.4%) | 0.01 | 10.9% | 81/742 |
| Piecewise (4 levels) | 0.065 (6.5%) | 0 | 11.7% | 87/742 |

**Interpretation:** Step function has slightly higher turnover (9.6% mean monthly change) but this is still very manageable. Median change is 0, meaning most months the allocation stays constant.

## Analysis

### What Works

1. **Binary allocation performs best:** The simple step function (VIX <20 threshold) outperforms all continuous allocation methods. This suggests the regime signal is strong enough that smoothing doesn't help.

2. **Massive Sharpe improvement:** Going from 0.05 to 0.24 is a nearly 5x improvement in risk-adjusted returns, achieved simply by avoiding high-VIX periods.

3. **Reasonable exposure:** 78% average exposure means we're invested most of the time but avoid the worst drawdowns during volatility spikes.

4. **Low turnover:** Median allocation change is 0 - regime shifts are infrequent enough that we're not constantly rebalancing.

### What Doesn't Work

1. **Continuous allocation underperforms binary:** Linear, sigmoid, and piecewise methods all show Sharpe 0.21-0.22, slightly worse than the simple step function. The smooth transition doesn't add value - VIX regime shifts are distinct enough that binary works best.

2. **Still below "actionable" threshold:** Sharpe 0.24 is in the "marginal" range (0.1-0.3). It's a huge improvement over 0.05, but may not be strong enough to deploy as a standalone strategy.

## Recommendation

**Status: MARGINAL - Promising but needs enhancement**

### Why Marginal?
- Sharpe 0.24 is below the 0.3 "actionable" threshold for live deployment
- Simple VIX threshold may be too naive for institutional-grade strategy
- Baseline momentum alone (even regime-aware) may not be diversified enough

### Next Steps

1. **Combine with other signals:** Test regime allocation on:
   - Multi-factor portfolios (not just momentum)
   - Diversified strategies (avoid worst, DRIF, etc.)
   - Value, quality, and carry factors

2. **Enhance regime signal:**
   - Add VVIX (VIX of VIX) as secondary signal
   - Combine VIX with credit spreads or funding conditions
   - Test macro overlays (ISM, yield curve, etc.)

3. **Robustness tests:**
   - Out-of-sample validation (split 2000-2015 vs 2015-2024)
   - Parameter sensitivity (VIX threshold 15, 18, 22 instead of 20)
   - Different cost assumptions (0.1%, 0.2%, 0.3% per trade)

4. **Position sizing:** Instead of binary 0/100%, test gradual scaling:
   - 50% base allocation + 50% regime-adjusted
   - Kelly criterion position sizing based on regime Sharpe estimates

## Files Created

- `R/zakamulin_allocation.R` - Core allocation functions (250 lines)
- `R/plan_zakamulin_allocation.R` - Targets pipeline (20 targets)
- Integration into `docs/_targets.R`

## Visualization

Generated plots (available via `tar_read()`):
- `zak_cumulative_plot` - Cumulative returns with VIX regime shading
- `zak_allocation_plot` - Portfolio exposure over time
- `zak_vix_allocation_scatter` - VIX vs allocation function shapes

## Reference

Zakamulin (2014) "Market Timing with a Robust Megatrend-Filter"

---

**Next Session:**
1. Create PR with these findings
2. Test regime allocation on multi-strategy portfolios (not just baseline momentum)
3. Investigate VVIX + VIX combined signal
