## Anomaly-Driven Demand (ADD) — Crowding as a Return Channel

### Thesis

When millions of factor investors mechanically rebalance the **same** published
anomaly portfolios at the **same** time (month-end), their coordinated *trading
flow* itself moves prices — independent of any new information. Anomalies
"discovered as passive predictors have become active agents in generating those
returns." This is a **flow/demand-pressure** channel, distinct from the
information-already-priced channel covered by the `priced-in-prohibition` rule
and [[priced-in-signals]].

### How ADD is measured (public data only)

1. For each of the **209 anomalies** in the Chen & Zimmermann open dataset
   ([openassetpricing.com](https://www.openassetpricing.com/)), sort stocks into
   quintiles each month.
2. For each stock, count **(new long-leg entries − new short-leg entries)** across
   all anomalies.
3. **ADD** = the month-over-month change in that net count. High ADD = a coming
   wave of mechanical buying; low ADD = coordinated selling.

### Key findings (from the post — treat as hypothetical until replicated)

> ⚠ AI-inferred: the figures below are transcribed from a Swedroe blog post
> digesting Posselt & Kjær (2026); we have not independently replicated them.

| Finding | Value |
|---|---|
| High-ADD vs low-ADD excess return | 6.62% → 10.65% monotonic; spread **4.03pp** (t ≈ 4.03) |
| Long-short ADD Sharpe | ≈ 0.61 |
| Alpha survival | Survives FF5 + momentum + first 3 PCs of anomaly returns |
| Timing | Generated in the **first ~6 trading days** of the month, **open-to-close (intraday)** |
| Price impact | **Permanent** (no 12-month reversal) → demand-based, not a liquidity blip |
| Cross-section | Stronger for **high-published-t** anomalies; near-zero for low-t |
| Size pattern | **U-shaped** — strongest in micro-cap and mega-cap, weakest in the middle |
| Feedback loop | returns → inflows → larger rebalancing flows → more price pressure → more returns |

### Why this matters to us

**Angle A — crowding/capacity warning (higher value, lower risk).** Our
leaderboard ranks many overlapping long-short factor strategies on backtested
Sharpe. ADD says a slice of those returns is mechanical crowding, concentrated
at month-start, strongest exactly where we are tempted to chase. It directly
compounds the multiple-testing problem: the more correlated published anomalies
we stack, the more our portfolio rides the same coordinated flow. This reinforces
the Vertox effective-strategy-count / deflated-Sharpe work ([#160]) — same
headline-Sharpe-overstatement theme, *different mechanism* (flow, not information).

**Angle B — ADD as a candidate signal (deferred).** ADD is buildable from free
public data (Chen-Zimmermann), fitting our free-tier posture. But it is yet
another long-short equity signal correlated with our existing ones, so it must be
budgeted against multiple testing ([#160], deflated Sharpe) before any reported
edge. Building it requires sourcing the 209-anomaly Chen-Zimmermann dataset, which
is **not yet in our data layer** — a separate scoped issue if pursued.

### Decision (2026-05-26)

Adopt **Angle A** now: the `priced-in-prohibition` rule gained a flow-pressure
(ADD) clause distinguishing demand-crowding from information-priced-in, with
required checks for month-start concentration, published-significance crowding,
capacity/reversal, and Turn-of-the-Month overlap ([#271]). Angle B (the ADD
signal + Chen-Zimmermann data layer) is parked pending a dedicated issue.

### Related

- [[priced-in-signals]] — the information-priced-in channel (this is the flow channel)
- [[taa-selection-research]], [[market-behavior-gap-analysis]] — adjacent crowding/capacity context
- [#160] — Vertox effective number of tested strategies / deflated Sharpe
- [#271] — Turn-of-the-Month overlay (the ~6-day month-start window ADD describes)

## Sources

- Larry Swedroe, "Where do returns actually come from in Factor Strategies? / When Everyone Trades the Same Factor Playbook" (2026-05-22), alphaarchitect.com — blog post digesting the paper below. Retrieved from a manual PDF save (live page Cloudflare-blocked).
- Posselt & Kjær (March 2026), "Anomaly-Driven Demand" (ADD) — the underlying paper.
- Chen & Zimmermann open anomaly dataset — [openassetpricing.com](https://www.openassetpricing.com/) (209 anomalies, free).
- Issue [#279] — gap analysis and decision record.
</content>
</invoke>
