---
paths:
  - "R/plan_*backtest*.R"
  - "R/plan_*drif*.R"
  - "R/plan_*factor*.R"
  - "R/plan_*partition*.R"
  # Widened 2026-08-05: the globs above match only the files that COMPUTE
  # partitions, so this rule never loaded for the files that STORE, DISPLAY or
  # REASON ABOUT them. #660 (validation metrics published in vignette prose)
  # was written in a file no glob here matched. The seal follows the number,
  # so the paths must follow it too.
  - "R/plan_leaderboard.R"
  - "R/plan_qa_gates.R"
  - "R/plan_*metrics*.R"
  - "docs/*.qmd"
  - "vignettes/*.qmd"
  - "scripts/evaluate_validation.R"
---
# Rule: Mandatory Train/Test/Validation Partitions for Backtests

## When This Applies
Any project that backtests a trading strategy, signal, or model.

## CRITICAL: Three Partitions, Not Two

Every backtest MUST use a 3-way temporal split:

| Partition | Purpose | When to use |
|-----------|---------|-------------|
| **Training** | Model fitting, signal estimation, expanding window | During development |
| **Testing** | Calibration, hyperparameter tuning, strategy comparison | During development |
| **Validation** | Final one-shot evaluation | ONCE, before production |

A 2-way split (IS/OOS) is insufficient — "OOS" gets used for both tuning AND evaluation, which is snooping.

## Partition Boundaries

All strategies in a project MUST share partition dates from a single `bt_partitions` target:

```r
plan_partitions <- function() {
  list(targets::tar_target(bt_partitions, {
    list(
      equity = list(
        train_start = as.Date("2005-01-01"),
        train_end   = as.Date("2019-12-31"),
        test_start  = as.Date("2020-01-01"),
        test_end    = as.Date("2022-12-31"),
        val_start   = as.Date("2023-01-01"),
        val_end     = as.Date("2026-12-31")
      )
    )
  }))
}
```

## Validation Is Sealed

The seal is a claim about **what has been observed**, not about where a number is stored. It therefore constrains four things, not one. Every leak found on 2026-08-05 (see "Why this section is long", below) passed the first bullet and failed one of the others.

### 1. Computation

- Validation metrics are NOT computed automatically by `tar_make()`
- Validation requires an explicit manual target or script, never invoked by the pipeline
- A metric window that is *unbounded above* computes validation whether or not it says so — bound every automatic window at `test_end` (QA gate S11)
- Guard it: no automatically-computed metrics target may emit a row labelled `Validation` (QA gate S14)

### 2. Storage

- A sealed partition you compute but hide is still computed. Suppressing it at render time is not compliance — it is one filter away from exposure, and anyone reading the target directly (a developer, an agent, a scratch script) sees it
- **Never commit validation metrics to the repository.** A tracked artefact carrying them puts the sealed partition into git history, where it ships with the package and survives any later fix

### 3. Display

- No published surface — vignette, dashboard, README, email digest — may render a validation figure, in a table *or in prose*
- Reading the value from an upstream metrics target rather than the leaderboard does not change this. The seal follows the number, not the code path
- Labelling a printed value "sealed partition" does not seal it. That label documents an intention the code contradicts

### 4. Reasoning

- **This is the binding constraint, and the easiest to violate without noticing.** Once you look at validation results and change the strategy, the validation partition becomes another test set — the seal is broken
- Writing a *conclusion* drawn from validation data is the same act as changing the strategy. "Generalisation to sealed Validation has not held" in a Cons column has already conditioned the reader's judgement on the sealed sample, whether or not a code change followed
- Calling validation "the unbiased live-performance estimate" stops being true the moment it is read and reported
- If the seal is broken, **say so** and either re-cut a genuinely untouched window from the most recent data, or retire the sealed-validation claim for that strategy. Continuing to present a broken seal as intact is the worst of the three options

### Regardless of partition

- Document in the vignette which partition each metric comes from
- A whole-sample aggregate (`Full Period`) necessarily spans the validation window. This is permitted: it is one number that cannot be decomposed by eye into a validation view, and it is how headline backtest figures are conventionally reported. It is **not** a licence to report validation separately alongside it

## Why this section is long

It was four lines and constrained only computation. On 2026-08-05 four independent leaks were found in a single session, each of which satisfied the old wording:

| leak | passed | failed |
|---|---|---|
| unbounded `OOS` window ([#645](https://github.com/JohnGavin/historical/issues/645)) | not labelled `Validation` | computation — window had no upper bound |
| `leaderboard` Validation slice ([#648](https://github.com/JohnGavin/historical/issues/648)) | filtered from display | computation + storage |
| digest snapshot parquet ([#655](https://github.com/JohnGavin/historical/issues/655)) | not rendered | storage — committed to git |
| `stock-backtest.qmd` prose ([#660](https://github.com/JohnGavin/historical/issues/660)) | — | display **and reasoning** |

A rule that names one failure mode will be satisfied by code exhibiting the other three. See [`fail-loud-not-null`](fail-loud-not-null.md) for the general form of this pattern.

## Metrics Labelling

Every metrics table MUST label the partition:

```r
bind_rows(
  calc_metrics(train_data, "Training"),
  calc_metrics(test_data, "Testing"),
  calc_metrics(val_data, "Validation"),
  calc_metrics(all_data, "Full Period")
)
```

## Related Rules

- `statistical-reporting` — report partition alongside every metric
- `look-ahead-bias-prevention` — validation prevents peek-ahead
- `quarto-vignette-evidence` — vignettes must state which partition
- `backtest-robustness` — parameter sensitivity & regime testing
- `position-sizing-guardrails` — sizing comparison & max risk per bet
- `risk-regime-evaluation` — regime-conditional metrics
- `execution-delay-sensitivity` — alpha decay & delayed execution
- `underperformance-prior` — historically normal drawdown durations
- [`fail-loud-not-null`](fail-loud-not-null.md) — the general pattern: a rule naming one failure mode is satisfied by code exhibiting the others; every instance needs a gate, not just a test
