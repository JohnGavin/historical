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

# Rule: Detection Power Is a First-Class Metric, Not a Diagnostic Column

Origin ([#726](https://github.com/JohnGavin/historical/issues/726): six of the eight
positive-Sharpe leaderboard strategies cannot be distinguished from zero by their own
samples; Value (HML) is 21× short) and the full evidence table live in
[`detection-power-required-details.md`](detection-power-required-details.md).

## When This Applies

Any claim that a strategy has an edge — a Sharpe, an alpha, an information ratio, a
hit rate above chance — made from a finite sample. That is every strategy row on
every leaderboard, every partition, and every new-strategy proposal.

## CRITICAL: State the required sample before reporting the observed effect

The failure mode is not computing a wrong number. It is reporting a correct number in
a format that implies it means something it does not.

> **A Sharpe reported without its detection requirement is an incomplete claim.**

The two belong adjacent. Separated by fifty columns, the first is read without the second.

## Required

| # | Requirement |
|---|---|
| 1 | Every positive-Sharpe row **must** carry a non-NA detection verdict. Enforced by QA gate **S20** (`qa_leaderboard_detection_power_values`). Three NA paths exist — `sharpe <= 0`, `months` missing, `hd_detection_power()` erroring — and the gate asserts the *property*, not any one path. |
| 2 | Where a strategy is underpowered, that fact is reported **beside** its Sharpe, not in a distant column. |
| 3 | NA on a **negative-Sharpe** row means *not applicable* (the one-sided test has no positive effect to detect). NA anywhere else means *not computed* and is a defect. These must not render identically — see [#728](https://github.com/JohnGavin/historical/issues/728). |
| 4 | A new strategy states its **expected** Sharpe and the sample it would need **before** being backtested, not after. Detection power is a design constraint, not a post-hoc autopsy. |
| 5 | Report the multiple-testing-corrected requirement alongside the single-test one. The single-test figure (`alpha = 0.05`) is the charitable case; if a strategy fails there, the correction is academic — but where it passes, the corrected figure is the one that matters. |

## Interaction with allocation

Detectability is one of the seven provenance facts in [#719](https://github.com/JohnGavin/historical/issues/719) Layer 2. The gating rule:

> **A strategy may not receive gross above 1.0× while `detection_underpowered` is
> TRUE or NA.**

This is not a claim that an underpowered strategy is *bad* — detection power is about what a sample can **show**, not what is **true**. The claim is that we cannot currently tell, and levering on what we cannot tell is the error.

## Interaction with the null-testing work

A signal-null test ([#718](https://github.com/JohnGavin/historical/issues/718)) on an underpowered sample is uninformative: a null that fails to reject is not reassuring. Detection power should gate **which strategies are worth running signal nulls on**. **A significance test conditioned on an undetectable effect returns a confident answer to a question the data cannot address.**

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

- `.claude/rules/fail-loud-not-null.md` — NA-as-silence; requirements 1 and 3 are that rule applied to the reporting layer
- `.claude/rules/backtest-robustness.md` — `K_eff_strat` / deflated Sharpe; the multiple-testing correction requirement 5 refers to
- `.claude/rules/underperformance-prior.md` — the complement: how long underperformance can run *without* being evidence against a strategy
- `.claude/rules/cross-geography-pervasiveness.md` — replication as the other answer to a sample too short to be decisive on its own
- `historicaldata::hd_detection_power()` — the implementation, with its derivation
