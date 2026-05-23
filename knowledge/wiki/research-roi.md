# Research ROI: Expected vs Actual Performance Gains

Meta-validation tracker — record expected Sharpe gains from each research initiative
BEFORE implementing, then compare against actual results after implementation.

**Related:** #121, #119, #122, #120, #125, #124, #117, #123

---

> **LIVING DOCUMENT:** Every research issue must record its expected gain BEFORE
> implementing, then the actual gain after backtests complete. Actual Gain and Delta
> values remain TBD until the relevant backtest has been run and peer-reviewed.
> Fabricating actuals defeats the calibration purpose of this tracker.

---

## Tracking Table

| Issue | Research | Expected Gain | Actual Gain | Delta | Notes |
|---|---|---|---|---|---|
| #121 | Momentum decomposition (style/industry tilt) | +10–20% Sharpe | TBD | TBD | Claim: overweight persistent components |
| #119 | Volatility spike adaptation (6m vs 12m lookback) | +10–20% Sharpe in spike regimes | TBD | TBD | Claim: faster adaptation to regime change |
| #123 | Regime-dependent allocation (continuous vs binary) | +10–20% Sharpe vs VIX overlay | TBD | TBD | Claim: Zakamulin optimal sizing |
| #122 | Crash prediction (5-day probability) | +2.51 Sharpe (paper claim) | TBD | TBD | Paper result, not our expectation |
| #120 | StockGPT transformer | +2.5 Sharpe (paper claim) | TBD | TBD | Paper result; replication uncertain |
| #125 | Transaction cost reality check | −10–30% Sharpe (downward adjustment) | TBD | TBD | Validation, not enhancement |
| #124 | Curve trades with macro signals | +0.5–0.6 Sharpe (uncorrelated) | TBD | TBD | Diversification, not alpha |
| #117 | DRIF stock-level implementation | TBD (compare to factor-level) | TBD | TBD | No prior expectation set |

---

## Measurement Protocol

### Before Implementation (Expected Gain)

1. **Record baseline** — current strategy Sharpe ratio from the most recent backtest
2. **State hypothesis** — "We expect +X% improvement because..."
3. **Define test period** — the data range used for validation (e.g., 2000–2023)
4. **Define metric** — Sharpe ratio, information ratio, max drawdown reduction, or combination
5. **Commit to table** — update this page with expected gain BEFORE any implementation begins

### After Implementation (Actual Gain)

1. **Run backtest** — same test period as the baseline recorded above
2. **Record actual Sharpe** — new strategy Sharpe ratio
3. **Compute delta** — `(Actual − Baseline) / Baseline`
4. **Update table** — fill in Actual Gain and Delta columns
5. **Analyze** — document why the expectation was over- or undershot

### Learning Metrics

| Metric | Formula | Direction |
|--------|---------|-----------|
| **Accuracy** | `|Expected − Actual| / Expected` | Lower is better |
| **Bias** | `mean(Actual − Expected)` across all completed rows | Negative = systematically optimistic |
| **Calibration** | `cor(Expected, Actual)` across all completed rows | Higher is better |

Review these quarterly. A persistent negative bias means paper claims should be
discounted before setting expectations (see Example Entry below for the 2× overestimation
pattern in #121).

---

## Example Entry (from issue #127)

**Issue #121: Momentum Decomposition**

*Before implementation:*
- Baseline (LTR total 12m momentum): Sharpe 0.85 (2000–2023)
- Expected gain: +15% Sharpe (0.85 → 0.98)
- Rationale: paper shows style/industry momentum persists while stock-specific reverts

*After implementation (hypothetical to illustrate the protocol):*

> ⚠ AI-inferred: The following illustrative numbers are drawn verbatim from the
> worked example in issue #127 and are NOT confirmed backtest results. They exist
> only to demonstrate protocol usage; they must be replaced with real figures when
> the #121 backtest is complete.

- Actual Sharpe: 0.91 (+7.1% vs baseline)
- Delta: −7.9 percentage points vs expected (+15%)
- Analysis: overestimated by ~2×; possible causes — smaller stock-specific weight,
  higher turnover from decomposed signal, different universe (international vs US-only)
- Lessons: halve paper claims for our implementations; verify universe match; account
  for turnover increase when decomposing signals

---

## Process Integration

| Stage | Action |
|-------|--------|
| Before research starts | Update the Tracking Table above with Expected Gain |
| After implementation | Fill in Actual Gain, Delta, and Analysis |
| Quarterly review | Compute Accuracy, Bias, Calibration; adjust future expectation priors |
| Annual review | Update research prioritisation framework with learned calibration factors |

### Calibration adjustments (to be updated as data accumulate)

> ⚠ AI-inferred: The following calibration factors are placeholders derived from
> the issue's motivating example. Replace with empirically computed values once
> at least 4–5 rows in the Tracking Table have Actual Gain recorded.

- Momentum enhancements: multiply paper claims by ~0.5× until evidence says otherwise
- ML replication: discount by ~0.3× due to undocumented hyperparameters

---

## Connections to Existing Rules

- **`verification-before-completion` rule** — enforces pre-registration at the research level
- **`resulting-prohibition` rule** — do not abandon research solely because it underperformed
  expectations; judge by process, not outcome
- **`analysis-rationale-mandatory` rule** — document WHY a gain is expected before seeing results

---

## Sources

- Issue #127 — [Track research ROI: expected vs actual performance gains (meta-validation)](https://github.com/JohnGavin/historical/issues/127) — primary source; all tracking table rows and the measurement protocol are copied verbatim from that issue
- Tetlock, *Superforecasting* — track forecast accuracy over time to improve calibration
- Gelman & Loken, "Garden of Forking Paths" — pre-register hypotheses before seeing results
