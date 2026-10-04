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

# Details: Strategy Combination — origin, worked examples, repo gaps

Companion to [`strategy-combination-modes`](strategy-combination-modes.md). That
file holds every normative requirement; this one holds the evidence and worked
examples. Nothing here adds or relaxes a requirement.

## Source

[#857](https://github.com/JohnGavin/historical/issues/857) — Zadeh (2026) via [Klement](https://klementoninvesting.substack.com/p/the-price-momentum-of-lottery-tickets), momentum x lottery (MAX) double sort on US stocks 1962–2023:

| Bucket | Annualised return |
|---|---:|
| Traditional momentum winners | 16.5% |
| Traditional momentum losers | 0.1% |
| Lottery-like winners (high MAX) | 15.0% |
| Lottery-like losers (high MAX) | **−14.8%** |

Read as a portfolio, this is "adding a lottery filter improves momentum". Read leg by leg, it is something much more specific and much more useful: **the filter is inert on the long leg and transformative on the short leg.** The correct implementation that follows — filter only the short side, leave the long side alone, and save the turnover — is invisible to anyone who only looked at the combined long/short Sharpe.

That gap between the portfolio-level reading and the per-leg reading is what the rule exists to close, generalised past this one instance.

## Worked examples per check

### 1. Complement control

The asymmetry between a result and its complement *is* the evidence. A good result on the filtered subset alone is not — it is one draw from a partition you chose. It costs one extra line and it is the single most informative number in the whole exercise.

### 2. Per-leg attribution

A filter that helps one leg and hurts the other can show a flat portfolio Sharpe and still be a real, useful signal applied to the wrong half. Zadeh's numbers are the worked example: portfolio-level, the lottery filter looks like a modest improvement; per-leg, it is inert (15.0 vs 16.5) on one side and worth ~15pp on the other.

### 3. Signal correlation

MAX is the live example: it is mechanically correlated with volatility, so "does MAX beat plain low-vol as a filter" is a required comparison, not an optional refinement.

### 4. Mechanism predicts the asymmetry

Zadeh's mechanism does this well: investors overpay for lottery payoffs, so those names have further to fall when momentum turns — a short-side story that predicts a short-side effect. Finding the effect where the mechanism said it would be is much stronger evidence than finding it somewhere.

### 5. Detection power on the filtered sample

Filtering to a tercile cuts the names per leg to roughly a third. For an equal-weighted leg that raises portfolio volatility by up to about `sqrt(3)` — the iid-idiosyncratic bound, less when the names are correlated — so the Sharpe must improve by more than the sample loss costs before the *detectability* of the result improves at all. This is the trap that makes filters feel productive while destroying evidence.

### 6. Multiplicity

A 3x3 double sort is 9 buckets, 4 corners and at least 3 long/short variants. Every threshold is a free parameter. See [#160](https://github.com/JohnGavin/historical/issues/160).

## Where this repo currently falls short

Named so the rule is auditable, not aspirational:

| Site | Combination | Gap |
|---|---|---|
| `R/plan_mean_reversion.R:142-144` | Entry z-score filtered by **three** simultaneous risk filters (`min_skew = -1.5`, `max_semivar_ratio = 1.5`, `max_cvar_pct = -0.08`) | No complement control, no per-filter attribution, three hardcoded thresholds each a free parameter. Nothing establishes that any one of the three does anything, individually or at all |
| `R/plan_ltr_momentum.R` | 21 features into one LambdaMART ranking | A blend, correctly — but no ablation, so no feature's contribution is known |
| repo-wide | — | `ablation` appears **nowhere** under `R/`; the four `unfiltered` matches are comments about leaderboard metrics tables, not strategy ablations. There is no shared way to ask "what does this component contribute?" |

The mean-reversion row is the instructive one: it is exactly the Zadeh design — a base signal refined by a skewness filter — implemented without any of the seven checks. Adding them there is the natural first repayment of this debt.

## Extending past filters: portfolio construction

The corollary for portfolio construction is the same rule one level up: adding a strategy to a book is itself a combination, and the same four modes apply — is the new strategy diversifying (blend), selecting when others trade (time), offsetting a known drawdown (hedge), or refining which assets another strategy holds (filter)? `new-strategy-portfolio-fit` and [#496](https://github.com/JohnGavin/historical/issues/496) ask for the marginal-benefit justification; the rule supplies the vocabulary for answering it and the ablation that makes the answer checkable.

## Related issues

- [#857](https://github.com/JohnGavin/historical/issues/857) — the momentum x MAX instance that motivated the rule
- [#496](https://github.com/JohnGavin/historical/issues/496) — new-strategy value gate, the portfolio-level version of the same question
- [#160](https://github.com/JohnGavin/historical/issues/160) — `K_eff_strat`
