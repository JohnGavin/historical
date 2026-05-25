---
title: Anomaly-Driven Demand (ADD)
canonical_question: "What is Anomaly-Driven Demand, how is it measured, and does it inflate factor returns or offer a tradeable signal?"
status: active
fresh_until: 2026-08-23
consensus_level: direct
sources:
  - swedroe-anomaly-driven-demand-2026-05-22.md
  - anomaly-driven-demand-kjaer-posselt-2025.md
compiled_by: claude-sonnet-4-6
compiled_on: 2026-05-25
tags: [factor-investing, crowding, rebalancing, anomalies, demand-based-pricing, chen-zimmermann, open-asset-pricing]
---

# Anomaly-Driven Demand (ADD)

Anomaly-Driven Demand (ADD) is a measure of the mechanical buying and selling pressure exerted on individual stocks by the collective rebalancing of factor investors. When a stock simultaneously enters the long legs of many anomaly strategies — because its characteristics updated this month — it attracts coordinated institutional buying from the entire factor-investing ecosystem. Kjær & Posselt (Aarhus University, Nov 2025) show that this pressure is large enough to move prices, that the effect is permanent, and that it cannot be explained by standard risk factors. For practitioners running factor-based leaderboards or multi-strategy systems, ADD matters primarily as a **crowding and inflation warning** (Angle A), and only secondarily as a potential trading signal (Angle B).

---

## What ADD Is

### The Chen-Zimmermann universe

ADD is constructed from the 209 anomalies in the [Chen & Zimmermann (2022) "Open source cross-sectional asset pricing" dataset](https://www.openassetpricing.com/), which spans US common stocks (NYSE, AMEX, NASDAQ) from January 1990 to December 2023. Only post-publication anomalies are counted at each point in time, ensuring that the signal is in investors' information sets.

> "For each of the 209 anomalies in the Chen and Zimmermann dataset, the authors sorted stocks into portfolios (quintiles) based on the anomaly characteristic. Each month, they counted — for each individual stock — how many anomaly long legs it had newly entered minus how many short legs it had newly entered. The change in this net count from one month to the next is ADD." — [swedroe-anomaly-driven-demand-2026-05-22.md:L105-114](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L105)

### Formal definition

For each stock j at time t:

1. Count the net number of long-leg minus short-leg inclusions across all published anomalies: **NET_j,t = Σ (1_[j ∈ P_long] − 1_[j ∈ P_short])**
2. Take the first difference: **ADD_j,t = NET_j,t − NET_j,t−1**

A high positive ADD value means a stock has recently entered many more long legs (or exited many short legs), signalling coordinated buying. A large negative ADD signals coordinated selling.

> "Since ADD is based only on anomaly characteristics, it is both measurable in real-time and also captures demand from multi-factor investors." — [anomaly-driven-demand-kjaer-posselt-2025.md:L344-345](../raw/anomaly-driven-demand-kjaer-posselt-2025.md#L344)

### Why it arises

Anomaly strategies require periodic rebalancing when stock characteristics update. A value investor must sell a stock that transitions from value to growth; a momentum investor must buy a stock that jumps into the top decile. Crucially, all anomalies draw from the same stock universe. When trillions of dollars track hundreds of strategies simultaneously, the rebalancing flows for stocks at the intersection of many long legs are large, predictable, and concentrated in calendar time.

> "Each time a stock enters the long leg of a value strategy, value investors must buy it. When it exits, they must sell. This is mechanical, predictable rebalancing — analogous to what happens when a stock is added to or removed from an index like the S&P 500." — [swedroe-anomaly-driven-demand-2026-05-22.md:L71-78](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L71)

---

## Key Empirical Findings

### 1. Monotonic return spread: 6.62% to 10.65% (t = 4.03, Sharpe = 0.61)

Sorting stocks into five quintile portfolios by ADD, annualised excess returns rise monotonically:

| Quintile | Annualised excess return |
|----------|-------------------------|
| Low (Q1) | 6.62% |
| Q2 | — |
| Q3 | — |
| Q4 | — |
| High (Q5) | 10.65% |
| **H–L spread** | **4.03 percentage points** |

The t-statistic on the spread is 4.03. The Sharpe ratio of a long-short strategy based purely on ADD is **0.61**.

> "Excess stock returns are monotonically increasing across ADD-sorted portfolios from 6.62% for the Low portfolio to 10.65% for the High portfolio, annualized. The return differential between the High and the Low portfolio (High-Low) is 4.03 percentage points with a t-statistic of 4.03." — [anomaly-driven-demand-kjaer-posselt-2025.md:L450-454](../raw/anomaly-driven-demand-kjaer-posselt-2025.md#L450)

### 2. Alpha survives standard controls

The return spread cannot be explained by: the Fama-French five-factor model, the Carhart momentum factor, the first three principal components of anomaly returns (which together explain 72% of total variation), or a bespoke "NET⊥ADD" portfolio designed to isolate anomaly exposure without ADD-driven changes. All intercepts remain statistically and economically significant across specifications.

> "The return differential between high- and low-ADD stocks cannot be explained by the controls; all intercepts are highly significant and align in magnitude with the return differential reported earlier." — [anomaly-driven-demand-kjaer-posselt-2025.md:L538-545](../raw/anomaly-driven-demand-kjaer-posselt-2025.md#L538)

### 3. ADD predicts actual investor positioning

The demand signal is not just statistical noise — it maps onto real changes in ownership:

- **Short interest** falls for high-ADD stocks in the following month and rises for low-ADD stocks. The H–L difference is statistically significant (sample: Jan 2007–Dec 2023).
- **Breadth of mutual fund ownership** (number of mutual funds holding the stock) increases with ADD: t=2.38 for H–L on full ADD; t=3.09 for the long-leg component alone.

> "Short interest rose for low-ADD stocks and fell for high-ADD stocks in the subsequent month. The fraction of institutional investors holding a stock — its 'breadth' — increased significantly with ADD, and this pattern was driven specifically by stocks entering more anomaly long legs." — [swedroe-anomaly-driven-demand-2026-05-22.md:L189-200](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L189)

### 4. Concentrated in the first ~6 trading days; entirely intraday

The entire H–L return differential accumulates in the first five to six trading days of the month — when institutional investors rebalance after month-end characteristic updates. Within those days, the effect is entirely driven by **open-to-close (intraday) returns**, not overnight returns.

| Period | Average daily H–L return | t-statistic |
|--------|--------------------------|-------------|
| First 5 trading days | 0.19% per month | 4.10 |
| Intraday (first 5 days) | 0.19% per month | **5.28** |
| Overnight (first 5 days) | ≈0% | insignificant |
| Rest of month | ≈0% | insignificant |

> "The figure shows a clear clustering of positive returns during the first five to six trading days following the characteristics update, while the pattern becomes mixed for the remainder of the month." — [anomaly-driven-demand-kjaer-posselt-2025.md:L637-638](../raw/anomaly-driven-demand-kjaer-posselt-2025.md#L637)

The intraday signature is consistent with institutional order flow (mutual funds and ETFs predominantly trade during market hours, not overnight).

### 5. Price impact is permanent — no reversal

Tracking the same stocks over 12 months after portfolio formation, there is **no reversal** of the initial return differential. The cumulative spread remains stable or drifts slightly higher, consistent with demand-based pricing theory: a shift in the demand curve leads to a permanent change in equilibrium price, not a temporary liquidity effect.

> "Tracking the same set of stocks over 12 months after portfolio formation, there was no reversal of the initial return differential. The cumulative spread remained stable or drifted slightly higher." — [swedroe-anomaly-driven-demand-2026-05-22.md:L217-220](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L217)

### 6. Stronger for high-t anomalies; asymmetric long/short legs

When anomalies are grouped by their published t-statistics, the ADD effect is **statistically significant only within the high-t group**. For low- and medium-t anomalies, the H–L differential is economically and statistically near zero. Relative to the baseline 4.03 ppts, the high-t group earns an additional ~103 basis points.

Within the high-t group, a long/short asymmetry emerges: long-leg changes produce a 4.15% H–L spread; short-leg changes only 1.88%. This is consistent with institutional short-selling constraints (most mutual funds are long-only).

> "The price impact of ADD is concentrated among statistically robust anomalies. For low-t anomalies, the High-Low spread is essentially zero. For high-t anomalies, the spread jumps to over 5 percentage points, and the effect is asymmetric — changes in long-leg inclusions have a larger price impact than short-leg changes." — [swedroe-anomaly-driven-demand-2026-05-22.md:L261-270](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L261)

### 7. U-shaped in size: present in both micro-cap and mega-cap

ADD predicts returns across the size distribution, but with a U-shaped profile: strongest for micro-cap stocks (thin markets, high price sensitivity to any flow), weakest in the mid-size range, and also **statistically significant for mega-cap stocks** at ~3 percentage points annualised.

> "The mega-cap result, a statistically significant 3 percentage points annualized premium, is more surprising. It likely reflects the sheer scale of assets chasing the same large, liquid names." — [swedroe-anomaly-driven-demand-2026-05-22.md:L289-298](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L289)

### 8. Anomaly-portfolio-level evidence: 8.04 ppts spread; 24 bp per 1-SD

At the anomaly level (not stock level), anomalies whose long legs contain high-ADD stocks and whose short legs contain low-ADD stocks earn **8.04 percentage points more per year** than anomalies at the other extreme. A one-standard-deviation increase in ADD imbalance predicts **24 basis points** higher next-month returns.

> "Anomalies whose long legs contain high-ADD stocks and whose short legs contain low-ADD stocks earned 8.04 percentage points more per year than anomalies at the other extreme. A one-standard-deviation increase in ADD imbalance predicted 24 basis points higher next-month returns." — [swedroe-anomaly-driven-demand-2026-05-22.md:L238-241](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L238)

### 9. Valuation signals dominant; "Other" category second

When ADD is decomposed by the Chen-Zimmermann economic categories, only three are individually significant: **Valuation** (0.26% monthly H–L), **Other** (0.27%), and **Option Risk** (0.25%). Excluding Valuation reduces the overall H–L by 0.14 percentage points; excluding Other reduces it by 0.09 ppts.

> "Only the categories Valuation, Other, and Option Risk are individually significant... Excluding the Valuation anomalies reduces the average High-Low return differential by 0.14 percentage points." — [anomaly-driven-demand-kjaer-posselt-2025.md:L682-688](../raw/anomaly-driven-demand-kjaer-posselt-2025.md#L682)

### 10. The feedback loop

> "As factor investing has grown, its rebalancing activity has become large enough to generate meaningful demand pressure in the stocks that define anomalies' long legs — and selling pressure in those that define the short legs. This mechanically inflates observed returns, which attracts more capital into the same strategies, which drives larger rebalancing flows, which produces more price pressure, which inflates returns further. The anomaly, in other words, is partly feeding itself." — [swedroe-anomaly-driven-demand-2026-05-22.md:L316-330](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L316)

---

## Return Inflation Warning: What ADD Means for Backtested Anomaly Returns

The most important implication for practitioners who evaluate or deploy anomaly strategies is explicit in the paper:

> "ex-post risk premia estimates are likely to be considerably inflated by the anomaly investors' rebalancing, particularly when the researcher relies on samples that encompass post-publication periods." — [anomaly-driven-demand-kjaer-posselt-2025.md:L217-219](../raw/anomaly-driven-demand-kjaer-posselt-2025.md#L217)

> ⚠ AI-inferred: This is a direct and explicit statement by the authors. The logical chain is: (1) post-publication, capital flows into the anomaly; (2) rebalancing of that capital mechanically buys the long leg and sells the short leg at predictable calendar points; (3) this creates demand pressure that inflates the realised long-short return; (4) backtests that use post-publication data capture both the genuine risk premium AND the demand-pressure component; (5) therefore, post-publication backtested Sharpe ratios overstate the forward-looking premium for a marginal investor adding capacity today. The inflation is not a static one-time effect — it grows as more capital enters.

---

## Angle A vs Angle B: The Practitioner Recommendation

### Angle A — Crowding/Capacity Warning (RECOMMENDED)

The primary actionable implication of ADD is not that you should trade it — it is that **your existing leaderboard strategies' reported performance may be significantly inflated by ADD-driven demand pressure**.

**Why Angle A is higher-value and lower-risk:**

1. **Directly applicable to issue #160** — the effective number of tested strategies and deflated Sharpe ratio concern. ADD provides a *mechanism* explaining why backtested Sharpe ratios overstate forward-looking returns: the post-publication period that forms the backtest coincides with capital inflows that mechanically inflate the very strategy returns being measured. Every strategy on our leaderboard that appeared post-2000 and uses widely-known anomaly characteristics is potentially affected.

2. **Directly applicable to issue #271** — Turn-of-the-Month (month-start concentration). The ADD return is entirely concentrated in the first 5-6 trading days of the month, with a t=5.28 intraday t-statistic. This is structurally the same as the Turn-of-the-Month calendar anomaly in #271. ADD provides the *microstructure mechanism* for why month-start returns are elevated: it is not a free anomaly — it is institutional rebalancing flow that a newcomer cannot profitably front-run without being the large institution itself.

3. **No capacity problem**: using ADD as a warning flag requires no trading. It is pure analysis.

4. **Aligns with [[swedroe-evidence-investing]] Gap 4 (valuation spread threshold) and the broader crowding literature**: Swedroe's framework already warns against highly-followed, statistically robust anomalies at scale. ADD quantifies precisely how the crowding of high-t, widely-followed anomalies mechanically inflates their measured returns.

**Practical use of Angle A in this project:**

- For any strategy on the leaderboard based on anomaly characteristics from the Chen-Zimmermann universe, estimate the ADD loading of its long and short legs. High ADD loading on the long leg is a red flag: a meaningful fraction of the reported return may be demand pressure, not genuine alpha.
- Weight-down anomalies whose reported t-statistics are high (>3.5) when forecasting forward Sharpe ratios — these are precisely the ones where ADD is concentrated and inflation is largest.
- Flag strategies whose peak performance coincides with the post-2006 anomaly publishing boom (the period when ADD was largest per Figure 2 of the paper).

### Angle B — ADD as a Long/Short Signal (LOWER PRIORITY)

ADD could, in principle, be traded as a long/short signal: buy high-ADD stocks, short low-ADD stocks, hold for 5-6 trading days at the start of each month. The measured Sharpe is 0.61, the price impact is permanent (no reversal), and the alpha survives FF5+momentum.

**Why Angle B is lower-priority for this project:**

> ⚠ AI-inferred: The following arguments against Angle B are synthesised from the ADD paper and our existing rules; they are not stated together in any single source.

1. **The ADD signal is public and already known.** As of March 2026 the paper has been presented at Cavalcade Asia-Pacific 2025, Frontiers of Factor Investing 2024, and SGF 2025. The `priced-in-prohibition` rule requires incremental predictive power beyond what is already reflected. Institutions with faster data pipelines and lower transaction costs are better positioned to exploit a month-start, 5-day window than a rules-based retail-scale system.

2. **Implementation requires being early in the 5-day window.** The entire effect is intraday, concentrated in trading days 1-5 post-month-end. To capture it, execution must occur on day 1-2 of the month, before the effect fully dissipates. This requires real-time characteristic update pipelines — a non-trivial infrastructure requirement.

3. **Transaction costs and capacity.** The U-shaped size result means the signal is strongest in micro-caps (where costs are highest) and present in mega-caps (where it competes with the deepest liquidity pools globally). The mid-range — where transaction costs and capacity are most tractable — is precisely where the signal is weakest.

4. **Feedback loop risk.** If ADD is now widely known, the feedback loop could accelerate, compressing the window further. Alternatively, crowding at the start of the month on the ADD signal itself creates its own ADD-on-ADD instability.

5. **Sharpe 0.61 at portfolio level before costs.** This is respectable but not exceptional. With the structural limitations above, net-of-cost Sharpe is likely lower.

**If pursuing Angle B regardless:** The most defensible implementation would be: (a) use only the high-t anomaly subset of ADD (which delivers ~5+ ppts H–L vs 4 ppts for all); (b) target mega-cap stocks where the 3-ppt premium persists in deeply liquid names; (c) execute at open on day 1 and 2 of each month; (d) hedge out anomaly factor exposure explicitly (FF5 + MOM).

---

## Mechanism Summary

```
Anomaly publication → Capital inflow into strategy
   ↓
Monthly characteristic update → Stocks enter/exit long and short legs
   ↓
ADD = Δ(net long-leg inclusions) → Predicts direction of coordinated flow
   ↓
Institutional rebalancing (days 1–5 of next month, intraday)
   ↓
Demand pressure → Price impact in high-ADD stocks (buy) + low-ADD stocks (sell)
   ↓
Permanent price shift (no reversal) + inflated measured anomaly return
   ↓
Higher measured return → more capital → larger ADD signal → larger price impact
                                    [feedback loop]
```

> ⚠ AI-inferred: The feedback loop diagram above synthesises from [swedroe-anomaly-driven-demand-2026-05-22.md:L316-330](../raw/swedroe-anomaly-driven-demand-2026-05-22.md#L316) and [anomaly-driven-demand-kjaer-posselt-2025.md:L217-219](../raw/anomaly-driven-demand-kjaer-posselt-2025.md#L217). Neither source presents this as a single diagram, but both describe the constituent arrows.

---

## Related Topics

- [[swedroe-evidence-investing]] — Swedroe five criteria (persistent, pervasive, robust, investable, intuitive); crowding as a capacity warning; Gap 4 (valuation spread thresholds)
- [[priced-in-signals]] — evidence log for signals that failed the priced-in test in this project
- [[market-behavior-gap-analysis]] — broader gap analysis of market microstructure and demand effects
- Issue #160 — effective number of tested strategies, deflated Sharpe ratio: ADD provides a structural inflation mechanism that partially explains inflated in-sample Sharpe ratios
- Issue #271 — Turn-of-the-Month anomaly: ADD is a microstructure explanation for the month-start return elevation documented in #271

---

## Sources

- [swedroe-anomaly-driven-demand-2026-05-22.md](../raw/swedroe-anomaly-driven-demand-2026-05-22.md) — Larry Swedroe, Alpha Architect, published 2026-05-22. Digest of the Kjær & Posselt paper. Key sections: construction (L96-138), key findings (L141-330), investor takeaways (L368-416). Lines cited: L71-78, L105-114, L149-157, L189-200, L205-213, L217-224, L238-241, L261-270, L289-298, L316-330, L341-345.
- [anomaly-driven-demand-kjaer-posselt-2025.md](../raw/anomaly-driven-demand-kjaer-posselt-2025.md) — Mads Markvart Kjær & Anders Merrild Posselt, Aarhus University / Danish Finance Institute. Version November 11, 2025. Presented at Cavalcade Asia-Pacific 2025. Key sections: abstract (L40-47), proxy construction (L280-345), main results Table 1 (L430-461), factor controls Table 2 (L514-554), position data Table 3 (L557-618), intramonthly pattern Table 4 (L621-668), anomaly categories Figure 5 (L672-717), t-statistic grouping Table 5 (L720-775), size/liquidity Table 6 (L784-810), conclusion (L928-943). Lines cited: L217-219, L338-342, L344-345, L450-454, L459-461, L538-545, L579-614, L637-638, L644-662, L682-688, L749-750, L754-757, L805-810.
