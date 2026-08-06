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
# Rule: Mandatory Train/Test/Holdout/Validation Partitions for Backtests

## When This Applies
Any project that backtests a trading strategy, signal, or model.

## CRITICAL: Four Partitions, Not Two

Every backtest MUST use a temporal split with, at minimum, Training/Testing/Validation. This project additionally uses a fourth tier, **Holdout**, added at [#660](https://github.com/JohnGavin/historical/issues/660) — see that section below for why.

| Partition | Purpose | When to use | Sealed? |
|-----------|---------|-------------|---------|
| **Training** | Model fitting, signal estimation, expanding window | During development | n/a |
| **Testing** | Calibration, hyperparameter tuning, strategy comparison | During development | n/a |
| **Holdout** | Observed data retained for evaluation, with a stated discount | Ongoing, automatic | **NO — observed, never sealed** |
| **Validation** | Final one-shot evaluation | ONCE, before production | **YES** |

A 2-way split (IS/OOS) is insufficient — "OOS" gets used for both tuning AND evaluation, which is snooping.

## Partition Boundaries

All strategies in a project MUST share partition dates from a single `bt_partitions` target:

```r
plan_partitions <- function() {
  list(targets::tar_target(bt_partitions, {
    list(
      equity = list(
        train_start   = as.Date("2005-01-01"),
        train_end     = as.Date("2019-12-31"),
        test_start    = as.Date("2020-01-01"),
        test_end      = as.Date("2023-12-31"),
        holdout_start = as.Date("2024-01-01"),
        holdout_end   = as.Date("2026-04-30"),
        val_start     = as.Date("2026-05-01"),
        val_end       = as.Date("2026-12-31")
      )
    )
  }))
}
```

## Holdout: Observed, Not Sealed ([#660](https://github.com/JohnGavin/historical/issues/660))

**Holdout is observed data, deliberately retained for evaluation; it is NOT sealed and must never be described as such.**

### Why this tier exists

The original two-way Testing/Validation split (`test_end = 2022-12-31`, `val_start = 2023-01-01`) was burned: [#660](https://github.com/JohnGavin/historical/issues/660) found `docs/stock-backtest.qmd` publishing Validation figures in prose and drawing a strategy conclusion from them — a violation of the Reasoning clause below. Fixing the display ([#660](https://github.com/JohnGavin/historical/issues/660)/PR #662) and the computation ([#648](https://github.com/JohnGavin/historical/issues/648)/PR #659) did not un-observe the partition itself: the seal is a claim about what has been read, and by the time those PRs landed, the 2023-2026 span had already been read and reasoned from.

Every month from 2024-01 to the data boundary (2026-04-15 equity, 2026-02-27 factor as of #660) sits inside the block that was published, so no re-slicing of *existing* data yields a genuinely clean window — the entire 2024-2026 span is observed. The only unobserved data is **2026-05-01 onwards**: the first month past the current data boundary. That is why the re-cut moves `val_start` there rather than to any earlier date, and introduces `Holdout` to cover the 2024-2026 span honestly instead of either (a) pretending it is still sealed, or (b) discarding two years of otherwise-usable evaluation data.

### What Holdout is and is not

- Holdout **is** computed automatically by `tar_make()` — deliberately, unlike Validation. There is no seal to preserve here; hiding it would gain nothing.
- Holdout **is** usable for evaluation, with a stated discount relative to a genuinely untouched sample — it has been read once (by whoever wrote the #660-era prose) and should be weighted accordingly, not treated as pristine.
- Holdout is **NOT** a one-shot result. It may be recomputed, inspected, and discussed repeatedly — that is the point of separating it from Validation.
- Holdout must **NEVER** be labelled "sealed", "sealed partition", or "one-shot evaluation" on any published surface. Doing so would repeat the exact #660 defect one tier down.
- QA gate S11 (`check_metric_window_bounds()`, R/plan_qa_gates.R) exempts `"Holdout"` from the `test_end` bound, the same way it exempts `"Validation"` and `"Full Period"` — Holdout's whole purpose is to extend past `test_end`.
- QA gate S14 (`check_leaderboard_no_validation_rows()`) is **unchanged in intent**: it still rejects only `"Validation"` rows. Holdout rows are allowed on the automatic path — that is the entire point of the tier.

## Validation Is Sealed

The seal is a claim about **what has been observed**, not about where a number is stored. It therefore constrains four things, not one. Every leak found on 2026-08-05 (see "Why this section is long", below) passed the first bullet and failed one of the others.

### 1. Computation

- Validation metrics are NOT computed automatically by `tar_make()`
- Validation requires an explicit manual target or script, never invoked by the pipeline
- A metric window that is *unbounded above* computes validation whether or not it says so — bound every automatic window at `test_end` (QA gate S11)
- Guard it: no automatically-computed metrics target may emit a row labelled `Validation` (QA gate S14)
- **Holdout is the one deliberate exception to "not computed automatically"** — it is allowed on the automatic path because it was never sealed in the first place (see the "Holdout: Observed, Not Sealed" section above). Do not read this bullet as licence to compute Validation automatically; Holdout and Validation are different partitions with different rules

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

### The re-cut ([#660](https://github.com/JohnGavin/historical/issues/660) resolution)

The `stock-backtest.qmd` prose leak above was the fourth leak in the same session, and the most severe: it was a *reasoning* violation, not just a display one. Removing the printed values (the display-side fix) could not undo the fact that the 2023-2026 partition had already been read and reasoned from — the seal on that specific span was permanently broken. The project chose [option 2 from the issue](https://github.com/JohnGavin/historical/issues/660): reclassify the burned span as a fourth tier, `Holdout`, and cut a new, genuinely untouched `Validation` window starting at the first month past the current data boundary (2026-05-01). See the "Holdout: Observed, Not Sealed" section above for the full boundary rationale.

## Metrics Labelling

Every metrics table MUST label the partition:

```r
bind_rows(
  calc_metrics(train_data, "Training"),
  calc_metrics(test_data, "Testing"),
  calc_metrics(holdout_data, "Holdout"),
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
