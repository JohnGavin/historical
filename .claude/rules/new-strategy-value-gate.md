---
name: new-strategy-value-gate
description: Advisory 5-check governance scorer for candidate strategy admission; requires pre-registration of expected metrics at decision time
type: rule
---

# Rule: New-Strategy Value Gate (Advisory, #496)

## When This Applies

Any decision to admit a new strategy into the leaderboard, pipeline, or portfolio.
Covers first-time registrations and material re-specifications (new asset class,
new frequency, materially changed signal).

Does NOT apply to: bug-fix patches to existing strategies, parameter sweeps within
a pre-registered range, or read-only backtesting for research purposes.

## CRITICAL: Gate Is Advisory — Records Verdicts, Never Blocks

The gate is **advisory in Phase 1**: failing a check produces a tidy tibble of
`"fail"` rows plus an `attr(result, "overall")` of `"reject"` or `"research_only"`,
and emits a `cli::cli_warn()`. It does NOT call `stop()` or abort the pipeline.
A failing strategy **can** be admitted with `override = TRUE` + `override_reason`.

**Phase 2** (separate PR, issue #496) will add candidate-vs-admitted separation
in `qa_leaderboard_coverage` and a pipeline gate target. Phase 3 (#482) adds the
expectation-vs-actual retro report.

## The 5 Checks

| # | Check | Key metric | Pass condition | Threshold |
|---|-------|-----------|----------------|-----------|
| 1 | **Similarity** | `correlation_max` = max \|Pearson ρ\| vs existing | < threshold | 0.80 (default) |
| 2 | **Incremental Sharpe** | Sharpe(EW with) − Sharpe(EW without) | > 0 (default) | 0 |
| 3 | **Diversification (EW)** | equal-weight ann. variance reduction (without − with) | > 0 | 0 |
| 3b | **Diversification (GMV)** | GMV variance reduction; computed via `hd_min_var_weights()` | > 0 | 0 |
| 4 | **Crowding** | published-t or logical flag (caller-supplied; advisory) | ≤ 3 / FALSE | advisory |
| 5 | **Robustness** | `robustness_pass` from CPCV/falsification gauntlet (caller-supplied) | TRUE | advisory |

Checks 1–3 are quantitative and drive the overall verdict. Checks 4–5 are advisory
inputs (caller-supplied; `"na"` when not provided).

### Incremental Sharpe Definition

Matches `strat_corr_augment` in `plan_strategy_correlation.R` exactly:

```
Sharpe(equal-weight candidate + existing) − Sharpe(equal-weight existing only)
```

where `Sharpe = CAGR / (sd(r) * sqrt(periods_per_year))` (geometric CAGR,
annualised vol). Positive = strategy adds value; negative = portfolio improves
without it.

### Overall Verdict Logic

```
"reject"        if similarity FAILS AND incremental_sharpe <= 0 AND
                   diversification_ew FAILS (all three quantitative checks bad)
"admit"         if checks 1, 2, and 3 (EW variant) all PASS
"research_only" otherwise (mixed results or any "na" in checks 1–3)
```

## Pre-Registration Requirement (MANDATORY)

Before admitting a strategy, record EXPECTED metrics at decision time using
`hd_admission_register()`. This creates an immutable pre-registration row in
the `strategy_admission` table (registry.duckdb).

Required fields to pre-register:

| Field | Why |
|-------|-----|
| `expected_incr_sharpe` | Pre-commit to the minimum improvement you expect |
| `expected_var_reduction` | Pre-commit to the diversification benefit you expect |
| `expected_target_regime` | Name the market regime the strategy is designed for |
| `expected_max_corr` | Declare the expected ceiling on correlation with existing strategies |
| `hypothesis` | One-paragraph rationale (evidence, not outcome) |
| `reviewer` | GitHub handle of the person admitting the strategy |

These are compared to realised metrics in the Phase 3 (#482) expectation-vs-actual
retro report, which feeds into `resulting-prohibition` checks.

### Idempotency Behaviour

`hd_admission_register()` uses upsert-by-strategy (one row per strategy).
On re-registration:
- `admission_uuid` and `admitted_at` are **preserved** (original admission is
  kept for audit).
- All other fields (reviewer, hypothesis, expected_*, gate_*) are **updated**.

## Decision Table

| Situation | Action |
|-----------|--------|
| Candidate ρ < 0.80 vs all existing, incr_sharpe > 0, var_reduc > 0 | Admit; pre-register via `hd_admission_register()` |
| Candidate ρ ≥ 0.80 vs any existing with higher Sharpe, incr_sharpe ≤ 0 | Reject; do not admit without documented exception |
| Mixed results (some pass, some fail) | "research_only"; investigate failing checks before admitting |
| Gate returns "reject" but override warranted (structural/regime reason) | Set `override = TRUE` with `override_reason`; document justification citing new evidence per `resulting-prohibition` |
| Robustness not yet run | Set `robustness_pass = NA`; schedule CPCV run; treat as "research_only" |

## Forbidden Patterns

| Pattern | Why wrong | Rule reference |
|---------|-----------|----------------|
| Admit a strategy ≥ 0.80 correlated with a higher-Sharpe existing strategy AND with negative incremental Sharpe | Mechanical admission inflates K_eff_strat (#160); adds no portfolio value | `backtest-robustness`, #496 |
| Admit based on in-sample performance with no crowding check | May be ADD flow, not genuine edge | `priced-in-prohibition` |
| Revise expected metrics AFTER seeing realised performance | Resulting — defeats the point of pre-registration | `resulting-prohibition` |
| Skip pre-registration ("we'll add it later") | Forfeits expectation-vs-actual comparison in Phase 3 | #496, #482 |
| Gate the pipeline (`tar_make` fails) in Phase 1 | Phase 1 is advisory-only; do NOT wire Phase 1 gate into pipeline | #496 Phase 1 scope |

## API Quick Reference

```r
# Score a candidate
result <- hd_strategy_value_gate(
  candidate        = my_returns,          # numeric vector
  existing         = existing_matrix,     # n x k matrix
  candidate_name   = "my_strategy",
  corr_threshold   = 0.80,
  min_incr_sharpe  = 0,
  periods_per_year = 12L,
  crowding         = 2.5,                 # published-t; NA if unknown
  robustness_pass  = TRUE                 # from CPCV gauntlet; NA if not run
)
attr(result, "overall")  # "admit" / "research_only" / "reject"

# Pre-register the decision
con  <- hd_registry_open(read_only = FALSE)
withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

uuid <- hd_admission_register(
  con        = con,
  strategy   = "my_strategy",
  hypothesis = "Adds trend-following diversification in EM; uncorrelated with value tilt",
  expected   = list(
    incr_sharpe   = 0.08,
    var_reduction = 0.002,
    target_regime = "trending",
    max_corr      = 0.35
  ),
  reviewer    = "john",
  gate_result = result   # serialised to gate_detail_json
)
```

## Related

- `resulting-prohibition` — judge strategy decisions by process, not outcome; pre-registration guards against post-hoc rationalisation
- `priced-in-prohibition` — checks 4 (crowding / ADD) and 5 (robustness) connect here
- `backtest-robustness` — check 5 (`robustness_pass`) comes from the CPCV/falsification gauntlet
- `cross-geography-pervasiveness` — check 5 should also verify multi-geography evidence
- [#496](https://github.com/JohnGavin/historical/issues/496) — origin issue; Phase 2 = pipeline wiring; Phase 3 = expectation-vs-actual retro
- [#270](https://github.com/JohnGavin/historical/issues/270) — leaderboard governance (parent)
- [#482](https://github.com/JohnGavin/historical/issues/482) — expectation-vs-actual retro report (Phase 3)
- `knowledge/wiki/new-strategy-value-gate.md` — full rationale digest
