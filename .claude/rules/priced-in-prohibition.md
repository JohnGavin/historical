---
name: priced-in-prohibition
description: Require evidence of incremental predictive power before using signals derived from publicly available information
type: rule
---

# Rule: Prohibit Acting on Priced-In Information

## Source

Swedroe evidence-based investing framework (wiki: `knowledge/wiki/swedroe-evidence-investing.md`, Gap 6).

## When This Applies

Any project constructing trading signals from publicly available information — macro indicators, earnings announcements, analyst consensus, news sentiment, sector rotations, or economic data releases.

## CRITICAL: Public Information Carries No Edge

A signal derived from information available to all market participants is already reflected in current prices. This is distinct from look-ahead bias (using future data) — it is about **currently available but already-priced** information.

Before incorporating a signal based on public data, require evidence that the signal provides **incremental** predictive power beyond what is already reflected in prices. The burden of proof is on the signal, not on the market.

## CRITICAL: Flow-Pressure Crowding (ADD) Is a Distinct Channel

"Priced-in" above is about **information** being already reflected in prices. There is a **second**, separate way published signals lose (or distort) their edge: **Anomaly-Driven Demand (ADD)**. When many factor investors mechanically rebalance the **same** published anomaly portfolios at the **same** time (month-end), their coordinated *trading flow* moves prices — independent of any new information. "Anomalies discovered as passive predictors become active agents generating those returns" (Kjær & Posselt 2025; digested in [[anomaly-driven-demand]]).

Why this matters for our leaderboard:

- A slice of a published anomaly's backtested return is **mechanical crowding**, not edge — concentrated in the first ~6 trading days of the month, strongest exactly where we are tempted to chase (high-published-t anomalies).
- This is the *demand-pressure* mechanism; the priced-in checks above test the *information* mechanism. **A signal can pass the information checks and still be contaminated by crowding flow.**
- Crowding compounds the multiple-testing problem in `backtest-robustness` / Vertox `K_eff_strat` ([#160]): the more correlated published anomalies we stack, the more our portfolio rides the same coordinated flow.

### Required when adding a published-anomaly signal

| Check | Question | Fail/flag condition |
|-------|----------|--------------------|
| Crowding concentration | Is the return concentrated in the month-start rebalance window (~first 6 trading days)? | If yes, the edge is partly coordinated flow, not persistent mispricing |
| Published-significance crowding | Is the anomaly high-published-t (widely traded)? | High-t anomalies attract the most ADD → most crowding contamination |
| Capacity / reversal | Is the price impact permanent (demand-based) or does it revert? | Permanent impact in crowded windows = capacity risk as more capital chases it |
| Turn-of-month overlap | Does the signal overlap our Turn-of-the-Month work ([#271])? | TOM overlays must be ADD-aware, not double-counting the same flow |

## Required Checks

| Check | Question | Fail condition |
|-------|----------|---------------|
| Information availability | Is this data available to institutional investors? | If yes, assume priced in |
| Incremental power | Does the signal predict returns **after** controlling for known factors (Fama-French, momentum, etc.)? | No residual alpha = priced in |
| Implementation edge | Is our edge in *processing speed* or *structural access*, not information content? | If edge is "we read the data" → no edge |
| Decay rate | Does the signal's predictive power decay within minutes/hours of release? | Fast decay = already being traded on |

## Forbidden Patterns

| Pattern | Why wrong |
|---------|-----------|
| "GDP growth is slowing, so short equities" | Consensus macro is fully priced |
| "Analyst consensus is bullish" | Consensus = priced in by definition |
| "This sector is overvalued based on P/E" | Relative valuation is the most-watched metric |
| Signal from a widely-followed indicator without decay analysis | No evidence of incremental power |
| Stacking many published high-t anomalies as if independent | Coordinated ADD flow + multiple-testing — see `K_eff_strat` ([#160]) |
| Treating an anomaly's month-start return as persistent edge | May be mechanical rebalancing flow (ADD), not mispricing |

## Acceptable Signals

| Type | Why it may work |
|------|----------------|
| Structural/behavioural anomalies with academic evidence across markets | Persistent mispricing documented over decades |
| Proprietary data not available to the market | Genuine information asymmetry |
| Speed advantage on public data (HFT context) | Edge is execution, not information |
| Cross-asset signals the market segments ignore | Institutional silos create blind spots |

## Related

- `look-ahead-bias-prevention` — covers temporal leakage; this rule covers information-already-priced
- `cross-geography-pervasiveness` — pervasiveness test strengthens evidence against data mining
- `backtest-robustness` — parameter sensitivity + `K_eff_strat` deflated-Sharpe; this rule adds information-content + flow-crowding scrutiny
- [[anomaly-driven-demand]] — wiki digest of Kjær & Posselt (2025) ADD; the flow-pressure channel
- [#160] — Vertox effective number of tested strategies / deflated Sharpe (crowding ↔ multiple-testing)
- [#271] — Turn-of-the-Month overlay (month-start return concentration; must be ADD-aware)
