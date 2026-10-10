# Rule: Detection Power Is a First-Class Metric, Not a Diagnostic Column

## Source

[#726](https://github.com/JohnGavin/historical/issues/726). The first live run of the
`hd_detection_power()` columns (August 2026) showed that **six of the eight
positive-Sharpe strategies on the leaderboard cannot be distinguished from zero by
their own samples**. Value (HML) was 21× short (needs 1337.1 years, has 62.7) and
Factor DRIF 19× short. No attainable sample fixes that. The metric had existed as
leaderboard column 60 of 61 and had never been read.

**That table is not reproduced here.** It was hand-typed, and it went stale: the
return-basis fixes ([#919](https://github.com/JohnGavin/historical/issues/919),
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
against us.** That is the argument for requirement 1 below in a single case.

## When This Applies

Any claim that a strategy has an edge — a Sharpe, an alpha, an information ratio, a
hit rate above chance — made from a finite sample. That is every strategy row on
every leaderboard, every partition, and every new-strategy proposal.

## CRITICAL: State the required sample before reporting the observed effect

The failure mode is not computing a wrong number. It is reporting a correct number in
a format that implies it means something it does not. A Sharpe of 0.068 with a
confidence interval, a p-value and a rank position is presented as a measurement. On
a sample 21× too short it is closer to a coin flip with three decimal places.

> **A Sharpe reported without its detection requirement is an incomplete claim.**

The two belong adjacent. Separated by fifty columns, the first is read without the
second — which is exactly what happened for as long as the column existed.

## Required

| # | Requirement |
|---|---|
| 1 | Every positive-Sharpe row **must** carry a non-NA detection verdict. Enforced by QA gate **S20** (`qa_leaderboard_detection_power_values`). Three NA paths exist — `sharpe <= 0`, `months` missing, `hd_detection_power()` erroring — and the gate asserts the *property*, not any one path. |
| 2 | Where a strategy is underpowered, that fact is reported **beside** its Sharpe, not in a distant column. |
| 3 | NA on a **negative-Sharpe** row means *not applicable* (the one-sided test has no positive effect to detect). NA anywhere else means *not computed* and is a defect. These must not render identically — see [#728](https://github.com/JohnGavin/historical/issues/728). |
| 4 | A new strategy states its **expected** Sharpe and the sample it would need **before** being backtested, not after. Detection power is a design constraint, not a post-hoc autopsy. |
| 5 | Report the multiple-testing-corrected requirement alongside the single-test one. The single-test figure (`alpha = 0.05`) is the charitable case; if a strategy fails there, the correction is academic — but where it passes, the corrected figure is the one that matters. |

## Interaction with allocation

Detectability is one of the seven provenance facts in
[#719](https://github.com/JohnGavin/historical/issues/719) Layer 2. The gating rule
that follows from #726:

> **A strategy may not receive gross above 1.0× while `detection_underpowered` is
> TRUE or NA.**

This is not a claim that an underpowered strategy is *bad*. Detection power is about
what a sample can **show**, not about what is **true** — a genuine 0.07 Sharpe edge
remains an edge whether or not 62 years can prove it. The claim is narrower and much
harder to argue with: **we cannot currently tell, and levering on what we cannot tell
is the error.** The right failure message is not "CMR is bad" but "we do not yet know
CMR well enough to lever it."

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

## Forbidden Patterns

| Pattern | Why wrong | Fix |
|---|---|---|
| Ranking strategies by Sharpe without showing which are detectable | Implies a comparability the power calculation denies | Report the verdict beside the rank |
| Treating a blank rigour cell as "not applicable" | It usually means "not computed" — the opposite claim | Distinguish the two (#728) |
| "The sample is short but the Sharpe is high, so it's fine" | High Sharpe *lowers* the requirement, but the arithmetic decides, not the intuition | Compute `T_min`; it is one function call |
| Allocating gross on an underpowered Sharpe | Sizing on a number the sample cannot support | #719 Layer 2 gate |
| Weakening S20 so the current data passes | The gate being right and the data being wrong is the *correct* state | Fix the data; PR #727's Risk State root-cause fix is the worked example |
| Adding a strategy, then asking whether it was detectable | Post-hoc; the answer arrives after the effort is spent | Requirement 4 — state it up front |

## Self-test

Before publishing or acting on any reported edge:

> **How long a sample would this effect need, and do we have it?**

If that question has not been answered numerically, the edge has not been reported —
only its point estimate has.

## Related

- `.claude/rules/fail-loud-not-null.md` — NA-as-silence; requirements 1 and 3 are that
  rule applied to the reporting layer
- `.claude/rules/backtest-robustness.md` — `K_eff_strat` / deflated Sharpe; the
  multiple-testing correction requirement 5 refers to
- `.claude/rules/underperformance-prior.md` — the complement: how long underperformance
  can run *without* being evidence against a strategy
- `.claude/rules/cross-geography-pervasiveness.md` — replication as the other answer to
  a sample too short to be decisive on its own
- `historicaldata::hd_detection_power()` — the implementation, with its derivation
- [#726](https://github.com/JohnGavin/historical/issues/726) — the finding
- [#728](https://github.com/JohnGavin/historical/issues/728) — rigour-column coverage
- [#719](https://github.com/JohnGavin/historical/issues/719) — provenance facts gating the allocator
- [#718](https://github.com/JohnGavin/historical/issues/718) — signal nulls
- [#711](https://github.com/JohnGavin/historical/issues/711) — origin of the diagnostic
