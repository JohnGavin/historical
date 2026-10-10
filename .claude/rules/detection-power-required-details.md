---
paths:
  - "R/plan_leaderboard.R"
  - "R/plan_qa_gates.R"
  - "R/plan_backtest.R"
  - "R/plan_stock_backtest.R"
  - "R/plan_multi_strategy.R"
  - "R/plan_kelly*.R"
  - "R/plan_leverage.R"
  - "R/plan_portfolio_opt.R"
  - "packages/historicaldata/R/hd_detection_power.R"
  - "packages/historicaldata/R/hd_prob_sharpe_positive.R"
  - "docs/leaderboard.qmd"
  - "docs/evidence.qmd"
---

# Details: Detection Power — origin evidence and interaction notes

Companion to [`detection-power-required`](detection-power-required.md). That file
holds every normative requirement; this one holds the origin data and the
longer reasoning. Nothing here adds or relaxes a requirement.

## Source

[#726](https://github.com/JohnGavin/historical/issues/726). The first live run of the
`hd_detection_power()` columns (August 2026) showed that **six of the eight
positive-Sharpe strategies on the leaderboard cannot be distinguished from zero by
their own samples**. Value (HML) was 21× short (needs 1337.1 years, has 62.7) and
Factor DRIF 19× short. No attainable sample fixes that. The metric had existed as
leaderboard column 60 of 61 and had never been read.

**The original table is not reproduced here.** It was hand-typed, and it went stale:
the return-basis fixes ([#919](https://github.com/JohnGavin/historical/issues/919),
[#937](https://github.com/JohnGavin/historical/issues/937)) and the Avoid Worst
series fix ([#921](https://github.com/JohnGavin/historical/pull/921) — the old 0.620
was the hindsight "Remove 10 Worst" scenario) changed most of its Sharpe values,
so its verdicts no longer held. The source of truth is the leaderboard's
`detection_min_n_years`, `detection_min_n_years_mt` and `detection_underpowered`
columns; read them rather than a copy.

Snapshot from the rebuilt store, **2026-10-10**, `Full Period` rows with Sharpe above
zero (13 rows; `have` and `need` in years; `need (mt)` is the multiple-testing-corrected
requirement). Dated evidence, not a maintained table:

| strategy | sharpe | have | need | need (mt) | single-test verdict |
|---|---:|---:|---:|---:|---|
| Mom 12-2 | 0.049 | 53.2 | 2575.1 | 5224.7 | 48.4× short |
| Value (HML) | 0.068 | 62.7 | 1337.1 | 2713.0 | 21.3× short |
| PSO Optimal | 0.130 | 16.3 | 367.3 | NA | 22.6× short |
| CMR | 0.250 | 25.9 | 98.9 | 200.7 | 3.8× short |
| Avoid Worst | 0.250 | 33.1 | 98.9 | 200.7 | 3.0× short |
| Risk State | 0.252 | 33.2 | 97.4 | 197.5 | 2.9× short |
| CMR Conditioned | 0.352 | 25.7 | 49.9 | 101.3 | 1.9× short |
| Factor MAX | 0.391 | 61.7 | 40.5 | 82.1 | powered |
| LTR | 0.430 | 21.2 | 33.5 | 68.0 | 1.6× short |
| Mom Pre-Peak | 0.452 | 53.2 | 30.3 | 61.5 | powered |
| Managed Futures | 0.477 | 18.9 | 27.3 | 55.3 | 1.4× short |
| Factor DRIF | 0.499 | 57.6 | 24.9 | 50.5 | powered |
| OLMAR-1 | 0.780 | 16.1 | 10.2 | 20.6 | powered |

Nine of the 13 are underpowered at the single-test bar. Of the four that pass it, only
Factor DRIF also passes the multiple-testing-corrected bar (needs 50.5, has 57.6);
Factor MAX, Mom Pre-Peak and OLMAR-1 do not. `have` for the daily strategies (CMR,
CMR Conditioned, Avoid Worst, Risk State, OLMAR-1) is observations / 252; the
store's own `detection_underpowered` flag agrees with have-versus-need on all 13
rows. This snapshot is taken after [#946](https://github.com/JohnGavin/historical/pull/946),
which stopped the rf join dropping trailing observations from the excess-basis
Mom and CMR series (their `have` now equals the deflated-Sharpe path's `T_obs`);
no verdict changed. CMR Conditioned is a blend basis and still loses its trailing
rows to the rf trim, so its `have` is shorter than CMR's.

Risk State is the row worth remembering. It first appeared as *not computable* — its
`months` arrived NA because `calc_metrics()` computed `n_obs` and discarded it one
line before returning. Filling that blank did not add a reassuring seventh row; it
added a sixth adverse one. **The NA was standing in for a verdict, and the verdict was
against us.** That is the argument for requirement 1 in a single case.

## Why the format matters

The failure mode is not computing a wrong number. It is reporting a correct number in
a format that implies it means something it does not. A Sharpe of 0.068 with a
confidence interval, a p-value and a rank position is presented as a measurement. On
a sample 21× too short it is closer to a coin flip with three decimal places. The
Sharpe and its detection requirement belong adjacent; separated by fifty columns, the
first is read without the second.

## Interaction with allocation — reasoning

Detectability is one of the seven provenance facts in
[#719](https://github.com/JohnGavin/historical/issues/719) Layer 2.

The gating rule is not a claim that an underpowered strategy is *bad*. Detection
power is about what a sample can **show**, not about what is **true** — a genuine
0.07 Sharpe edge remains an edge whether or not 62 years can prove it. The claim is
narrower: **we cannot currently tell, and levering on what we cannot tell is the
error.** The right failure message is not "CMR is bad" but "we do not yet know CMR
well enough to lever it."

## Interaction with the null-testing work

A signal-null test ([#718](https://github.com/JohnGavin/historical/issues/718)) on an
underpowered sample tells you close to nothing: the test has no power to reject on
the *real* signal either, so a null that fails to reject is uninformative rather than
reassuring. Detection power should gate **which strategies are worth running signal
nulls on** — otherwise the null framework spends its budget on samples that cannot
answer.

The same logic applies to any significance machinery. **A significance test
conditioned on an undetectable effect returns a confident answer to a question the
data cannot address.**

## Worked example for "weakening S20"

PR #727's Risk State root-cause fix is the worked example of fixing the data rather
than the gate.

## Related issues

- [#726](https://github.com/JohnGavin/historical/issues/726) — the finding
- [#728](https://github.com/JohnGavin/historical/issues/728) — rigour-column coverage
- [#719](https://github.com/JohnGavin/historical/issues/719) — provenance facts gating the allocator
- [#718](https://github.com/JohnGavin/historical/issues/718) — signal nulls
- [#711](https://github.com/JohnGavin/historical/issues/711) — origin of the diagnostic
