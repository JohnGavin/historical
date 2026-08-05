---
paths:
  - "R/plan_*backtest*.R"
  - "R/plan_*drif*.R"
  - "R/plan_*factor*.R"
  - "R/plan_*partition*.R"
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

- Validation metrics are NOT computed automatically by `tar_make()`
- Validation requires an explicit manual target or script
- Once you look at validation results and change the strategy, the validation partition becomes another test set — the seal is broken
- Document in the vignette which partition each metric comes from

**The seal covers display and reasoning, not only computation.** A source
metrics target may legitimately compute a `"Validation"` row for other
consumers (e.g. `scripts/evaluate_validation.R`) — that is not itself a
violation. The violation is reading that row into a **published document**
(a rendered `.qmd`, a table, a prose sentence) or drawing a **conclusion**
from it (a Pros/Cons verdict, a "generalisation has/hasn't held" claim). Both
are breaches of the seal even when no code change followed, because the
partition's value depends on the values never having been looked at
(#660). Every published document is scanned for a literal
`period == "Validation"` read by the `qa_no_published_validation_reads`
gate (S15, `R/plan_qa_gates.R`) — the sanctioned exception is
`scripts/evaluate_validation.R`, the one-shot manual evaluation route.

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
