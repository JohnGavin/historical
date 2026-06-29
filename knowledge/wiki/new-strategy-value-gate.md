---
title: New-Strategy Value Gate
canonical_question: "What is the advisory governance framework for admitting new strategies into the leaderboard, and how does pre-registration of expected metrics guard against post-hoc rationalisation?"
status: active
fresh_until: 2027-01-01
consensus_level: direct
sources:
  - "#496"
compiled_by: claude-sonnet-4-6
compiled_on: 2026-06-29
tags: [governance, strategy-admission, multiple-testing, pre-registration, advisory-gate, incremental-sharpe, diversification, crowding]
---

# New-Strategy Value Gate

## Sources

- [Issue #496](https://github.com/JohnGavin/historical/issues/496) — origin; Phase 1 = advisory gate scorer + admission pre-registration
- Project rule: `.claude/rules/new-strategy-value-gate.md`
- Related: `R/plan_strategy_correlation.R` (incremental Sharpe definition), `packages/historicaldata/R/strategy_value_gate.R`, `packages/historicaldata/R/registry_admission.R`
- [Issue #270](https://github.com/JohnGavin/historical/issues/270) — leaderboard governance (parent)
- [Issue #482](https://github.com/JohnGavin/historical/issues/482) — expectation-vs-actual retro (Phase 3)

---

## Rationale: Why a Governance Gate?

Each time a new strategy is added to the leaderboard, the multiple-testing
adjustment must account for it. The effective number of tested strategies
(`K_eff_strat`, Vertox #160) grows with each addition, and the deflated Sharpe
threshold tightens accordingly. Without a gate, the analyst faces two problems:

1. **Mechanical admission inflates K_eff_strat.** A near-duplicate of an existing
   strategy adds almost no new information but counts as an additional test,
   shrinking the deflated Sharpe threshold for all strategies.

2. **Post-hoc rationalisation.** Without pre-registration, expected metrics are
   implicitly set after seeing results — defeating the purpose of a Sharpe-based
   admission criterion.

> ⚠ AI-inferred: The link between admission governance and deflated Sharpe
> threshold tightening follows from the Vertox K_eff_strat definition, but the
> specific numerical impact on per-strategy thresholds depends on the existing
> correlation structure and is not computed here.

---

## The 5 Checks

### Check 1: Similarity (correlation_max)

Computes the maximum absolute Pearson correlation of the candidate against every
existing strategy. If `correlation_max >= corr_threshold` (default 0.80), the
check fails.

A highly correlated candidate that also has lower incremental Sharpe is strictly
worse for the portfolio than the strategy it resembles.

### Check 2: Incremental Sharpe

Defined to match `strat_corr_augment` in `plan_strategy_correlation.R`:

```
Sharpe(equal-weight candidate + existing) − Sharpe(equal-weight existing only)
```

Positive = candidate improves the equal-weight portfolio. Negative = portfolio
performs better without the candidate.

> ⚠ AI-inferred: The equal-weight portfolio is used here for consistency with
> the leaderboard's `strat_corr_augment` target. A GMV-weighted incremental
> Sharpe would be more efficient in theory, but could mask concentration issues.

### Check 3: Diversification (variance reduction)

Two variants are computed:

**Equal-weight (EW):** `var(EW existing) − var(EW existing + candidate)`. Positive
when the candidate reduces portfolio variance.

**Global minimum-variance (GMV):** variance under GMV weights with vs without the
candidate, using `hd_min_var_weights()`. Computed via `tryCatch` — "na" if the
covariance matrix is singular (e.g. too few observations for the number of strategies).

### Check 4: Crowding (advisory)

Caller-supplied: either a logical flag or a published-t statistic (> 3 = high
crowding). Not computed inside the gate — the caller runs ADD analysis per
[[anomaly-driven-demand]] before calling. "na" when not supplied.

High crowding (`"flag"`) does not block admission but is recorded and should
trigger increased scrutiny under `priced-in-prohibition`.

### Check 5: Robustness (advisory)

`robustness_pass = TRUE/FALSE/NA`. The caller runs the CPCV/falsification gauntlet
and supplies the binary verdict. "na" when not yet run. Does not block admission
but is pre-registered for the expectation-vs-actual retro.

---

## Overall Verdict Logic

| Outcome of checks 1–3 | Overall |
|----------------------|---------|
| All three fail | `"reject"` |
| All three pass | `"admit"` |
| Mixed (any fail or "na" in checks 1–3) | `"research_only"` |

The verdict is stored in `attr(result, "overall")` on the tibble. The gate is
advisory: `"reject"` + `override = TRUE` admits the strategy with documented reason.

---

## Pre-Registration and Expectation-vs-Actual

The `strategy_admission` table in registry.duckdb stores expected metrics at
admission time — before realised performance is available. The pre-registration
includes:

| Column | Purpose |
|--------|---------|
| `expected_incr_sharpe` | Pre-commit to the minimum improvement expected |
| `expected_var_reduction` | Pre-commit to the diversification benefit expected |
| `expected_target_regime` | Declare which market regime the strategy is designed for |
| `expected_max_corr` | Ceiling on expected correlation with existing strategies |
| `hypothesis` | One-paragraph rationale (evidence-based, not outcome-based) |
| `reviewer` | Accountable person at admission time |

**Idempotency contract:** one row per strategy (upsert-by-strategy). On re-registration,
`admission_uuid` and `admitted_at` are preserved; expectations are updated. This
means the original admission timestamp is never lost, but expectations can be revised
with full audit trail (the update IS visible as a new `reviewer` + `hypothesis`).

Phase 3 (#482) will compare `expected_*` to realised metrics, feeding into
`resulting-prohibition` checks.

---

## Advisory-First Stance

Phase 1 (this feature) is purely advisory:
- Gate records verdict + warns via `cli::cli_warn()`
- Does NOT block `tar_make()` or `devtools::check()`
- Does NOT gate any existing `qa_leaderboard_coverage` target

Phase 2 (separate PR, issue #496) will:
- Add candidate-vs-admitted separation in `qa_leaderboard_coverage`
- Wire the gate result into the pipeline as a blocking target

Phase 3 (#482) will:
- Implement the expectation-vs-actual retro report
- Retrospectively apply to #489 Value/Managed-Futures strategies

---

## Connection to Crowding and Multiple Testing

The gate connects three related issues:

- **Multiple testing (#160):** each admitted strategy raises K_eff_strat, tightening
  the deflated Sharpe threshold. Check 1 (similarity) prevents near-duplicates from
  padding K_eff_strat without genuine independence.

- **ADD flow ([[anomaly-driven-demand]]):** Check 4 (crowding) asks whether the
  strategy's backtested return is partly mechanical month-start rebalancing pressure
  from other investors tracking the same published anomaly. A high-published-t
  anomaly concentrated in the first 6 trading days of the month warrants extra scrutiny.

- **Covariance estimation ([[covariance-estimation-wide-data]]):** Check 3b (GMV)
  uses `hd_min_var_weights()`, which fails gracefully on singular covariance (the
  wide-data regime). When the covariance is invertible, the GMV check provides a
  more efficient diversification signal than the EW check.

---

## Implementation Notes

- `hd_strategy_value_gate()` is in `packages/historicaldata/R/strategy_value_gate.R`.
- `hd_admission_init()`, `hd_admission_register()`, `hd_admission_read()` are in
  `packages/historicaldata/R/registry_admission.R`.
- The `strategy_admission` table lives in the same `registry.duckdb` file as `bt.*`
  and `art.*` tables.
- `jsonlite` (Suggests) is used to serialise the gate_result tibble to `gate_detail_json`.
- The incremental Sharpe implementation is intentionally a private copy of the logic in
  `strat_corr_augment` — not a call to that function — since `strategy_value_gate.R`
  lives in the installed package and the pipeline plans are not package exports.
