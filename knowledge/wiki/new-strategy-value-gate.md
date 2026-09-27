---
title: New-Strategy Value Gate
canonical_question: "What is the advisory governance framework for admitting new strategies into the leaderboard, how does pre-registration guard against post-hoc rationalisation, and how does the gate distinguish a determinate mixed result from a check that could not be computed at all?"
status: active
fresh_until: 2027-03-01
consensus_level: direct
sources:
  - "#496"
  - "#902"
  - "#511 (superseded)"
compiled_by: orchestrator-tier
compiled_on: 2026-09-26
tags: [governance, strategy-admission, multiple-testing, pre-registration, advisory-gate, incremental-sharpe, diversification, crowding, detection-power, research-log]
---

# New-Strategy Value Gate

## Sources

- [Issue #496](https://github.com/JohnGavin/historical/issues/496) -- origin;
  advisory gate scorer + admission pre-registration
- [Issue #902](https://github.com/JohnGavin/historical/issues/902) -- adds
  `counterparty` and `kill_criterion` fields to the pre-registration
- [PR #511](https://github.com/JohnGavin/historical/pull/511) -- first
  implementation; **superseded** by the PR this page documents (2026-09-26
  review found three defects, fixed below)
- Project rules: `.claude/rules/detection-power-required.md`,
  `.claude/rules/research-log-honesty.md`, `.claude/rules/fail-loud-not-null.md`
- Code: `packages/historicaldata/R/strategy_value_gate.R`,
  `packages/historicaldata/R/admission_preregister.R`,
  `R/plan_strategy_correlation.R` (canonical `HD_REDUNDANCY_THRESH`)
- [Issue #270](https://github.com/JohnGavin/historical/issues/270) -- leaderboard governance (parent)
- [Issue #482](https://github.com/JohnGavin/historical/issues/482) -- expectation-vs-actual retro (future phase)

---

## What changed from PR #511, and why

PR #511 implemented the 5-check scorer and a bespoke `strategy_admission`
DuckDB table. A 2026-09-26 review found three defects that this
implementation fixes:

| Defect in #511 | Why it mattered | Fix here |
|---|---|---|
| `hd_admission_register()`'s upsert-by-strategy silently overwrote `hypothesis`/`expected_*` on re-registration, with no seal and no audit trail | Exactly the "resulting"/post-hoc-rationalisation failure pre-registration exists to prevent (`.claude/rules/research-log-honesty.md`, `.claude/rules/resulting-prohibition.md`) -- nothing stopped an expectation being quietly reworded after an outcome was known | Pre-registration now writes a **sealed** row (`hd_rlog_seal()`) to the existing research log; a sealed claim can never be silently overwritten -- re-registering aborts unless `revises = TRUE`, which creates a NEW row linked via `parent_uuid`, never an edit |
| Overall verdict collapsed "mixed pass/fail" and "a check could not be computed" into one label, `"research_only"` | Violates `.claude/rules/checks-must-distinguish-unknown.md` -- a reader could not tell "the evidence genuinely disagrees" from "we don't actually know" | Four-state verdict: `"admit"` / `"reject"` / `"mixed"` (all determinate) vs. `"indeterminate"` (>=1 required check is `NA` -- reported via `verdict_reason` naming which) |
| No detection-power check | `.claude/rules/detection-power-required.md` requires stating expected Sharpe vs. required sample before trusting a backtest | New `detection_power` check inside the scorer (candidate's own Sharpe vs. `hd_detection_power()`'s requirement, on the realised sample) **and** a pre-registration-time detection-power calculation (expected Sharpe vs. required sample, stated before the candidate is even backtested -- requirement 4) |
| `corr_threshold = 0.80` re-typed as a literal, duplicating `R/plan_strategy_correlation.R`'s `REDUNDANCY_THRESH` | Two independently-maintained copies of the same threshold drift silently | Single home: `historicaldata::HD_REDUNDANCY_THRESH` (exported constant in the package); both the gate's default `corr_threshold` and `R/plan_strategy_correlation.R`'s `REDUNDANCY_THRESH` read the same value |

The bespoke `strategy_admission` table is **removed entirely** -- there is no
migration path for it (#511 was never merged), so there is no data to carry
forward.

---

## Rationale: Why a Governance Gate?

Each time a new strategy is added to the leaderboard, the multiple-testing
adjustment must account for it. The effective number of tested strategies
(`K_eff_strat`, Vertox #160) grows with each addition, and the deflated Sharpe
threshold tightens accordingly. Without a gate, the analyst faces three problems:

1. **Mechanical admission inflates K_eff_strat.** A near-duplicate of an existing
   strategy adds almost no new information but counts as an additional test,
   shrinking the deflated Sharpe threshold for all strategies.
2. **Post-hoc rationalisation.** Without pre-registration, expected metrics are
   implicitly set after seeing results -- defeating the purpose of a Sharpe-based
   admission criterion.
3. **Undetectable claims get admitted anyway.** A candidate can clear every
   correlation/diversification threshold on a sample too short to actually
   distinguish its claimed Sharpe from noise (`.claude/rules/detection-power-required.md`).

> ⚠ AI-inferred: The link between admission governance and deflated Sharpe
> threshold tightening follows from the Vertox K_eff_strat definition, but the
> specific numerical impact on per-strategy thresholds depends on the existing
> correlation structure and is not computed here.

---

## The Checks

`hd_strategy_value_gate(candidate, existing, ...)` scores a candidate
strategy's returns against an existing portfolio's returns on **four
quantitative checks** (which vote on the overall verdict) plus **three
advisory checks** (reported, never voted):

### Quantitative (vote on the verdict)

1. **Similarity** -- max \|Pearson rho\| vs every existing strategy. Fails at
   `>= HD_REDUNDANCY_THRESH` (0.80, the single canonical value shared with
   `R/plan_strategy_correlation.R`'s leaderboard redundancy flag).
2. **Incremental Sharpe** -- `Sharpe(equal-weight candidate + existing) -
   Sharpe(equal-weight existing)`, matching `strat_corr_augment` in
   `plan_strategy_correlation.R` exactly. Positive = candidate adds value.
3. **Diversification (EW)** -- equal-weight annualised variance reduction
   (without minus with the candidate). Positive = candidate reduces risk.
4. **Detection power** -- the candidate's OWN standalone annualised Sharpe,
   checked against [`hd_detection_power()`](../../packages/historicaldata/R/hd_detection_power.R)'s
   required sample at the realised `n_obs`. Three outcomes, matching
   `detection-power-required.md` requirement 3's own three-state
   distinction:
   - `"pass"` -- own Sharpe positive, sample clears the (optionally
     Bonferroni-corrected) requirement.
   - `"fail"` -- own Sharpe positive, sample is short (underpowered).
   - `"n_a"` -- own Sharpe is zero or negative: there is no positive effect
     to test for. This is a legitimate NOT-APPLICABLE outcome, deliberately
     distinct from...
   - `"na"` -- the candidate's own Sharpe itself could not be computed (e.g.
     zero variance). This is the ONLY detection-power outcome that can make
     the overall verdict `"indeterminate"`.

### Advisory (reported, not voted)

5. **Diversification (GMV)** -- global minimum-variance variance reduction
   via `hd_min_var_weights()`; `"na"` when the covariance matrix is singular.
6. **Crowding** -- caller-supplied published-t or logical flag (ADD
   analysis, `[[anomaly-driven-demand]]`); not computed inside the gate.
7. **Robustness** -- caller-supplied `TRUE`/`FALSE`/`NA` from the
   CPCV/falsification gauntlet.

---

## Overall Verdict Logic (Four States, Never Three)

The four quantitative checks vote:

| Condition on the 4 quantitative checks | Overall | Determinate? |
|---|---|---|
| Any one is `"na"` (could not be computed) | `"indeterminate"` | **No** -- `verdict_reason` names which check(s) |
| All four `"pass"` | `"admit"` | Yes |
| All four `"fail"`/`"n_a"` | `"reject"` | Yes |
| Some pass, some fail/n_a, none `"na"` | `"mixed"` | Yes -- more analysis will not change this; a different candidate or portfolio would |

`"indeterminate"` is never collapsed with `"mixed"` -- a reader who sees
`"mixed"` knows the evidence genuinely disagrees; a reader who sees
`"indeterminate"` knows a required input simply was not computable (see
`.claude/rules/checks-must-distinguish-unknown.md`).

---

## Pre-Registration via the Research Log (Sealed, Never Silently Overwritten)

`hd_admission_preregister()` records an admission hypothesis as a row in the
project's existing research log (`hd_rlog_*`, `research_log.R`) rather than a
bespoke table -- the research log already has exactly the sealing and
lineage machinery pre-registration needs.

Field mapping onto the `hypotheses` schema:

| `hypotheses` column | Admission meaning |
|---|---|
| `economic_claim` | The admission hypothesis (free-text rationale) |
| `dependent_var` | Fixed: `"portfolio_incremental_sharpe"` -- admission is a claim about the PORTFOLIO's risk-adjusted return, not the candidate's own return |
| `predictor` | The candidate strategy identifier |
| `sample_spec` | The expected target regime, where supplied |
| `null_hypothesis` | Fixed, standard null for this hypothesis class |
| `status` | `hd_rlog_statuses()` vocabulary; `"proposed"` at registration |
| `extra_json` | Everything the schema has no column for: `reviewer`, `expected_incr_sharpe`, `expected_var_reduction`, `expected_target_regime`, `expected_max_corr`, `counterparty` (#902), `kill_criterion` (#902), `expected_sharpe` + its detection-power requirement, and the gate result -- tagged `kind = "strategy_admission"` |

**Sealed at inception, never silently overwritten.** `hd_admission_preregister()`
calls [`hd_rlog_seal()`](../../packages/historicaldata/R/research_log_seal.R)
by default. If a sealed admission hypothesis already exists for the
strategy, re-registering **aborts** unless `revises = TRUE` is passed, in
which case a NEW row is written with `parent_uuid` pointing at the sealed
row it revises. There is no UPDATE path anywhere in this module -- the
research log is append-only, so "never silently overwritten" is true by
construction, not merely by policy.

**#902 fields.** `counterparty` (who is expected to be on the other side of
this trade, and why they are willing to give up the edge -- "If I can't name
the mechanism and the counterparty, I don't have an edge") and
`kill_criterion` (a machine-checkable withdrawal condition, stated before
admission) are recorded alongside the existing expected-metric fields.

**Detection power at pre-registration time (requirement 4).** When
`expected_sharpe` is supplied, `hd_admission_preregister()` calls
`hd_detection_power()` immediately and records the required sample (in
years, both uncorrected and Bonferroni-corrected) -- stated BEFORE the
strategy is backtested, not derived afterwards from whatever sample
happened to be available.

`hd_admission_read()` finds every `hypotheses` row tagged
`kind = "strategy_admission"` and unpacks the admission-specific fields into
columns. A revised strategy's full history (oldest first, linked via
`parent_uuid`) is always retrievable -- nothing is ever overwritten in
place.

---

## Advisory-First Stance

This gate remains advisory, matching #511's Phase 1 scope:
- The gate records a verdict and warns via `cli::cli_warn()` on
  `"indeterminate"`; it never calls `stop()` on a failing or indeterminate
  check.
- It is NOT wired into `docs/_targets.R` or any QA gate target -- a future
  phase may add candidate-vs-admitted separation to
  `qa_leaderboard_coverage` (S7) and a pipeline-blocking target, but that is
  explicitly out of scope here.
- The expectation-vs-actual retro report (#482) -- comparing pre-registered
  expectations to realised metrics -- remains future work; the sealed,
  lineage-linked research-log rows this PR writes are exactly what that
  report will read.

## Connection to Crowding, Multiple Testing, and Detection Power

- **Multiple testing (#160):** each admitted strategy raises K_eff_strat,
  tightening the deflated Sharpe threshold. The similarity check prevents
  near-duplicates from padding K_eff_strat without genuine independence.
- **ADD flow ([[anomaly-driven-demand]]):** the crowding check asks whether
  the strategy's backtested return is partly mechanical month-start
  rebalancing pressure from other investors tracking the same published
  anomaly.
- **Detection power (`.claude/rules/detection-power-required.md`):** a
  strategy that clears every correlation/diversification threshold on a
  sample too short to detect its own claimed Sharpe is not a validated
  strategy -- it is an unresolved coin flip with decimal places. The
  detection-power check makes that distinction part of the admission
  decision itself, not a separate audit performed later.

## Implementation Notes

- `hd_strategy_value_gate()` and `HD_REDUNDANCY_THRESH` are in
  `packages/historicaldata/R/strategy_value_gate.R`.
- `hd_admission_preregister()` and `hd_admission_read()` are in
  `packages/historicaldata/R/admission_preregister.R`.
- Both build entirely on existing infrastructure
  (`hd_min_var_weights()`, `hd_detection_power()`, `hd_rlog_*`,
  `hd_rlog_seal()`) -- no new database table, no new storage format.
- `jsonlite` (Suggests) serialises the `extra_json` payload and, when a
  gate result is supplied, the gate detail tibble.
