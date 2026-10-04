---
paths:
  - "R/plan_mean_reversion.R"
  - "R/plan_ltr_momentum.R"
  - "R/plan_multi_strategy.R"
  - "R/plan_add_signal.R"
  - "R/plan_mom_prepeak*.R"
  - "R/plan_regime*.R"
  - "R/plan_vix_macro_overlay.R"
  - "R/plan_marginal_contribution.R"
  - "R/plan_portfolio_opt.R"
  - "R/plan_stock_backtest.R"
  - "R/plan_factormax.R"
  - "R/plan_drif*.R"
  - "R/plan_commodities_*.R"
  - "packages/historicaldata/R/add_signal.R"
  - "explorations/**"
---

# Rule: Strategy Combination — Name the Mode, and Attribute Per Leg

Origin ([#857](https://github.com/JohnGavin/historical/issues/857), Zadeh 2026
momentum x MAX: the lottery filter is inert on the long leg and transformative
on the short leg), per-check worked examples and the repo-gap audit live in
[`strategy-combination-modes-details.md`](strategy-combination-modes-details.md).

A portfolio-level reading of a combined strategy hides what each component does
per leg. This rule closes that gap.

## When This Applies

Any time two or more signals are combined into one strategy, or one strategy's universe, weights, or exposure is conditioned on a second signal. Includes:

- Double sorts and any "rank by A, then filter on B"
- Risk filters applied to an entry signal (`R/plan_mean_reversion.R` — three of them)
- Regime or volatility overlays scaling an existing leg
- Feature stacks fed to one model (`R/plan_ltr_momentum.R` — 21 features)
- Any proposal phrased as "use X to improve Y"

## CRITICAL: Name the combination mode before writing any code

Four modes. They are not interchangeable, they have different failure modes, and picking one by accident is the normal way this goes wrong.

| Mode | What the second signal does | What it buys | What it costs |
|---|---|---|---|
| **Filter** | Selects *which assets* the first strategy trades | Concentration where the edge lives | Sample. Thins the cross-section, raises turnover |
| **Blend** | Averaged into a combined score or capital split | Variance reduction via diversification | Dilution. Both signals are weakened |
| **Time** | Scales gross exposure over time (vol-managed, regime) | Avoids the bad periods | Timing risk; often just sells low |
| **Hedge** | Held alongside to offset a known failure mode | Truncates a specific tail | Carry, permanently |

**Filter and blend are opposites and are constantly confused.** A blend says "both signals have information, average them". A filter says "signal A has the information, signal B says where to look for it". If you cannot say which claim you are making, you are not ready to test it.

The declaration goes in the plan file header, in one sentence, before the first target.

## Required for any FILTER combination

Seven checks. The first two are cheap and kill most filters; run them before anything else.

1. **The complement control.** If you filter to high-B, **you must also report low-B**. If the filtered and complement subsets perform alike, B is not filtering anything and the finding is dead. A good result on the filtered subset alone is one draw from a partition you chose.
2. **Per-leg attribution — never a portfolio-level verdict alone.** Report the filter's effect **separately on every leg** (long, short) and every corner bucket, not just on the combined strategy.
3. **Signal correlation.** Report `cor(rank(A), rank(B))` and the correlation of B with the obvious confounders — volatility above all. A filter highly correlated with the base signal is a re-weighting of it, not new information.
4. **The mechanism must predict the asymmetry *before* you look.** State why B should work, **and on which leg**, in advance, then check whether the data's asymmetry matches. A filter with no leg-specific mechanism that nonetheless shows a leg-specific effect is more likely noise. Per `resulting-prohibition`, inventing the mechanism after seeing which leg moved does not count.
5. **Detection power recomputed on the FILTERED sample — never inherited.** A filter that improves the point estimate while shrinking the sample can leave you strictly less certain than before. Run `hd_detection_power()` on the filtered strategy's own Sharpe and its own sample, and report it beside the Sharpe. The filtered strategy is a different estimator on a smaller sample and inherits nothing; `detection-power-required` applies to it on its own terms.
6. **Multiplicity.** Combination is a multiple-testing generator: every threshold is a free parameter. `K_eff_strat` must rise to reflect this ([#160](https://github.com/JohnGavin/historical/issues/160)); leaving it at the base strategy's value silently under-deflates every Sharpe downstream. Count the tests honestly, including the ones you ran and discarded.
7. **Turnover and cost, measured not assumed.** A filter churns positions twice (base signal *and* filter). Report turnover for the filtered and unfiltered strategies side by side, and state which conclusions survive costs. Per `backtesting-assumptions`, a gross-only result for a higher-turnover strategy is not a result.

## Order of operations must be stated

`rank-then-filter` and `filter-then-rank` produce different portfolios and neither is the default. Say which, and why, in the plan header. Silence here is a reproducibility defect, not a style question.

## The general construction question

Asked at every combination point:

> **What does this component contribute that the strategy would not have without it — and how would I see it if the answer were "nothing"?**

A component whose contribution cannot be isolated cannot be evaluated, and per `checks-must-distinguish-unknown` it must be reported as **unknown**, not as part of the strategy's credit. Every added component needs a stated mode, a stated mechanism, and an ablation that could show it inert. Adding a strategy to a book is itself a combination: the same four modes apply (see the details file and [#496](https://github.com/JohnGavin/historical/issues/496)).

Known gaps in this repo (mean-reversion's three filters, LTR's 21 features, no shared ablation helper) are audited in the details file.

## Forbidden Patterns

| Pattern | Why wrong | Fix |
|---|---|---|
| Filtered subset reported without its complement | One draw from a partition you chose; no evidence the filter filters | Report both (check 1) |
| Portfolio-level Sharpe as the only verdict on a filter | Hides a filter that works on one leg and is noise on the other | Per-leg attribution (check 2) |
| Filtered strategy inheriting the base strategy's detection-power verdict | Different estimator, smaller sample — inherits nothing | Recompute (check 5) |
| Stacking N filters, reporting only the N-filter result | No filter's contribution is known; N free thresholds unaccounted | Ablate one at a time |
| `K_eff` left unchanged after adding a double sort | Under-deflates every Sharpe downstream | Raise it (check 6) |
| Mechanism written after seeing which leg moved | `resulting-prohibition` | Pre-register the leg |
| "Blend" and "filter" used interchangeably in the same discussion | They make opposite claims about where the information is | Declare the mode in the plan header |
| Adding a filter because it improves the point estimate, with a smaller sample | Can reduce certainty while appearing to improve the strategy | Compare detection power before and after |

## Self-test

Before merging any combination:

> **If this second signal were pure noise, what number in my output would look different?**

If nothing would, the combination has not been tested — only performed. And:

> **Which leg did the mechanism say this would work on, and is that the leg it worked on?**

## Related

- [`detection-power-required`](detection-power-required.md) — check 5; a filtered strategy needs its own verdict
- [`backtest-robustness`](backtest-robustness.md) — `K_eff_strat` deflation; check 6
- [`priced-in-prohibition`](priced-in-prohibition.md) — incremental power over the base leg is the same demand as check 1, aimed at the market rather than at the filter
- [`resulting-prohibition`](resulting-prohibition.md) — check 4; the mechanism precedes the result
- [`backtesting-assumptions`](backtesting-assumptions.md) — check 7 cost model
- [`fail-loud-not-null`](fail-loud-not-null.md) — a filter is a row-dropper; count and report what it drops
- [`look-ahead-bias-prevention`](look-ahead-bias-prevention.md) — both signals lag, not just the base one
- [`dashboard-output-first`](dashboard-output-first.md) — a filter refines an existing surface; it does not earn a new one
