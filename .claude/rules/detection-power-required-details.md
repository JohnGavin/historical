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
`hd_detection_power()` columns showed that **six of the eight positive-Sharpe
strategies on the leaderboard cannot be distinguished from zero by their own
samples**, two of them by more than an order of magnitude:

| strategy | sharpe | have (yrs) | need (yrs) | shortfall |
|---|---:|---:|---:|---:|
| Value (HML) | 0.068 | 62.7 | 1337.1 | 21× |
| Factor DRIF | 0.076 | 57.6 | 1067.2 | 19× |
| Mom Pre-Peak | 0.226 | 53.1 | 121.1 | 2.3× |
| Risk State | 0.252 | 33.2 | 97.4 | 2.9× |
| LTR | 0.330 | 21.2 | 56.9 | 2.7× |
| Managed Futures | 0.477 | 18.9 | 27.3 | 1.4× |

Only Avoid Worst (0.620, needs 16.1 of 33.1 available) and OLMAR-1 (0.780, needs 10.2
of 16.1) clear the bar.

Value (HML) has one of the longest samples in the repo and is still 21× short. No
attainable sample fixes that. The metric had existed as leaderboard column 60 of 61
and had never been read.

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
