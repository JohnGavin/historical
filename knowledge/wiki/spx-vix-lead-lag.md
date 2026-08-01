---
title: SPX ↔ VIX Lead-Lag and RSI(2) Filter Asymmetry
canonical_question: "Does SPX lead VIX, and is an SPX-based oversold filter better than a VIX-based one — and if so, why?"
status: active
fresh_until: 2027-08-01
consensus_level: split
sources:
  - aligrithm-spx-vix-leadlag-2026.md
compiled_by: orchestrator-tier
compiled_on: 2026-08-01
tags: [vix, spx, lead-lag, rsi, mean-reversion, regime, levy-area, volatility-hysteresis, aligrithm, falsification]
---

# SPX ↔ VIX Lead-Lag and RSI(2) Filter Asymmetry

A source claim ([aligrithm](../raw/aligrithm-spx-vix-leadlag-2026.md)) bundles two
separate propositions and presents them as one: that SPX *leads* VIX, and that
therefore an SPX-based oversold filter beats a VIX-based one. Tested against
8,351 trading days of our own data (SPY + FRED `VIXCLS`, 1993-02-01 → 2026-04-10,
`explorations/vix_spx_leadlag/`), **the filter claim holds and the causal claim
does not.** They are true and false for the same underlying reason, which is the
useful part.

`consensus_level: split` — we confirm one half of the source and contradict the other.

---

## Result 1 — the filter claim replicates (positive)

| condition | share of days | next-day SPX mean | win rate | next-day VIX mean | down-rate |
|---|---|---|---|---|---|
| SPX RSI(2) ≤ 20 | 27.8% | **+0.109%** | **55.6%** | **−0.168** | **57.6%** |
| VIX RSI(2) ≤ 20 | 35.7% | +0.041% | 54.4% | +0.076 | 50.5% |
| unconditional | — | +0.047% | 54.0% | +0.001 | 53.0% |

VIX-oversold is not merely weaker — its next-day SPX return (+0.041%) sits
*below* unconditional (+0.047%). Source reported 57.66% vs 55.51%; we get 55.6%
vs 54.4%. Same ordering, smaller gap, different sample and RSI smoothing.

## Result 2 — the causal claim does not replicate, and mildly reverses (negative)

Cross-correlation is overwhelmingly contemporaneous, and lead-lag is symmetric:

| lag k | `cor(spx_ret[t], vix_chg[t+k])` |
|---|---|
| −1 (VIX first) | +0.086 |
| **0** | **−0.792** |
| +1 (SPX first) | +0.106 |

Predictive regressions, each controlling for the target's own lag:

| direction | β | t | p | FPR @ equipoise | model R² |
|---|---|---|---|---|---|
| SPX_t → VIX_{t+1} | −0.289 | **−0.11** | 0.911 | n/a | 0.0183 |
| VIX_t → SPX_{t+1} | +0.0004 | **+3.15** | 0.0016 | 0.027 | 0.0079 |

SPX has **no** incremental power over tomorrow's VIX. VIX has modest but real
power over tomorrow's SPX — the reverse of the stated direction.

## Result 3 — why both hold: the two RSI conditions are nearly disjoint

This is the finding worth carrying forward. The two "filters" are not two sensors
on one market state; they describe **opposite** states and almost never co-occur.

| bucket | n | % days | next-day SPX | SPX win | next-day VIX | VIX down |
|---|---|---|---|---|---|---|
| neither | 3,200 | 38.3% | +0.008% | 52.5% | +0.051 | 51.8% |
| VIX oversold only | 2,824 | 33.8% | +0.040% | 54.4% | +0.083 | 50.5% |
| **SPX oversold only** | 2,170 | 26.0% | **+0.112%** | **55.8%** | **−0.176** | **58.1%** |
| both oversold | 154 | 1.8% | +0.065% | 53.9% | −0.053 | 50.6% |

- `cor(spx_rsi2, vix_rsi2) = −0.664`
- `P(VIX oversold | SPX oversold) = 0.066`
- overlap: 154 of 8,348 days (1.8%)

**SPX RSI(2) ≤ 20** means price just fell hard → VIX is *high* → the setup is a
panic bottom, and both SPX rebound and VIX decay follow.
**VIX RSI(2) ≤ 20** means VIX just fell hard → the panic already unwound → the
rebound is behind you.

So "SPX filters better" is not a statement about sensor quality. The two rules
select different days, and one of those day-sets happens to precede the
mean-reversion.

## Result 4 — Lévy area shows real ordering that is probably not tradeable

Using `hd_levy_area()` ([#605]; positive = first series leads):

| window | mean | fraction > 0 |
|---|---|---|
| 5d | +0.377 | 0.582 |
| 10d | +1.004 | 0.623 |
| 21d | +2.555 | 0.671 |
| 63d | +9.917 | 0.778 |

> ⚠ AI-inferred: the most plausible reading is the **volatility hysteresis loop**
> — price falls, VIX spikes fast, price recovers, VIX decays slowly. That
> asymmetric loop encloses signed area regardless of any exploitable lead, which
> is exactly why it coexists with the Result 2 null. Not independently verified
> against a hysteresis-specific test.

t-statistics are deliberately omitted: windows overlap n-deep, so effective
sample size is far below nominal ([#601]).

---

## Lessons learnt

**L1 — A mechanism is not a forecast.** "VIX is computed from SPX options, so
VIX reacts to SPX" is true by construction and says nothing about predictability.
A reaction that is instantaneous leaves nothing to forecast. The source treats
the mechanism as evidence for the forecast; the data separates them cleanly.

**L2 — When two filters are compared, check whether they select the same days.**
The bucket table (Result 3) took minutes and explained more than the headline
comparison did. A filter comparison without an overlap statistic is
under-specified. Generalises to any A-vs-B signal comparison.

**L3 — Contemporaneous dominance can hide the question.** At daily close, VIX is
computed from SPX options quoted at the same instant, so `cor = −0.79` at lag 0
is structural. Daily data **cannot** test an intraday causal claim; picking the
frequency to match the claim is a prerequisite, not a refinement.

**L4 — Path-geometry ordering ≠ predictive lead.** Lévy area found a strong,
monotone ordering signature in the same data where the regression found nothing.
Both are correct; they measure different things. Do not read a non-zero Lévy
area as a tradeable lead.

**L5 — Test what you can, and say what you cannot.** The source's headline is a
short-**VX-futures** backtest. We hold VIX *spot*. That claim was not tested and
is not disputed here — it is simply out of reach with our data.

## Live consequence for this project

`R/plan_avoid_worst.R` goes to cash on **absolute VIX level** thresholds
(`c(25, 30, 35, 40)`) — that is "use VIX to time SPX". Result 2 gives it modest
support (t = 3.15) rather than refutation, but the effect is small (model
R² 0.008) and this is the first direct test of the strategy's premise we have
run. A head-to-head against an SPX-drawdown trigger is tracked in [#611] N1.

## Limitations

- In-sample throughout; no train/test split, no walk-forward.
- Asymmetry regressors are 79% correlated (VIF ≈ 2.7), inflating SEs ~1.6×. The
  asymmetry survives; the coefficients are not precisely identified.
- Single market (US). No cross-geography replication — see
  `cross-geography-pervasiveness`.
- The SPX↔VIX relationship is among the most-watched in markets; any surviving
  edge must clear `priced-in-prohibition`'s incremental-power test, which
  Result 2 fails.

## Sources

- [aligrithm-spx-vix-leadlag-2026.md](../raw/aligrithm-spx-vix-leadlag-2026.md) — source claims and the author's own caveats
- `explorations/vix_spx_leadlag/` — `run.R`, `SUMMARY.md`, `results/run_output.txt` (reproducible: `nix develop . --command Rscript explorations/vix_spx_leadlag/run.R`)
- [historical#611](https://github.com/JohnGavin/historical/issues/611) — review issue and next steps
- [historical#605](https://github.com/JohnGavin/historical/issues/605) — `hd_levy_area()`, used in Result 4
- [historical#601](https://github.com/JohnGavin/historical/issues/601) — why Result 4's t-statistics are withheld

## Related

- [[walk-forward-correlation]] — same family of "is this edge real" diagnostics
- [[anomaly-driven-demand]] — crowding channel; relevant if any VIX-timing rule is widely traded
- [[regime-trend-following]] — regime classification, the natural consumer of Result 3
