# Rule: Strategy Combination — Name the Mode, and Attribute Per Leg

## Source

[#857](https://github.com/JohnGavin/historical/issues/857) — Zadeh (2026) via [Klement](https://klementoninvesting.substack.com/p/the-price-momentum-of-lottery-tickets), momentum x lottery (MAX) double sort on US stocks 1962–2023:

| Bucket | Annualised return |
|---|---:|
| Traditional momentum winners | 16.5% |
| Traditional momentum losers | 0.1% |
| Lottery-like winners (high MAX) | 15.0% |
| Lottery-like losers (high MAX) | **−14.8%** |

Read as a portfolio, this is "adding a lottery filter improves momentum". Read leg by leg, it is something much more specific and much more useful: **the filter is inert on the long leg and transformative on the short leg.** The correct implementation that follows — filter only the short side, leave the long side alone, and save the turnover — is invisible to anyone who only looked at the combined long/short Sharpe.

That gap between the portfolio-level reading and the per-leg reading is what this rule exists to close, generalised past this one instance.

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

### 1. The complement control — the cheapest kill test, and the one always skipped

If you filter to high-B, **you must also report low-B**. If the filtered and complement subsets perform alike, B is not filtering anything and the finding is dead. It costs one extra line and it is the single most informative number in the whole exercise.

The asymmetry between a result and its complement *is* the evidence. A good result on the filtered subset alone is not — it is one draw from a partition you chose.

### 2. Per-leg attribution — never a portfolio-level verdict alone

Report the filter's effect **separately on every leg** (long, short) and every corner bucket, not just on the combined strategy. A filter that helps one leg and hurts the other can show a flat portfolio Sharpe and still be a real, useful signal applied to the wrong half.

Zadeh's numbers are the worked example: portfolio-level, the lottery filter looks like a modest improvement; per-leg, it is inert (15.0 vs 16.5) on one side and worth ~15pp on the other.

### 3. Signal correlation — is B just A wearing a hat

Report `cor(rank(A), rank(B))` and the correlation of B with the obvious confounders — volatility above all. A filter highly correlated with the base signal is a re-weighting of it, not new information.

MAX is the live example: it is mechanically correlated with volatility, so "does MAX beat plain low-vol as a filter" is a required comparison, not an optional refinement.

### 4. The mechanism must predict the asymmetry *before* you look

State why B should work, **and on which leg**, in advance. Then check whether the data's asymmetry matches the one the mechanism predicts.

Zadeh's mechanism does this well: investors overpay for lottery payoffs, so those names have further to fall when momentum turns — a short-side story that predicts a short-side effect. Finding the effect where the mechanism said it would be is much stronger evidence than finding it somewhere.

A filter with no leg-specific mechanism that nonetheless shows a leg-specific effect is more likely noise. Per `resulting-prohibition`, inventing the mechanism after seeing which leg moved does not count.

### 5. Detection power recomputed on the FILTERED sample — never inherited

**A filter that improves the point estimate while shrinking the sample can leave you strictly less certain than before.** This is the trap that makes filters feel productive while destroying evidence.

Filtering to a tercile cuts the names per leg to roughly a third. For an equal-weighted leg that raises portfolio volatility by up to about `sqrt(3)` — the iid-idiosyncratic bound, less when the names are correlated — so the Sharpe must improve by more than the sample loss costs before the *detectability* of the result improves at all. Meanwhile `detection-power-required` applies to the filtered strategy on its own terms.

So: run `hd_detection_power()` on the filtered strategy's own Sharpe and its own sample, and report it beside the Sharpe. Do not carry the base strategy's power verdict across — the filtered strategy is a different estimator on a smaller sample and inherits nothing.

### 6. Multiplicity — combination is a multiple-testing generator

A 3x3 double sort is 9 buckets, 4 corners and at least 3 long/short variants. Every threshold is a free parameter. `K_eff_strat` must rise to reflect this ([#160](https://github.com/JohnGavin/historical/issues/160)); leaving it at the base strategy's value silently under-deflates every Sharpe downstream.

Count the tests honestly, including the ones you ran and discarded.

### 7. Turnover and cost, measured not assumed

A filter churns positions twice: names enter and leave on the base signal *and* on the filter. Report turnover for the filtered and unfiltered strategies side by side, and state which conclusions survive costs. Per `backtesting-assumptions`, a gross-only result for a higher-turnover strategy is not a result.

## Order of operations must be stated

`rank-then-filter` and `filter-then-rank` produce different portfolios and neither is the default. Say which, and why, in the plan header. Silence here is a reproducibility defect, not a style question.

## Where this repo currently falls short

Named so the rule is auditable, not aspirational:

| Site | Combination | Gap |
|---|---|---|
| `R/plan_mean_reversion.R:142-144` | Entry z-score filtered by **three** simultaneous risk filters (`min_skew = -1.5`, `max_semivar_ratio = 1.5`, `max_cvar_pct = -0.08`) | No complement control, no per-filter attribution, three hardcoded thresholds each a free parameter. Nothing establishes that any one of the three does anything, individually or at all |
| `R/plan_ltr_momentum.R` | 21 features into one LambdaMART ranking | A blend, correctly — but no ablation, so no feature's contribution is known |
| repo-wide | — | `ablation` appears **nowhere** under `R/`; the four `unfiltered` matches are comments about leaderboard metrics tables, not strategy ablations. There is no shared way to ask "what does this component contribute?" |

The mean-reversion row is the instructive one: it is exactly the Zadeh design — a base signal refined by a skewness filter — implemented without any of the seven checks above. Adding them there is the natural first repayment of this debt.

## Extending past filters: the general construction question

The four modes generalise into one question asked at every combination point:

> **What does this component contribute that the strategy would not have without it — and how would I see it if the answer were "nothing"?**

That second clause is the whole discipline. A component whose contribution cannot be isolated cannot be evaluated, and per `checks-must-distinguish-unknown` it must be reported as **unknown**, not as part of the strategy's credit. Every added component needs a stated mode, a stated mechanism, and an ablation that could show it inert.

The corollary for portfolio construction is the same rule one level up: adding a strategy to a book is itself a combination, and the same four modes apply — is the new strategy diversifying (blend), selecting when others trade (time), offsetting a known drawdown (hedge), or refining which assets another strategy holds (filter)? `new-strategy-portfolio-fit` and [#496](https://github.com/JohnGavin/historical/issues/496) ask for the marginal-benefit justification; this rule supplies the vocabulary for answering it and the ablation that makes the answer checkable.

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
- [#857](https://github.com/JohnGavin/historical/issues/857) — the momentum x MAX instance that motivated this
- [#496](https://github.com/JohnGavin/historical/issues/496) — new-strategy value gate, the portfolio-level version of the same question
- [#160](https://github.com/JohnGavin/historical/issues/160) — `K_eff_strat`
