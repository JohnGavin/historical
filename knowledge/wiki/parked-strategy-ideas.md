---
title: Parked Strategy Ideas (Low Priority, Not Tested)
canonical_question: "Which strategy ideas have we read about, decided not to work on now, and recorded so that nobody mistakes them for tested-and-failed or re-derives them from scratch?"
status: active
fresh_until: 2027-04-17
consensus_level: single-source
sources:
  - "#962"
  - "#496"
  - "algoadvantage-057"
  - "tradequantix-momentum-series"
compiled_by: orchestrator-tier
compiled_on: 2026-10-17
tags: [strategy-ideas, parked, backlog, not-tested, low-priority, governance]
---

# Parked Strategy Ideas (Low Priority, Not Tested)

**Nothing on this page has been tested.** A row here means "named in a source,
checked against the repo, not built". It is not a negative result. A negative
result needs a research-log hypothesis with a determinate status (`refuted`,
`inconclusive-underpowered`, ...), and none of these has one.

Adding a strategy is an [#496](https://github.com/JohnGavin/historical/issues/496)
decision (portfolio fit, and a named candidate to remove or downgrade). Parking
an idea here costs nothing and does not start that process.

## Ideas

| # | Idea | Where it came from | Repo status (grep-level, 2026-10-17) | Priority |
|---|---|---|---|---|
| P1 | SPY/TLT month-end rebalance trade | AlgoAdvantage #057 show notes | `R/plan_turn_of_month.R` does not mention TLT; no strategy | low |
| P2 | Bond end-of-month effect (the show notes mention an 18-month drawdown) | AlgoAdvantage #057 show notes | no strategy | low |
| P3 | Equity statistical arbitrage from a pairs universe | AlgoAdvantage #057 show notes | no pairs or stat-arb code found | low |
| P4 | Long volatility into earnings | AlgoAdvantage #057 show notes | no earnings-volatility code found | low |
| P5 | Cheap out-of-the-money puts as a hedge | AlgoAdvantage #057 show notes | only the CBOE `PPUT` index series exists, as a data row in `registry.R` | low |
| P6 | Pullback entry inside a momentum trade | TradeQuantiX Part 2 (USA pullback momentum) | no pullback strategy found in `R/plan_*.R` | low |
| P7 | Momentum plus low-volatility ranking sleeve | TradeQuantiX Parts 1 and 2 | no low-volatility ranking sleeve found | low |

## Why these are out of reach for now

- Options-based ideas (P4, P5) need an options data feed and a cost model we do
  not have.
- P1 and P2 sit next to the turn-of-month effect we already run; the value gate
  would ask what they add beyond it.
- P3 needs a point-in-time pairs universe and borrow costs.
- P6 and P7 are variants of momentum, which already has several entries on the
  leaderboard. The value gate asks for a candidate to remove.

These are reasons for low priority, not findings. Any of them could change
once a data source or a gap in the portfolio makes it worth a pre-registration.

## What to do when one of these is picked up

1. Write the pre-registration (`admission_preregister()`), which seals the
   mechanism (`counterparty`), the kill criterion and the expected Sharpe with
   its detection-power requirement. See `new-strategy-value-gate.md`.
2. Move the row's status here from "not started" to a link to the sealed
   hypothesis uuid.
3. Record the outcome in the research log whatever it is, including
   `refuted` and `inconclusive-underpowered`.

## Open question: one ledger for everything

The research log is the project's ledger of hypotheses and their outcomes, but
it holds 12 hypotheses today (10 are the same OLMAR-1 claim, with the
deprecated status `tested`) and no future ideas. Tracking strategies we work
on, those that failed, and those we may try later in one queryable place is
being worked out in [#962](https://github.com/JohnGavin/historical/issues/962).
Until that lands, this page is the only record of the parked ideas.

## Sources

- [Issue #962](https://github.com/JohnGavin/historical/issues/962) -- gap
  analysis of the TradeQuantiX momentum series and AlgoAdvantage #057 against
  our gates; Addendum B (row B9) lists P1 to P5, Addendum A the momentum
  variants P6 and P7.
- [Issue #496](https://github.com/JohnGavin/historical/issues/496) -- the
  new-strategy value gate.
- AlgoAdvantage #057, "The Questions that Change Everything" (Kris Longmore),
  https://algoadvantage.substack.com/p/the-questions-that-change-everything.
  Show notes only; no transcript was read.
- TradeQuantiX, "Momentum Mini-Portfolio Development", Parts 1 and 2,
  https://www.tradequantixnewsletter.com/ (saved copies read by the owner and
  checked in this session).
- Wiki: `new-strategy-value-gate.md`.
